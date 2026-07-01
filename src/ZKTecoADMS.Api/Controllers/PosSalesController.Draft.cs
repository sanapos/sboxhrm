using ClosedXML.Excel;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
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
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<SaleOrderDto>>> CompleteSale(Guid id)
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

        order.Status = PosSaleOrderStatus.Completed;
        order.SaleDate ??= DateTime.UtcNow;
        order.SoldBy ??= CurrentUserEmail;
        order.PaidAmount = order.PaidAmount > 0 ? order.PaidAmount : order.Total;
        await PosSaleStockHelper.ApplySaleStockAsync(
            dbContext, storeId, order, order.Lines.ToList(), plan!, CurrentUserEmail);
        await PosSaleStockHelper.UpdateCustomerOnSaleCompleteAsync(dbContext, storeId, order);
        order.UpdatedAt = DateTime.UtcNow;
        order.UpdatedBy = CurrentUserEmail;
        await PosFinanceSyncHelper.SyncSaleOnCompleteAsync(dbContext, order, CurrentUserId);
        await dbContext.SaveChangesAsync();

        await PosNotificationHelper.NotifySaleCompletedAsync(
            notificationService, dbContext, storeId, order.Id, order.OrderNo,
            order.Total, order.SoldBy, CurrentUserId);

        return Ok(AppResponse<SaleOrderDto>.Success(await MapOrderAsync(storeId, order)));
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
                OrderNo = await PosSaleStockHelper.NextOrderNoAsync(dbContext, storeId),
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
        order.PriceListName = dto.PriceListName?.Trim() ?? "Bảng giá chung";
        order.UpdatedAt = DateTime.UtcNow;
        order.UpdatedBy = CurrentUserEmail;

        var lines = new List<PosSaleOrderLine>();
        decimal subTotal = 0;
        decimal lineDiscountTotal = 0;
        foreach (var line in dto.Lines)
        {
            var p = products[line.ProductId];
            PosProductVariant? soldVariant = null;
            if (line.VariantId.HasValue)
                variants.TryGetValue(line.VariantId.Value, out soldVariant);

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
        order.Total = subTotal - lineDiscountTotal - dto.Discount;

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
            order.PaidAmount = complete
                ? (dto.PaidAmount > 0 ? dto.PaidAmount : order.Total)
                : dto.PaidAmount;
        }

        var paymentSync = paymentInputs
            .Select(p => new PosFinanceSyncHelper.SalePaymentSync(p.Amount, p.PaymentMethod, p.BankAccountId))
            .ToList();

        if (complete && plan != null)
        {
            await PosSaleStockHelper.ApplySaleStockAsync(
                dbContext, storeId, order, lines, plan, CurrentUserEmail);
            await PosSaleStockHelper.UpdateCustomerOnSaleCompleteAsync(dbContext, storeId, order);
            await PosFinanceSyncHelper.SyncSaleOnCompleteAsync(
                dbContext, order, CurrentUserId, paymentSync);

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
