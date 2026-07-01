using ClosedXML.Excel;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Controllers.Reports;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/pos/reports")]
[Authorize]
public class PosReportsController(ZKTecoDbContext dbContext) : AuthenticatedControllerBase
{
    [HttpGet("sales/summary")]
    [RequireModulePermission("PosSalesReport", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetSalesSummary(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to)
    {
        var storeId = RequiredStoreId;
        var fromDt = from?.Date ?? DateTime.UtcNow.Date.AddDays(-30);
        var toDt = (to?.Date ?? DateTime.UtcNow.Date).AddDays(1);

        var orders = dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive &&
                        o.Status == PosSaleOrderStatus.Completed &&
                        o.CreatedAt >= fromDt && o.CreatedAt < toDt);

        var totalRevenue = await orders.SumAsync(o => o.Total);
        var totalPaid = await orders.SumAsync(o => o.PaidAmount);
        var totalDiscount = await orders.SumAsync(o => o.Discount);
        var orderCount = await orders.CountAsync();

        var byPayment = await orders
            .GroupBy(o => o.PaymentMethod)
            .Select(g => new { paymentMethod = g.Key, total = g.Sum(x => x.Total), count = g.Count() })
            .OrderByDescending(x => x.total)
            .ToListAsync();

        var byDay = await orders
            .GroupBy(o => o.CreatedAt.Date)
            .Select(g => new { date = g.Key, total = g.Sum(x => x.Total), count = g.Count() })
            .OrderBy(x => x.date)
            .ToListAsync();

        var topProducts = await dbContext.PosSaleOrderLines.AsNoTracking()
            .Where(l => l.StoreId == storeId && l.Deleted == null &&
                        l.SaleOrder != null && l.SaleOrder.Deleted == null &&
                        l.SaleOrder.Status == PosSaleOrderStatus.Completed &&
                        l.SaleOrder.CreatedAt >= fromDt && l.SaleOrder.CreatedAt < toDt)
            .GroupBy(l => new { l.ProductId, l.ProductName })
            .Select(g => new
            {
                productId = g.Key.ProductId,
                productName = g.Key.ProductName,
                qty = g.Sum(x => x.Qty),
                revenue = g.Sum(x => x.LineTotal),
            })
            .OrderByDescending(x => x.revenue)
            .Take(20)
            .ToListAsync();

        return Ok(AppResponse<object>.Success(new
        {
            from = fromDt,
            to = toDt.AddDays(-1),
            totalRevenue,
            totalPaid,
            totalDiscount,
            orderCount,
            byPayment,
            byDay,
            topProducts,
        }));
    }

    [HttpGet("sales/orders")]
    [RequireModulePermission("PosSalesReport", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetSalesOrders(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        page = Math.Max(page, 1);
        pageSize = Math.Clamp(pageSize, 1, 200);
        var fromDt = from?.Date;
        var toDt = to?.Date.AddDays(1);

        var query = dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive);
        if (fromDt.HasValue) query = query.Where(o => o.CreatedAt >= fromDt);
        if (toDt.HasValue) query = query.Where(o => o.CreatedAt < toDt);

        var total = await query.CountAsync();
        var items = await query
            .OrderByDescending(o => o.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(o => new
            {
                o.Id,
                o.OrderNo,
                Status = o.Status.ToString(),
                o.SubTotal,
                o.Discount,
                o.Total,
                o.PaidAmount,
                o.PaymentMethod,
                o.CustomerName,
                o.CreatedAt,
                o.CreatedBy,
                LineCount = o.Lines.Count,
            })
            .ToListAsync();

        return Ok(AppResponse<object>.Success(new { total, page, pageSize, items }));
    }

    [HttpGet("sales/export/excel")]
    [RequireModulePermission("PosSalesReport", ModulePermissionAction.Export)]
    public async Task<IActionResult> ExportSalesExcel(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to)
    {
        var storeId = RequiredStoreId;
        var fromDt = from?.Date ?? DateTime.UtcNow.Date.AddDays(-30);
        var toDt = (to?.Date ?? DateTime.UtcNow.Date).AddDays(1);

        var orders = await dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive &&
                        o.CreatedAt >= fromDt && o.CreatedAt < toDt)
            .OrderByDescending(o => o.CreatedAt)
            .ToListAsync();

        using var workbook = new XLWorkbook();
        var ws = workbook.Worksheets.Add("Doanh thu POS");
        var headers = new[]
        {
            "STT", "Mã đơn", "Ngày", "Khách hàng", "Tạm tính", "Giảm giá",
            "Tổng", "Đã thu", "Thanh toán", "Trạng thái", "Người tạo"
        };

        var meta = ReportExcelMeta.FromUser(
            User, "BÁO CÁO DOANH THU POS",
            $"{fromDt:dd/MM/yyyy} - {toDt.AddDays(-1):dd/MM/yyyy}",
            null,
            new[] { $"Tổng đơn: {orders.Count}" }, orders.Count);
        var (headerRow, dataStartRow) = ReportExcelLayout.ApplyMeta(ws, meta, headers.Length);
        ReportExcelLayout.ApplyHeaderRow(ws, headerRow, headers);

        var row = dataStartRow;
        var idx = 1;
        foreach (var o in orders)
        {
            ws.Cell(row, 1).Value = idx++;
            ws.Cell(row, 2).Value = o.OrderNo;
            ws.Cell(row, 3).Value = o.CreatedAt.ToString("dd/MM/yyyy HH:mm");
            ws.Cell(row, 4).Value = o.CustomerName ?? "";
            ws.Cell(row, 5).Value = o.SubTotal;
            ws.Cell(row, 6).Value = o.Discount;
            ws.Cell(row, 7).Value = o.Total;
            ws.Cell(row, 8).Value = o.PaidAmount;
            ws.Cell(row, 9).Value = o.PaymentMethod;
            ws.Cell(row, 10).Value = o.Status.ToString();
            ws.Cell(row, 11).Value = o.CreatedBy ?? "";
            row++;
        }

        ws.Columns(1, headers.Length).AdjustToContents();
        using var stream = new MemoryStream();
        workbook.SaveAs(stream);
        return File(stream.ToArray(),
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            $"BaoCaoDoanhThuPOS_{DateTime.Now:yyyyMMdd_HHmm}.xlsx");
    }

    [HttpGet("stock/summary")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetStockSummary()
    {
        var storeId = RequiredStoreId;
        var products = await dbContext.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.IsActive &&
                        p.ProductType != PosProductType.Service)
            .Select(p => new { p.Id, p.OnHandQty, p.CostPrice, p.MinStockQty })
            .ToListAsync();

        var variantAttrs = await dbContext.PosProductVariants.AsNoTracking()
            .Where(v => v.StoreId == storeId && v.Deleted == null && v.IsActive)
            .Select(v => new { v.ProductId, v.AttributeJson, v.OnHandQty, v.CostPrice })
            .ToListAsync();

        var distinctVariantProductIds = variantAttrs
            .Where(v => !PosVariantStockHelper.IsUnitOnlyVariant(v.AttributeJson))
            .Select(v => v.ProductId)
            .Distinct()
            .ToHashSet();

        var parentValue = products
            .Where(p => !distinctVariantProductIds.Contains(p.Id))
            .Sum(p => p.OnHandQty * p.CostPrice);
        var variantValue = variantAttrs
            .Where(v => distinctVariantProductIds.Contains(v.ProductId))
            .Sum(v => v.OnHandQty * v.CostPrice);
        var inventoryValue = parentValue + variantValue;

        var totalSkus = products.Count;
        var totalQty = products.Sum(p => p.OnHandQty);
        var outOfStock = products.Count(p => p.OnHandQty <= 0);
        var belowMin = products.Count(p => p.MinStockQty > 0 && p.OnHandQty < p.MinStockQty && p.OnHandQty > 0);

        return Ok(AppResponse<object>.Success(new
        {
            totalSkus,
            totalQty,
            inventoryValue,
            outOfStock,
            belowMin,
        }));
    }

    [HttpGet("stock/products")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetStockProducts(
        [FromQuery] string? search,
        [FromQuery] string? filter,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        page = Math.Max(page, 1);
        pageSize = Math.Clamp(pageSize, 1, 200);

        var query = dbContext.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.IsActive &&
                        p.ProductType != PosProductType.Service);

        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            query = query.Where(p =>
                p.Name.ToLower().Contains(s) ||
                p.ProductCode.ToLower().Contains(s) ||
                (p.Barcode != null && p.Barcode.ToLower().Contains(s)));
        }

        if (Enum.TryParse<PosStockFilter>(filter, true, out var sf))
        {
            query = sf switch
            {
                PosStockFilter.BelowMin => query.Where(p => p.MinStockQty > 0 && p.OnHandQty < p.MinStockQty),
                PosStockFilter.OutOfStock => query.Where(p => p.OnHandQty <= 0),
                PosStockFilter.AboveMax => query.Where(p => p.MaxStockQty > 0 && p.OnHandQty > p.MaxStockQty),
                _ => query,
            };
        }

        var total = await query.CountAsync();
        var items = await query
            .OrderBy(p => p.OnHandQty <= 0 ? 0 : 1)
            .ThenBy(p => p.Name)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(p => new
            {
                p.Id,
                p.ProductCode,
                p.Barcode,
                p.Name,
                p.BaseUnitName,
                p.OnHandQty,
                p.MinStockQty,
                p.MaxStockQty,
                p.CostPrice,
                stockValue = p.OnHandQty * p.CostPrice,
                ProductType = p.ProductType.ToString(),
            })
            .ToListAsync();

        return Ok(AppResponse<object>.Success(new { total, page, pageSize, items }));
    }

    [HttpGet("stock/export/excel")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Export)]
    public async Task<IActionResult> ExportStockExcel([FromQuery] string? search)
    {
        var storeId = RequiredStoreId;
        var query = dbContext.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.IsActive &&
                        p.ProductType != PosProductType.Service);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            query = query.Where(p =>
                p.Name.ToLower().Contains(s) ||
                p.ProductCode.ToLower().Contains(s));
        }

        var products = await query.OrderBy(p => p.Name).Take(5000).ToListAsync();

        using var workbook = new XLWorkbook();
        var ws = workbook.Worksheets.Add("Ton kho POS");
        var headers = new[]
        {
            "STT", "Mã hàng", "Mã vạch", "Tên hàng", "ĐVT", "Tồn kho",
            "Tồn tối thiểu", "Giá vốn", "Giá trị tồn"
        };
        var meta = ReportExcelMeta.FromUser(
            User, "BÁO CÁO TỒN KHO POS", null, null,
            new[] { $"Tổng mặt hàng: {products.Count}" }, products.Count);
        var (headerRow, dataStartRow) = ReportExcelLayout.ApplyMeta(ws, meta, headers.Length);
        ReportExcelLayout.ApplyHeaderRow(ws, headerRow, headers);

        var row = dataStartRow;
        var idx = 1;
        foreach (var p in products)
        {
            ws.Cell(row, 1).Value = idx++;
            ws.Cell(row, 2).Value = p.ProductCode;
            ws.Cell(row, 3).Value = p.Barcode ?? "";
            ws.Cell(row, 4).Value = p.Name;
            ws.Cell(row, 5).Value = p.BaseUnitName ?? "";
            ws.Cell(row, 6).Value = p.OnHandQty;
            ws.Cell(row, 7).Value = p.MinStockQty;
            ws.Cell(row, 8).Value = p.CostPrice;
            ws.Cell(row, 9).Value = p.OnHandQty * p.CostPrice;
            row++;
        }

        ws.Columns(1, headers.Length).AdjustToContents();
        using var stream = new MemoryStream();
        workbook.SaveAs(stream);
        return File(stream.ToArray(),
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            $"BaoCaoTonKhoPOS_{DateTime.Now:yyyyMMdd_HHmm}.xlsx");
    }

    /// <summary>Tổng kết cuối ngày theo nhân viên (người bán / người tạo).</summary>
    [HttpGet("end-of-day")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetEndOfDay(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] string? staffEmail,
        [FromQuery] Guid? soldByEmployeeId,
        [FromQuery] string filterBy = "soldBy",
        [FromQuery] bool includeProductDetail = true,
        [FromQuery] bool includeTransactions = false)
    {
        var storeId = RequiredStoreId;
        var fromDt = from?.Date ?? DateTime.UtcNow.Date;
        var toDt = (to?.Date ?? DateTime.UtcNow.Date).AddDays(1);
        var filter = filterBy.Equals("createdBy", StringComparison.OrdinalIgnoreCase)
            ? "createdBy"
            : filterBy.Equals("soldByEmployee", StringComparison.OrdinalIgnoreCase)
                ? "soldByEmployee"
                : "soldBy";

        string? effectiveStaff = staffEmail?.Trim();
        Guid? effectiveEmployeeId = soldByEmployeeId;
        if (!IsManager)
        {
            effectiveStaff = CurrentUserEmail;
            effectiveEmployeeId = EmployeeId;
            if (string.IsNullOrWhiteSpace(effectiveStaff) && !effectiveEmployeeId.HasValue)
                return BadRequest(AppResponse<object>.Fail("Không xác định được tài khoản nhân viên"));
        }

        var baseQuery = dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive &&
                        o.CreatedAt >= fromDt && o.CreatedAt < toDt);
        baseQuery = ApplyStaffFilter(baseQuery, effectiveStaff, effectiveEmployeeId, filter);

        var completedQuery = baseQuery.Where(o => o.Status == PosSaleOrderStatus.Completed);
        var canceledQuery = baseQuery.Where(o => o.Status == PosSaleOrderStatus.Cancelled);

        var orderCount = await completedQuery.CountAsync();
        var subTotal = await completedQuery.SumAsync(o => (decimal?)o.SubTotal) ?? 0;
        var orderDiscount = await completedQuery.SumAsync(o => (decimal?)o.Discount) ?? 0;
        var netSales = await completedQuery.SumAsync(o => (decimal?)o.Total) ?? 0;
        var actualReceived = await completedQuery.SumAsync(o => (decimal?)o.PaidAmount) ?? 0;
        var debtTotal = await completedQuery.SumAsync(o => (decimal?)(o.Total - o.PaidAmount)) ?? 0;
        if (debtTotal < 0) debtTotal = 0;

        var canceledCount = await canceledQuery.CountAsync();
        var canceledTotal = await canceledQuery.SumAsync(o => (decimal?)o.Total) ?? 0;

        var orderIds = await completedQuery.Select(o => o.Id).ToListAsync();
        var refundTotal = orderIds.Count == 0
            ? 0m
            : await dbContext.PosStockTransactions.AsNoTracking()
                .Where(t => t.StoreId == storeId && t.Deleted == null &&
                            t.SaleOrderId != null && orderIds.Contains(t.SaleOrderId.Value) &&
                            t.TransactionType == PosStockTransactionType.Return &&
                            (t.Note == null || !t.Note.StartsWith("Hủy đơn")))
                .SumAsync(t => (decimal?)(t.LineAmount ?? 0)) ?? 0;

        var lineDiscountTotal = orderIds.Count == 0
            ? 0m
            : await dbContext.PosSaleOrderLines.AsNoTracking()
                .Where(l => l.StoreId == storeId && l.Deleted == null &&
                            orderIds.Contains(l.SaleOrderId))
                .SumAsync(l => (decimal?)l.DiscountAmount) ?? 0;

        var payments = await completedQuery
            .GroupBy(o => o.PaymentMethod)
            .Select(g => new
            {
                paymentMethod = g.Key ?? "Khác",
                total = g.Sum(x => x.PaidAmount),
                count = g.Count(),
            })
            .OrderByDescending(x => x.total)
            .ToListAsync();

        var cashTotal = payments
            .Where(p => p.paymentMethod.Contains("mặt", StringComparison.OrdinalIgnoreCase) ||
                        p.paymentMethod.Equals("Cash", StringComparison.OrdinalIgnoreCase))
            .Sum(p => p.total);

        object? products = null;
        if (includeProductDetail && orderIds.Count > 0)
        {
            products = await dbContext.PosSaleOrderLines.AsNoTracking()
                .Where(l => l.StoreId == storeId && l.Deleted == null &&
                            orderIds.Contains(l.SaleOrderId))
                .GroupBy(l => new { l.ProductId, l.ProductName })
                .Select(g => new
                {
                    productId = g.Key.ProductId,
                    productName = g.Key.ProductName,
                    qty = g.Sum(x => x.Qty),
                    revenue = g.Sum(x => x.LineTotal),
                    lineDiscount = g.Sum(x => x.DiscountAmount),
                })
                .OrderByDescending(x => x.revenue)
                .ToListAsync();
        }

        object? transactions = null;
        if (includeTransactions)
        {
            var txRows = await completedQuery
                .OrderBy(o => o.CreatedAt)
                .Select(o => new
                {
                    o.Id,
                    o.OrderNo,
                    o.CreatedAt,
                    qty = o.Lines.Sum(l => l.Qty),
                    revenue = o.SubTotal,
                    discount = o.Discount,
                    vat = 0m,
                    rounding = 0m,
                    returnFee = 0m,
                    actualReceived = o.PaidAmount,
                    o.PaymentMethod,
                    o.SoldBy,
                    o.CreatedBy,
                })
                .ToListAsync();

            var returnedMap = orderIds.Count == 0
                ? new Dictionary<Guid, decimal>()
                : await dbContext.PosStockTransactions.AsNoTracking()
                    .Where(t => t.StoreId == storeId && t.Deleted == null &&
                                t.SaleOrderId != null && orderIds.Contains(t.SaleOrderId.Value) &&
                                t.TransactionType == PosStockTransactionType.Return &&
                                (t.Note == null || !t.Note.StartsWith("Hủy đơn")))
                    .GroupBy(t => t.SaleOrderId!.Value)
                    .Select(g => new { OrderId = g.Key, Amount = g.Sum(x => x.LineAmount ?? 0) })
                    .ToDictionaryAsync(x => x.OrderId, x => x.Amount);

            transactions = txRows.Select(t => new
            {
                t.OrderNo,
                t.CreatedAt,
                t.qty,
                t.revenue,
                otherIncome = 0m,
                t.vat,
                t.rounding,
                returnFee = returnedMap.GetValueOrDefault(t.Id),
                t.actualReceived,
                t.PaymentMethod,
                t.SoldBy,
                t.CreatedBy,
            }).ToList();
        }

        var storeName = await dbContext.Stores.AsNoTracking()
            .Where(s => s.Id == storeId)
            .Select(s => s.Name)
            .FirstOrDefaultAsync();

        string? staffName = null;
        if (effectiveEmployeeId.HasValue)
            staffName = await ResolveEmployeeDisplayNameAsync(storeId, effectiveEmployeeId.Value);
        else if (!string.IsNullOrWhiteSpace(effectiveStaff))
            staffName = await ResolveStaffDisplayNameAsync(storeId, effectiveStaff);

        return Ok(AppResponse<object>.Success(new
        {
            from = fromDt,
            to = toDt.AddTicks(-1),
            filterBy = filter,
            staffEmail = effectiveStaff,
            soldByEmployeeId = effectiveEmployeeId,
            staffName,
            storeName,
            generatedAt = DateTime.UtcNow,
            orderCount,
            orderDiscount,
            totalSales = subTotal,
            vat = 0m,
            netSales,
            refundTotal,
            totalAfterRefund = Math.Max(0, netSales - refundTotal),
            canceledCount,
            canceledTotal,
            cashTotal,
            debtTotal,
            actualReceived,
            lineDiscountTotal,
            payments,
            products,
            transactions,
        }));
    }

    /// <summary>Danh sách nhân viên có phát sinh bán hàng (admin/manager).</summary>
    [HttpGet("end-of-day/staff")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetEndOfDayStaff(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] string filterBy = "soldBy")
    {
        var storeId = RequiredStoreId;
        var fromDt = from?.Date ?? DateTime.UtcNow.Date;
        var toDt = (to?.Date ?? DateTime.UtcNow.Date).AddDays(1);
        var filter = filterBy.Equals("createdBy", StringComparison.OrdinalIgnoreCase)
            ? "createdBy"
            : filterBy.Equals("soldByEmployee", StringComparison.OrdinalIgnoreCase)
                ? "soldByEmployee"
                : "soldBy";

        if (!IsManager)
        {
            var email = CurrentUserEmail ?? "";
            var selfId = EmployeeId;
            var selfName = selfId.HasValue
                ? await ResolveEmployeeDisplayNameAsync(storeId, selfId.Value)
                : (string.IsNullOrWhiteSpace(email)
                    ? null
                    : await ResolveStaffDisplayNameAsync(storeId, email));
            return Ok(AppResponse<object>.Success(new[]
            {
                new
                {
                    email,
                    employeeId = selfId,
                    displayName = selfName ?? email,
                    isSelf = true,
                },
            }));
        }

        var orderQuery = dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive &&
                        o.Status == PosSaleOrderStatus.Completed &&
                        o.CreatedAt >= fromDt && o.CreatedAt < toDt);

        if (filter == "soldByEmployee")
        {
            var employeeIds = await orderQuery.Where(o => o.SoldByEmployeeId != null)
                .Select(o => o.SoldByEmployeeId!.Value)
                .Distinct()
                .ToListAsync();
            var employees = await dbContext.Employees.AsNoTracking()
                .Where(e => employeeIds.Contains(e.Id) && e.StoreId == storeId && e.Deleted == null)
                .Select(e => new
                {
                    e.Id,
                    Name = (e.LastName + " " + e.FirstName).Trim(),
                    e.CompanyEmail,
                })
                .OrderBy(e => e.Name)
                .ToListAsync();
            var employeeItems = employees.Select(e => new
            {
                email = e.CompanyEmail,
                employeeId = (Guid?)e.Id,
                displayName = string.IsNullOrWhiteSpace(e.Name) ? e.CompanyEmail ?? e.Id.ToString() : e.Name,
                isSelf = EmployeeId.HasValue && e.Id == EmployeeId.Value,
            }).ToList();
            return Ok(AppResponse<object>.Success(employeeItems));
        }

        var emails = filter == "createdBy"
            ? await orderQuery.Where(o => o.CreatedBy != null)
                .Select(o => o.CreatedBy!)
                .Distinct()
                .OrderBy(e => e)
                .ToListAsync()
            : await orderQuery.Where(o => o.SoldBy != null)
                .Select(o => o.SoldBy!)
                .Distinct()
                .OrderBy(e => e)
                .ToListAsync();

        var nameMap = await ResolveStaffDisplayNamesAsync(storeId, emails);
        var items = emails.Select(e => new
        {
            email = e,
            employeeId = (Guid?)null,
            displayName = nameMap.GetValueOrDefault(e) ?? e,
            isSelf = e.Equals(CurrentUserEmail, StringComparison.OrdinalIgnoreCase),
        }).ToList();

        return Ok(AppResponse<object>.Success(items));
    }

    private static IQueryable<PosSaleOrder> ApplyStaffFilter(
        IQueryable<PosSaleOrder> query,
        string? staffEmail,
        Guid? soldByEmployeeId,
        string filterBy)
    {
        if (filterBy == "soldByEmployee" && soldByEmployeeId.HasValue)
            return query.Where(o => o.SoldByEmployeeId == soldByEmployeeId);
        if (string.IsNullOrWhiteSpace(staffEmail)) return query;
        return filterBy == "createdBy"
            ? query.Where(o => o.CreatedBy == staffEmail)
            : query.Where(o => o.SoldBy == staffEmail);
    }

    private async Task<string?> ResolveEmployeeDisplayNameAsync(Guid storeId, Guid employeeId)
    {
        var emp = await dbContext.Employees.AsNoTracking()
            .Where(e => e.Id == employeeId && e.StoreId == storeId && e.Deleted == null)
            .Select(e => new { Name = (e.LastName + " " + e.FirstName).Trim(), e.CompanyEmail })
            .FirstOrDefaultAsync();
        if (emp == null) return null;
        return !string.IsNullOrWhiteSpace(emp.Name) ? emp.Name : emp.CompanyEmail;
    }

    private async Task<string?> ResolveStaffDisplayNameAsync(Guid storeId, string email)
    {
        var map = await ResolveStaffDisplayNamesAsync(storeId, [email]);
        return map.GetValueOrDefault(email);
    }

    private async Task<Dictionary<string, string>> ResolveStaffDisplayNamesAsync(
        Guid storeId, IEnumerable<string> emails)
    {
        var list = emails.Where(e => !string.IsNullOrWhiteSpace(e)).Distinct().ToList();
        if (list.Count == 0) return new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        var employees = await dbContext.Employees.AsNoTracking()
            .Where(e => e.StoreId == storeId && e.Deleted == null &&
                        list.Contains(e.CompanyEmail))
            .Select(e => new { e.CompanyEmail, Name = (e.LastName + " " + e.FirstName).Trim() })
            .ToListAsync();

        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var e in employees)
        {
            if (!string.IsNullOrWhiteSpace(e.CompanyEmail) && !string.IsNullOrWhiteSpace(e.Name))
                result[e.CompanyEmail] = e.Name;
        }
        return result;
    }
}
