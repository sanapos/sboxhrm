using ClosedXML.Excel;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System.Data;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Api.Controllers.Reports;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

public partial class PosSalesController
{
    [HttpPut("{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<SaleOrderDto>>> UpdateSale(Guid id, [FromBody] UpdateSaleDto dto)
    {
        var storeId = RequiredStoreId;
        var order = await dbContext.PosSaleOrders
            .Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId && o.Deleted == null);
        if (order == null)
            return NotFound(AppResponse<SaleOrderDto>.Fail("Không tìm thấy đơn hàng"));
        if (order.Status != PosSaleOrderStatus.Draft)
            return BadRequest(AppResponse<SaleOrderDto>.Fail("Chỉ sửa được đơn tạm"));

        dbContext.PosSaleOrderLines.RemoveRange(order.Lines);
        var createDto = new CreateSaleDto(
            dto.Lines, dto.Discount, dto.PaidAmount, dto.PaymentMethod,
            dto.CustomerName, dto.CustomerId, dto.Note, dto.Complete,
            dto.IsDelivery, dto.DeliveryAddress, dto.DeliveryPhone,
            dto.DeliveryPartner, dto.DeliveryStatus, dto.DeliveryDate,
            dto.SoldBy, dto.SoldByEmployeeId, dto.SalesChannel, dto.PriceListName);
        var (_, lines, err) = await BuildSaleAsync(storeId, order, createDto, dto.Complete);
        if (err != null) return BadRequest(AppResponse<SaleOrderDto>.Fail(err));
        if (lines == null)
            return BadRequest(AppResponse<SaleOrderDto>.Fail("Không cập nhật được đơn"));

        dbContext.PosSaleOrderLines.AddRange(lines);
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<SaleOrderDto>.Success(await MapOrderAsync(storeId, order)));
    }

    [HttpPost("{id:guid}/complete")]
    [RequireModulePermission("PosSaleOrders", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<SaleOrderDto>>> CompleteSale(
        Guid id, [FromBody] CompleteSaleDto? dto = null)
    {
        var storeId = RequiredStoreId;
        var order = await dbContext.PosSaleOrders
            .Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId && o.Deleted == null);
        if (order == null)
            return NotFound(AppResponse<SaleOrderDto>.Fail("Không tìm thấy đơn hàng"));
        if (order.Status != PosSaleOrderStatus.Draft)
            return BadRequest(AppResponse<SaleOrderDto>.Fail("Đơn không ở trạng thái tạm"));
        if (order.Lines.Count == 0)
            return BadRequest(AppResponse<SaleOrderDto>.Fail("Đơn trống"));

        var lineInputs = order.Lines.Select(l => (l.ProductId, l.Qty, l.VariantId)).ToList();
        var (plan, stockErr) = await PosSaleStockHelper.PrepareSaleStockAsync(dbContext, storeId, lineInputs);
        if (stockErr != null) return BadRequest(AppResponse<SaleOrderDto>.Fail(stockErr));

        var productIds = order.Lines.Select(l => l.ProductId).Distinct().ToList();
        var products = plan?.Products ?? await dbContext.PosProducts
            .Where(p => productIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
            .ToDictionaryAsync(p => p.Id);

        var dtoLines = BuildCompleteSaleLineDtos(order.Lines.ToList(), dto?.Lines);
        var warrantyLines = dtoLines
            .Where(l => products.TryGetValue(l.ProductId, out var wp) &&
                        PosSaleWarrantyHelper.NeedsRegistration(wp))
            .Select(l => (l, products[l.ProductId]))
            .ToList();
        if (warrantyLines.Count > 0)
        {
            var warrantyErr = await PosSaleWarrantyHelper.ValidateSerialsAsync(
                dbContext, storeId, warrantyLines);
            if (warrantyErr != null) return BadRequest(AppResponse<SaleOrderDto>.Fail(warrantyErr));
        }

        order.Status = PosSaleOrderStatus.Completed;
        order.SaleDate ??= DateTime.UtcNow;
        order.SoldBy ??= CurrentUserEmail;
        order.PaidAmount = order.PaidAmount > 0 ? order.PaidAmount : 0;

        await using var tx = await dbContext.Database.BeginTransactionAsync(IsolationLevel.RepeatableRead);
        try
        {
            await PosSaleStockHelper.ApplySaleStockAsync(
                dbContext, storeId, order, order.Lines.ToList(), plan!, CurrentUserEmail);
            await PosSaleStockHelper.UpdateCustomerOnSaleCompleteAsync(dbContext, storeId, order);
            if (order.CustomerId.HasValue)
            {
                var saleCustomer = await dbContext.PosCustomers.AsTracking()
                    .FirstOrDefaultAsync(c => c.Id == order.CustomerId && c.StoreId == storeId && c.Deleted == null);
                if (saleCustomer != null)
                {
                    await PosCustomerFinanceHelper.ApplyPointsOnSaleCompleteAsync(
                        dbContext, storeId, order, saleCustomer, CurrentUserEmail);
                    if (order.VoucherId.HasValue)
                    {
                        var vch = await dbContext.PosVouchers.AsTracking()
                            .FirstOrDefaultAsync(v => v.Id == order.VoucherId && v.StoreId == storeId);
                        if (vch != null)
                        {
                            vch.UsedCount += 1;
                            vch.UpdatedAt = DateTime.UtcNow;
                        }
                    }
                }
            }
            await PosSaleWarrantyHelper.RegisterOnSaleAsync(
                dbContext, storeId, order, order.Lines.ToList(), dtoLines, products, CurrentUserEmail);
            order.UpdatedAt = DateTime.UtcNow;
            order.UpdatedBy = CurrentUserEmail;
            await PosFinanceSyncHelper.SyncSaleOnCompleteAsync(dbContext, order, CurrentUserId);
            await dbContext.SaveChangesAsync();
            await tx.CommitAsync();
        }
        catch
        {
            await tx.RollbackAsync();
            throw;
        }

        var lowStockItems = plan!.Products.Values
            .Select(p => (p.Id, p.Name, p.OnHandQty, p.MinStockQty));
        await PosNotificationHelper.NotifyLowStockAsync(
            notificationService, dbContext, storeId, lowStockItems, CurrentUserId);

        await PosNotificationHelper.NotifySaleCompletedAsync(
            notificationService, dbContext, storeId, order.Id, order.OrderNo,
            order.Total, order.SoldBy, CurrentUserId);

        return Ok(AppResponse<SaleOrderDto>.Success(await MapOrderAsync(storeId, order)));
    }

    private static List<SaleLineDto> BuildCompleteSaleLineDtos(
        List<PosSaleOrderLine> orderLines, List<SaleLineDto>? inputLines)
    {
        if (inputLines == null || inputLines.Count == 0)
        {
            return orderLines.Select(l => new SaleLineDto(
                l.ProductId, l.Qty, null, l.UnitPrice, l.VariantId)).ToList();
        }

        var byKey = inputLines.ToDictionary(
            l => (l.ProductId, l.VariantId), l => l);

        return orderLines.Select(l =>
        {
            if (byKey.TryGetValue((l.ProductId, l.VariantId), out var matched))
                return matched with { Qty = l.Qty };
            return new SaleLineDto(l.ProductId, l.Qty, null, l.UnitPrice, l.VariantId);
        }).ToList();
    }

    [HttpGet("export/excel")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Export)]
    public async Task<IActionResult> ExportExcel(
        [FromQuery] string? search,
        [FromQuery] string? statuses,
        [FromQuery] string? paymentMethod,
        [FromQuery] bool? isDelivery,
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to)
    {
        var storeId = RequiredStoreId;
        var query = dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive);

        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            query = query.Where(o => o.OrderNo.ToLower().Contains(s) ||
                                     (o.CustomerName != null && o.CustomerName.ToLower().Contains(s)));
        }
        if (!string.IsNullOrWhiteSpace(statuses))
        {
            var statusList = statuses.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Select(s => Enum.TryParse<PosSaleOrderStatus>(s, true, out var x) ? x : (PosSaleOrderStatus?)null)
                .Where(x => x.HasValue).Select(x => x!.Value).Distinct().ToList();
            if (statusList.Count > 0)
                query = query.Where(o => statusList.Contains(o.Status));
        }
        if (!string.IsNullOrWhiteSpace(paymentMethod))
            query = query.Where(o => o.PaymentMethod.Contains(paymentMethod.Trim()));
        if (isDelivery.HasValue)
            query = query.Where(o => o.IsDelivery == isDelivery.Value);
        if (from.HasValue)
            query = query.Where(o => (o.SaleDate ?? o.CreatedAt) >= from.Value.Date);
        if (to.HasValue)
            query = query.Where(o => (o.SaleDate ?? o.CreatedAt) < to.Value.Date.AddDays(1));

        var items = await query.OrderByDescending(o => o.SaleDate ?? o.CreatedAt).Take(5000).ToListAsync();

        using var workbook = new XLWorkbook();
        var ws = workbook.Worksheets.Add("Don hang");
        var headers = new[]
        {
            "Mã đơn", "Thời gian", "Trạng thái", "Khách hàng", "Giao hàng",
            "TT giao hàng", "Tạm tính", "Giảm giá", "Tổng", "Đã trả", "Còn lại", "Thanh toán", "Người bán"
        };
        var periodLabel = from.HasValue || to.HasValue
            ? $"{from?.ToString("dd/MM/yyyy") ?? "…"} – {to?.ToString("dd/MM/yyyy") ?? "…"}"
            : null;
        var meta = ReportExcelMeta.FromUser(User, "DANH SÁCH ĐƠN HÀNG", periodLabel, null,
            new[] { $"Tổng: {items.Count}" }, items.Count);
        var (headerRow, dataStartRow) = ReportExcelLayout.ApplyMeta(ws, meta, headers.Length);
        ReportExcelLayout.ApplyHeaderRow(ws, headerRow, headers);
        var row = dataStartRow;
        foreach (var o in items)
        {
            var dt = o.SaleDate ?? o.CreatedAt;
            ws.Cell(row, 1).Value = o.OrderNo;
            ws.Cell(row, 2).Value = dt.ToString("dd/MM/yyyy HH:mm");
            ws.Cell(row, 3).Value = o.Status switch
            {
                PosSaleOrderStatus.Draft => "Đang xử lý",
                PosSaleOrderStatus.Completed => "Hoàn thành",
                PosSaleOrderStatus.Cancelled => "Đã hủy",
                _ => o.Status.ToString()
            };
            ws.Cell(row, 4).Value = o.CustomerName ?? "Khách lẻ";
            ws.Cell(row, 5).Value = o.IsDelivery ? "Có" : "Không";
            ws.Cell(row, 6).Value = o.DeliveryStatus ?? "";
            ws.Cell(row, 7).Value = o.SubTotal;
            ws.Cell(row, 8).Value = o.Discount;
            ws.Cell(row, 9).Value = o.Total;
            ws.Cell(row, 10).Value = o.PaidAmount;
            ws.Cell(row, 11).Value = o.Total - o.PaidAmount;
            ws.Cell(row, 12).Value = o.PaymentMethod;
            ws.Cell(row, 13).Value = o.SoldBy ?? "";
            row++;
        }
        ws.Columns(1, headers.Length).AdjustToContents();
        using var stream = new MemoryStream();
        workbook.SaveAs(stream);
        return File(stream.ToArray(),
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            $"DonHang_{DateTime.Now:yyyyMMdd}.xlsx");
    }

    private async Task<(PosSaleOrder? order, List<PosSaleOrderLine>? lines, string? error)> BuildSaleAsync(
        Guid storeId,
        PosSaleOrder? existing,
        CreateSaleDto dto,
        bool complete)
    {
        if (dto.Lines == null || dto.Lines.Count == 0)
            return (null, null, "Đơn hàng trống");

        if (dto.CustomerId.HasValue && !await dbContext.PosCustomers.AnyAsync(c =>
                c.Id == dto.CustomerId && c.StoreId == storeId && c.Deleted == null))
            return (null, null, "Khách hàng không hợp lệ");

        SaleStockPlan? plan = null;
        if (complete)
        {
            var lineInputs = dto.Lines.Select(l => (l.ProductId, l.Qty, l.VariantId)).ToList();
            var (p, stockErr) = await PosSaleStockHelper.PrepareSaleStockAsync(dbContext, storeId, lineInputs);
            if (stockErr != null) return (null, null, stockErr);
            plan = p;
        }

        var productIds = dto.Lines.Select(l => l.ProductId).Distinct().ToList();
        var variantIds = dto.Lines.Where(l => l.VariantId.HasValue)
            .Select(l => l.VariantId!.Value).Distinct().ToList();
        var products = plan?.Products ?? await dbContext.PosProducts
            .Where(p => productIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
            .ToDictionaryAsync(p => p.Id);
        var variants = plan?.Variants ?? (variantIds.Count == 0
            ? new Dictionary<Guid, PosProductVariant>()
            : await dbContext.PosProductVariants
                .Where(v => variantIds.Contains(v.Id) && v.StoreId == storeId && v.Deleted == null && v.IsActive)
                .ToDictionaryAsync(v => v.Id));

        var now = DateTime.UtcNow;
        PosSaleOrder order;
        if (existing == null)
        {
            order = new PosSaleOrder
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                OrderNo = await PosSaleStockHelper.NextOrderNoAsync(dbContext, storeId, now),
                IsActive = true,
                CreatedBy = CurrentUserEmail,
            };
        }
        else
        {
            order = existing;
        }

        order.Status = complete ? PosSaleOrderStatus.Completed : PosSaleOrderStatus.Draft;
        order.Discount = dto.Discount;
        order.PaymentMethod = string.IsNullOrWhiteSpace(dto.PaymentMethod) ? "Tiền mặt" : dto.PaymentMethod.Trim();
        order.CustomerId = dto.CustomerId;
        order.CustomerName = dto.CustomerName?.Trim();
        if (dto.CustomerId.HasValue && string.IsNullOrWhiteSpace(order.CustomerName))
        {
            var cust = await dbContext.PosCustomers.AsNoTracking()
                .FirstOrDefaultAsync(c => c.Id == dto.CustomerId && c.StoreId == storeId);
            order.CustomerName = cust?.Name;
        }
        order.Note = dto.Note?.Trim();
        order.IsDelivery = dto.IsDelivery;
        order.DeliveryAddress = dto.DeliveryAddress?.Trim();
        order.DeliveryPhone = dto.DeliveryPhone?.Trim();
        order.DeliveryPartner = dto.DeliveryPartner?.Trim();
        order.DeliveryStatus = dto.IsDelivery
            ? (string.IsNullOrWhiteSpace(dto.DeliveryStatus) ? "Chờ giao" : dto.DeliveryStatus.Trim())
            : null;
        order.DeliveryDate = dto.DeliveryDate;
        order.SaleDate = complete ? now : order.SaleDate;
        await ResolveSoldByAsync(storeId, order, dto.SoldByEmployeeId, dto.SoldBy);
        order.SalesChannel = dto.SalesChannel?.Trim() ?? "Bán trực tiếp";
        if (dto.PriceListId.HasValue)
        {
            var pl = await dbContext.PosPriceLists.AsNoTracking()
                .FirstOrDefaultAsync(x => x.Id == dto.PriceListId && x.StoreId == storeId && x.Deleted == null);
            if (pl == null)
                return (null, null, "Bảng giá không hợp lệ");
            order.PriceListId = pl.Id;
            order.PriceListName = pl.Name;
        }
        else
        {
            var defaultPl = await dbContext.PosPriceLists.AsNoTracking()
                .FirstOrDefaultAsync(x => x.StoreId == storeId && x.IsDefault && x.Deleted == null);
            if (defaultPl == null)
            {
                defaultPl = await dbContext.PosPriceLists.AsNoTracking()
                    .Where(x => x.StoreId == storeId && x.Deleted == null && x.IsActive)
                    .OrderByDescending(x => x.IsDefault).ThenBy(x => x.SortOrder)
                    .FirstOrDefaultAsync();
            }
            if (defaultPl != null)
            {
                order.PriceListId = defaultPl.Id;
                order.PriceListName = defaultPl.Name;
            }
            else
            {
                order.PriceListName = string.IsNullOrWhiteSpace(dto.PriceListName)
                    ? "Bảng giá chung"
                    : dto.PriceListName.Trim();
            }
        }
        order.UpdatedAt = DateTime.UtcNow;
        order.UpdatedBy = CurrentUserEmail;

        var lines = new List<PosSaleOrderLine>();
        decimal subTotal = 0;
        decimal lineDiscountTotal = 0;
        foreach (var line in dto.Lines)
        {
            if (!products.TryGetValue(line.ProductId, out var p))
                return (null, null, "Hàng hóa không hợp lệ hoặc đã ngừng kinh doanh");

            PosProductVariant? soldVariant = null;
            if (line.VariantId.HasValue)
            {
                if (!variants.TryGetValue(line.VariantId.Value, out soldVariant))
                    return (null, null, "Biến thể hàng hóa không hợp lệ");
            }

            var unitPrice = line.UnitPrice ?? soldVariant?.BasePrice ?? p.BasePrice;
            string? unitName = p.BaseUnitName;
            var lineName = soldVariant != null ? $"{p.Name} — {soldVariant.Name}" : p.Name;

            if (line.UnitId.HasValue)
            {
                var unit = await dbContext.PosProductUnits.AsNoTracking()
                    .FirstOrDefaultAsync(u => u.Id == line.UnitId && u.ProductId == p.Id && u.Deleted == null);
                if (unit != null)
                {
                    unitName = unit.UnitName;
                    if (!line.UnitPrice.HasValue) unitPrice = unit.BasePrice;
                }
            }
            else if (soldVariant?.AttributeJson != null)
            {
                try
                {
                    using var doc = System.Text.Json.JsonDocument.Parse(soldVariant.AttributeJson);
                    if (doc.RootElement.TryGetProperty("_unit", out var uEl))
                        unitName = uEl.GetString();
                }
                catch { /* ignore */ }
            }

            var grossLine = unitPrice * line.Qty;
            var discAmt = Math.Max(0, Math.Min(line.DiscountAmount, grossLine));
            var lineTotal = grossLine - discAmt;
            subTotal += grossLine;
            lineDiscountTotal += discAmt;
            lines.Add(new PosSaleOrderLine
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                SaleOrderId = order.Id,
                ProductId = p.Id,
                VariantId = soldVariant?.Id,
                ProductName = lineName,
                UnitName = unitName,
                Qty = line.Qty,
                UnitPrice = unitPrice,
                DiscountAmount = discAmt,
                LineTotal = lineTotal,
                LineNote = string.IsNullOrWhiteSpace(line.LineNote) ? null : line.LineNote.Trim(),
                IsActive = true,
                CreatedBy = CurrentUserEmail,
            });
        }

        order.SubTotal = subTotal;
        var merchandise = subTotal - lineDiscountTotal - dto.Discount;
        if (merchandise < 0) merchandise = 0;

        var voucherApply = await PosCustomerFinanceHelper.TryApplyVoucherAsync(
            dbContext, storeId, dto.VoucherCode, merchandise, dto.CustomerId);
        if (voucherApply?.Error != null)
            return (null, null, voucherApply.Error);
        decimal voucherDiscount = 0;
        PosVoucher? appliedVoucher = null;
        if (voucherApply != null)
        {
            appliedVoucher = voucherApply.Voucher;
            voucherDiscount = voucherApply.DiscountAmount;
            order.VoucherId = appliedVoucher.Id;
            order.VoucherCode = appliedVoucher.Code;
            order.VoucherDiscount = voucherDiscount;
        }

        var afterVoucher = merchandise - voucherDiscount;
        if (dto.PointsToRedeem > 0)
        {
            if (!dto.CustomerId.HasValue)
                return (null, null, "Cần chọn khách hàng để đổi điểm");
            var ptCust = await dbContext.PosCustomers.AsNoTracking()
                .FirstOrDefaultAsync(c => c.Id == dto.CustomerId && c.StoreId == storeId && c.Deleted == null);
            if (ptCust == null) return (null, null, "Khách hàng không hợp lệ");
            var (ptDisc, ptRedeem, ptErr) = PosCustomerFinanceHelper.CalcPointsRedeem(
                dto.PointsToRedeem, ptCust.PointBalance, afterVoucher);
            if (ptErr != null) return (null, null, ptErr);
            order.PointsRedeemed = ptRedeem;
            order.PointsDiscount = ptDisc;
        }

        order.Total = Math.Max(0, afterVoucher - order.PointsDiscount);
        order.PointsEarned = complete && dto.CustomerId.HasValue
            ? PosCustomerFinanceHelper.CalcPointsEarn(order.Total)
            : 0;

        var paymentInputs = dto.Payments?
            .Where(p => p.Amount > 0)
            .ToList() ?? [];
        if (paymentInputs.Count == 0 && dto.PaidAmount > 0)
        {
            paymentInputs.Add(new SalePaymentInputDto(
                dto.PaidAmount,
                string.IsNullOrWhiteSpace(dto.PaymentMethod) ? "Tiền mặt" : dto.PaymentMethod.Trim()));
        }

        if (paymentInputs.Count > 0)
        {
            order.PaidAmount = paymentInputs.Sum(p => p.Amount);
            order.PaymentMethod = string.Join(" + ", paymentInputs.Select(p => p.PaymentMethod));
        }
        else
        {
            order.PaidAmount = dto.PaidAmount;
        }

        var paymentSync = paymentInputs
            .Select(p => new PosFinanceSyncHelper.SalePaymentSync(p.Amount, p.PaymentMethod, p.BankAccountId))
            .ToList();

        if (complete && plan != null)
        {
            var warrantyLines = dto.Lines
                .Where(l => products.TryGetValue(l.ProductId, out var wp) &&
                            PosSaleWarrantyHelper.NeedsRegistration(wp))
                .Select(l => (l, products[l.ProductId]))
                .ToList();
            if (warrantyLines.Count > 0)
            {
                var warrantyErr = await PosSaleWarrantyHelper.ValidateSerialsAsync(
                    dbContext, storeId, warrantyLines);
                if (warrantyErr != null) return (null, null, warrantyErr);
            }

            await PosSaleStockHelper.ApplySaleStockAsync(
                dbContext, storeId, order, lines, plan, CurrentUserEmail);
            await PosSaleStockHelper.UpdateCustomerOnSaleCompleteAsync(dbContext, storeId, order);
            if (order.CustomerId.HasValue)
            {
                var saleCustomer = await dbContext.PosCustomers.AsTracking()
                    .FirstOrDefaultAsync(c => c.Id == order.CustomerId && c.StoreId == storeId && c.Deleted == null);
                if (saleCustomer != null)
                {
                    await PosCustomerFinanceHelper.ApplyPointsOnSaleCompleteAsync(
                        dbContext, storeId, order, saleCustomer, CurrentUserEmail);
                    if (appliedVoucher != null)
                    {
                        appliedVoucher.UsedCount += 1;
                        appliedVoucher.UpdatedAt = DateTime.UtcNow;
                    }
                }
            }
            await PosFinanceSyncHelper.SyncSaleOnCompleteAsync(
                dbContext, order, CurrentUserId, paymentSync);
            await PosSaleWarrantyHelper.RegisterOnSaleAsync(
                dbContext, storeId, order, lines, dto.Lines, products, CurrentUserEmail);

            var lowStockItems = plan.Products.Values
                .Select(p => (p.Id, p.Name, p.OnHandQty, p.MinStockQty));
            await PosNotificationHelper.NotifyLowStockAsync(
                notificationService, dbContext, storeId, lowStockItems, CurrentUserId);
        }

        return (order, lines, null);
    }

    private async Task ResolveSoldByAsync(
        Guid storeId, PosSaleOrder order, Guid? soldByEmployeeId, string? soldByFallback)
    {
        var employeeId = soldByEmployeeId ?? EmployeeId;
        if (employeeId.HasValue)
        {
            var emp = await dbContext.Employees.AsNoTracking()
                .FirstOrDefaultAsync(e => e.Id == employeeId.Value &&
                                          e.StoreId == storeId && e.Deleted == null);
            if (emp != null)
            {
                order.SoldByEmployeeId = emp.Id;
                var name = (emp.LastName + " " + emp.FirstName).Trim();
                order.SoldBy = !string.IsNullOrWhiteSpace(name)
                    ? name
                    : soldByFallback?.Trim() ?? emp.CompanyEmail ?? CurrentUserEmail;
                return;
            }
        }

        order.SoldByEmployeeId = null;
        order.SoldBy = soldByFallback?.Trim() ?? CurrentUserEmail;
    }
}
