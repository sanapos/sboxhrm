using ClosedXML.Excel;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Controllers.Reports;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

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
        [FromQuery] DateTime? to,
        [FromQuery] int? dayStartHour = null)
    {
        var storeId = RequiredStoreId;
        var hour = await ResolveReportDayStartHourAsync(storeId, dayStartHour);
        var (fromDt, toDt, fromVn, toVnEx) = ResolvePosRange(from, to, hour, defaultLookbackDays: 30);

        // Ngày doanh thu = SaleDate ?? CreatedAt; cửa sổ UTC+7 (+ ngày qua đêm nếu hour>0).
        var orders = dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive &&
                        o.Status == PosSaleOrderStatus.Completed &&
                        (o.SaleDate ?? o.CreatedAt) >= fromDt &&
                        (o.SaleDate ?? o.CreatedAt) < toDt);

        var totalRevenue = await orders.SumAsync(o => o.Total);
        var totalPaid = await orders.SumAsync(o => o.PaidAmount);
        var totalDiscount = await orders.SumAsync(o => o.Discount);
        var orderCount = await orders.CountAsync();

        var byPaymentRaw = await dbContext.CashTransactions.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive
                && c.Status == CashTransactionStatus.Completed
                && c.Type == CashTransactionType.Income
                && c.InternalNote != null
                && c.InternalNote.StartsWith(PosFinanceSyncHelper.SaleMarker)
                && c.TransactionDate >= fromDt && c.TransactionDate < toDt)
            .GroupBy(c => c.PaymentMethod)
            .Select(g => new { Method = g.Key, total = g.Sum(x => x.Amount), count = g.Count() })
            .ToListAsync();

        static string PayLabel(PaymentMethodType method) => method switch
        {
            PaymentMethodType.Cash => "Tiền mặt",
            PaymentMethodType.BankTransfer => "Chuyển khoản",
            PaymentMethodType.VietQR => "VietQR",
            PaymentMethodType.Card => "Thẻ",
            PaymentMethodType.EWallet => "Ví điện tử",
            _ => "Khác",
        };

        object byPayment;
        if (byPaymentRaw.Count > 0)
        {
            byPayment = byPaymentRaw
                .Select(g => new { paymentMethod = PayLabel(g.Method), g.total, g.count })
                .OrderByDescending(x => x.total)
                .ToList();
        }
        else
        {
            byPayment = await orders
                .GroupBy(o => o.PaymentMethod)
                .Select(g => new { paymentMethod = g.Key ?? "Khác", total = g.Sum(x => x.PaidAmount), count = g.Count() })
                .OrderByDescending(x => x.total)
                .ToListAsync();
        }

        var byDay = await orders
            .GroupBy(o => (o.SaleDate ?? o.CreatedAt).Date)
            .Select(g => new { date = g.Key, total = g.Sum(x => x.Total), count = g.Count() })
            .OrderBy(x => x.date)
            .ToListAsync();

        var topProducts = await dbContext.PosSaleOrderLines.AsNoTracking()
            .Where(l => l.StoreId == storeId && l.Deleted == null &&
                        l.SaleOrder != null && l.SaleOrder.Deleted == null &&
                        l.SaleOrder.Status == PosSaleOrderStatus.Completed &&
                        (l.SaleOrder.SaleDate ?? l.SaleOrder.CreatedAt) >= fromDt &&
                        (l.SaleOrder.SaleDate ?? l.SaleOrder.CreatedAt) < toDt)
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

        var orderIds = await orders.Select(o => o.Id).ToListAsync();
        var totalCogs = orderIds.Count == 0
            ? 0m
            : await dbContext.PosStockTransactions.AsNoTracking()
                .Where(t => t.StoreId == storeId && t.Deleted == null &&
                            t.TransactionType == PosStockTransactionType.Sale &&
                            t.SaleOrderId != null && orderIds.Contains(t.SaleOrderId.Value))
                .SumAsync(t => (decimal?)(t.LineAmount ?? 0)) ?? 0;

        var cogsByOrder = orderIds.Count == 0
            ? new Dictionary<Guid, decimal>()
            : await dbContext.PosStockTransactions.AsNoTracking()
                .Where(t => t.StoreId == storeId && t.Deleted == null &&
                            t.TransactionType == PosStockTransactionType.Sale &&
                            t.SaleOrderId != null && orderIds.Contains(t.SaleOrderId.Value))
                .GroupBy(t => t.SaleOrderId!.Value)
                .Select(g => new { OrderId = g.Key, Cogs = g.Sum(x => x.LineAmount ?? 0) })
                .ToDictionaryAsync(x => x.OrderId, x => x.Cogs);

        var orderRows = await orders
            .Select(o => new { o.Id, BizAt = o.SaleDate ?? o.CreatedAt, o.Total })
            .ToListAsync();

        var profitByDay = orderRows
            .GroupBy(o => o.BizAt.Date)
            .Select(g =>
            {
                var revenue = g.Sum(x => x.Total);
                var cogs = g.Sum(x => cogsByOrder.GetValueOrDefault(x.Id));
                return new
                {
                    date = g.Key,
                    revenue,
                    cogs,
                    profit = revenue - cogs,
                    count = g.Count(),
                };
            })
            .OrderBy(x => x.date)
            .ToList();

        var topEmployees = await orders
            .GroupBy(o => new { o.SoldBy, o.SoldByEmployeeId })
            .Select(g => new
            {
                soldBy = g.Key.SoldBy,
                employeeId = g.Key.SoldByEmployeeId,
                revenue = g.Sum(x => x.Total),
                orderCount = g.Count(),
            })
            .OrderByDescending(x => x.revenue)
            .Take(10)
            .ToListAsync();

        var storeName = await dbContext.Stores.AsNoTracking()
            .Where(s => s.Id == storeId)
            .Select(s => s.Name)
            .FirstOrDefaultAsync();

        return Ok(AppResponse<object>.Success(new
        {
            from = fromVn.Date,
            to = toVnEx.AddDays(-1).Date,
            dayStartHour = hour,
            overnight = hour > 0,
            storeName,
            totalRevenue,
            totalPaid,
            totalDiscount,
            totalCogs,
            totalProfit = totalRevenue - totalCogs,
            orderCount,
            byPayment,
            byDay,
            profitByDay,
            topProducts,
            topEmployees,
        }));
    }

    [HttpGet("sales/orders")]
    [RequireModulePermission("PosSalesReport", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetSalesOrders(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        [FromQuery] int? dayStartHour = null)
    {
        var storeId = RequiredStoreId;
        page = Math.Max(page, 1);
        pageSize = Math.Clamp(pageSize, 1, 200);
        var hour = await ResolveReportDayStartHourAsync(storeId, dayStartHour);
        DateTime? fromDt = null;
        DateTime? toDt = null;
        if (from.HasValue || to.HasValue)
        {
            var range = ResolvePosRange(from, to, hour);
            fromDt = range.fromUtc;
            toDt = range.toUtcExclusive;
        }

        var query = dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive);
        if (fromDt.HasValue) query = query.Where(o => (o.SaleDate ?? o.CreatedAt) >= fromDt);
        if (toDt.HasValue) query = query.Where(o => (o.SaleDate ?? o.CreatedAt) < toDt);

        var total = await query.CountAsync();
        var items = await query
            .OrderByDescending(o => o.SaleDate ?? o.CreatedAt)
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
        [FromQuery] DateTime? to,
        [FromQuery] int? dayStartHour = null)
    {
        var storeId = RequiredStoreId;
        var hour = await ResolveReportDayStartHourAsync(storeId, dayStartHour);
        var (fromDt, toDt, fromVn, toVnEx) = ResolvePosRange(from, to, hour, defaultLookbackDays: 30);

        var orders = await dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive &&
                        (o.SaleDate ?? o.CreatedAt) >= fromDt &&
                        (o.SaleDate ?? o.CreatedAt) < toDt)
            .OrderByDescending(o => o.SaleDate ?? o.CreatedAt)
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
            $"{fromVn:dd/MM/yyyy} - {toVnEx.AddDays(-1):dd/MM/yyyy}" +
            (hour > 0 ? $" (qua đêm từ {hour:00}:00)" : " (UTC+7)"),
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
            ws.Cell(row, 3).Value = (o.SaleDate ?? o.CreatedAt).ToString("dd/MM/yyyy HH:mm");
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

    /// <summary>Báo cáo hàng hóa: top doanh thu + top giá trị tồn.</summary>
    [HttpGet("goods/summary")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetGoodsSummary(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] int limit = 20,
        [FromQuery] int? dayStartHour = null)
    {
        var storeId = RequiredStoreId;
        limit = Math.Clamp(limit, 1, 50);
        var hour = await ResolveReportDayStartHourAsync(storeId, dayStartHour);
        var (fromDt, toDt, _, _) = ResolvePosRange(from, to, hour, defaultLookbackDays: 30);

        var topByRevenue = await dbContext.PosSaleOrderLines.AsNoTracking()
            .Where(l => l.StoreId == storeId && l.Deleted == null &&
                        l.SaleOrder != null && l.SaleOrder.Deleted == null &&
                        l.SaleOrder.Status == PosSaleOrderStatus.Completed &&
                        (l.SaleOrder.SaleDate ?? l.SaleOrder.CreatedAt) >= fromDt &&
                        (l.SaleOrder.SaleDate ?? l.SaleOrder.CreatedAt) < toDt)
            .GroupBy(l => new { l.ProductId, l.ProductName })
            .Select(g => new
            {
                productId = g.Key.ProductId,
                productName = g.Key.ProductName,
                qty = g.Sum(x => x.Qty),
                revenue = g.Sum(x => x.LineTotal),
            })
            .OrderByDescending(x => x.revenue)
            .Take(limit)
            .ToListAsync();

        var topByStockValue = await dbContext.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.IsActive &&
                        p.ProductType != PosProductType.Service)
            .OrderByDescending(p => p.OnHandQty * p.CostPrice)
            .Take(limit)
            .Select(p => new
            {
                p.Id,
                p.ProductCode,
                p.Name,
                p.OnHandQty,
                p.MinStockQty,
                p.CostPrice,
                stockValue = p.OnHandQty * p.CostPrice,
                p.BaseUnitName,
            })
            .ToListAsync();

        var stockSummary = await GetStockSummaryCoreAsync(storeId);

        return Ok(AppResponse<object>.Success(new
        {
            from = fromDt,
            to = toDt.AddDays(-1),
            inventoryValue = stockSummary.inventoryValue,
            productCount = stockSummary.totalSkus,
            totalOnHandQty = stockSummary.totalQty,
            outOfStockCount = stockSummary.outOfStock,
            belowMinCount = stockSummary.belowMin,
            topByRevenue,
            topByStockValue,
        }));
    }

    /// <summary>Phân tích tình hình kinh doanh — so sánh kỳ trước.</summary>
    [HttpGet("analysis/overview")]
    [RequireModulePermission("PosSalesReport", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetBusinessAnalysis(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] int? dayStartHour = null)
    {
        var storeId = RequiredStoreId;
        var hour = await ResolveReportDayStartHourAsync(storeId, dayStartHour);
        var (fromDt, toDt, fromVn, toVnEx) = ResolvePosRange(from, to, hour, defaultLookbackDays: 30);
        var spanDays = Math.Max(1, (toVnEx.Date - fromVn.Date).Days);
        var prevRange = ResolvePosRange(
            fromVn.Date.AddDays(-spanDays), fromVn.Date.AddDays(-1), hour);
        var prevFrom = prevRange.fromUtc;
        var prevTo = prevRange.toUtcExclusive;

        async Task<(decimal revenue, decimal cogs, int orders, decimal discount)> PeriodAsync(
            DateTime start, DateTime end)
        {
            var q = dbContext.PosSaleOrders.AsNoTracking()
                .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive &&
                            o.Status == PosSaleOrderStatus.Completed &&
                            (o.SaleDate ?? o.CreatedAt) >= start &&
                            (o.SaleDate ?? o.CreatedAt) < end);
            var revenue = await q.SumAsync(o => (decimal?)o.Total) ?? 0;
            var discount = await q.SumAsync(o => (decimal?)o.Discount) ?? 0;
            var count = await q.CountAsync();
            var ids = await q.Select(o => o.Id).ToListAsync();
            var cogs = ids.Count == 0
                ? 0m
                : await dbContext.PosStockTransactions.AsNoTracking()
                    .Where(t => t.StoreId == storeId && t.Deleted == null &&
                                t.TransactionType == PosStockTransactionType.Sale &&
                                t.SaleOrderId != null && ids.Contains(t.SaleOrderId.Value))
                    .SumAsync(t => (decimal?)(t.LineAmount ?? 0)) ?? 0;
            return (revenue, cogs, count, discount);
        }

        var current = await PeriodAsync(fromDt, toDt);
        var previous = await PeriodAsync(prevFrom, prevTo);

        var byChannel = await dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive &&
                        o.Status == PosSaleOrderStatus.Completed &&
                        (o.SaleDate ?? o.CreatedAt) >= fromDt &&
                        (o.SaleDate ?? o.CreatedAt) < toDt)
            .GroupBy(o => o.SalesChannel ?? "Khác")
            .Select(g => new { channel = g.Key, revenue = g.Sum(x => x.Total), count = g.Count() })
            .OrderByDescending(x => x.revenue)
            .ToListAsync();

        var byCategory = await dbContext.PosSaleOrderLines.AsNoTracking()
            .Where(l => l.StoreId == storeId && l.Deleted == null &&
                        l.SaleOrder != null && l.SaleOrder.Deleted == null &&
                        l.SaleOrder.Status == PosSaleOrderStatus.Completed &&
                        (l.SaleOrder.SaleDate ?? l.SaleOrder.CreatedAt) >= fromDt &&
                        (l.SaleOrder.SaleDate ?? l.SaleOrder.CreatedAt) < toDt)
            .Join(dbContext.PosProducts.AsNoTracking(),
                l => l.ProductId, p => p.Id,
                (l, p) => new { l.LineTotal, p.CategoryId })
            .GroupBy(x => x.CategoryId)
            .Select(g => new
            {
                categoryId = g.Key,
                revenue = g.Sum(x => x.LineTotal),
            })
            .OrderByDescending(x => x.revenue)
            .Take(10)
            .ToListAsync();

        var categoryIds = byCategory.Where(c => c.categoryId.HasValue).Select(c => c.categoryId!.Value).ToList();
        var categoryNames = await dbContext.PosProductCategories.AsNoTracking()
            .Where(c => categoryIds.Contains(c.Id))
            .ToDictionaryAsync(c => c.Id, c => c.Name);

        var topCategories = byCategory.Select(c => new
        {
            categoryId = c.categoryId,
            categoryName = c.categoryId.HasValue
                ? categoryNames.GetValueOrDefault(c.categoryId.Value, "Khác")
                : "Khác",
            revenue = c.revenue,
        }).ToList();

        decimal PctChange(decimal cur, decimal prev) =>
            prev == 0 ? (cur > 0 ? 100 : 0) : Math.Round((cur - prev) / prev * 100, 1);

        var storeName = await dbContext.Stores.AsNoTracking()
            .Where(s => s.Id == storeId)
            .Select(s => s.Name)
            .FirstOrDefaultAsync();

        return Ok(AppResponse<object>.Success(new
        {
            from = fromVn.Date,
            to = toVnEx.AddDays(-1).Date,
            dayStartHour = hour,
            overnight = hour > 0,
            storeName,
            current = new
            {
                revenue = current.revenue,
                cogs = current.cogs,
                profit = current.revenue - current.cogs,
                marginPct = current.revenue > 0
                    ? Math.Round((current.revenue - current.cogs) / current.revenue * 100, 1)
                    : 0m,
                orderCount = current.orders,
                avgOrderValue = current.orders > 0
                    ? Math.Round(current.revenue / current.orders, 0)
                    : 0m,
                discount = current.discount,
            },
            previous = new
            {
                revenue = previous.revenue,
                cogs = previous.cogs,
                profit = previous.revenue - previous.cogs,
                orderCount = previous.orders,
                avgOrderValue = previous.orders > 0
                    ? Math.Round(previous.revenue / previous.orders, 0)
                    : 0m,
            },
            changePct = new
            {
                revenue = PctChange(current.revenue, previous.revenue),
                profit = PctChange(current.revenue - current.cogs, previous.revenue - previous.cogs),
                orders = PctChange(current.orders, previous.orders),
            },
            byChannel,
            topCategories,
        }));
    }

    private static async Task<(int totalSkus, decimal totalQty, decimal inventoryValue, int outOfStock, int belowMin)>
        GetStockSummaryCoreAsync(ZKTecoDbContext db, Guid storeId)
    {
        var products = await db.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.IsActive &&
                        p.ProductType != PosProductType.Service)
            .Select(p => new { p.Id, p.OnHandQty, p.CostPrice, p.MinStockQty })
            .ToListAsync();

        var variantAttrs = await db.PosProductVariants.AsNoTracking()
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

        return (
            products.Count,
            products.Sum(p => p.OnHandQty),
            parentValue + variantValue,
            products.Count(p => p.OnHandQty <= 0),
            products.Count(p => p.MinStockQty > 0 && p.OnHandQty < p.MinStockQty && p.OnHandQty > 0));
    }

    private Task<(int totalSkus, decimal totalQty, decimal inventoryValue, int outOfStock, int belowMin)>
        GetStockSummaryCoreAsync(Guid storeId) =>
        GetStockSummaryCoreAsync(dbContext, storeId);

    [HttpGet("stock/summary")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetStockSummary()
    {
        var storeId = RequiredStoreId;
        var core = await GetStockSummaryCoreAsync(storeId);

        return Ok(AppResponse<object>.Success(new
        {
            totalSkus = core.totalSkus,
            totalQty = core.totalQty,
            inventoryValue = core.inventoryValue,
            outOfStock = core.outOfStock,
            belowMin = core.belowMin,
            productCount = core.totalSkus,
            totalStockValue = core.inventoryValue,
            totalOnHandQty = core.totalQty,
            outOfStockCount = core.outOfStock,
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

    [HttpGet("stock/lots/summary")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetStockLotsSummary()
    {
        var storeId = RequiredStoreId;
        var today = DateTime.UtcNow.Date;

        var lots = await dbContext.PosStockLots.AsNoTracking()
            .Include(l => l.Product)
            .Where(l => l.StoreId == storeId && l.Deleted == null && l.IsActive &&
                        l.Status == PosStockLotStatus.Active && l.QtyOnHand > 0)
            .Select(l => new
            {
                l.QtyOnHand,
                l.ExpiryDate,
                l.UnitCost,
                WarningDays = l.Product != null ? l.Product.ExpiryWarningDays : 30,
            })
            .ToListAsync();

        var withExpiry = lots.Where(l => l.ExpiryDate.HasValue).ToList();
        var expired = withExpiry.Where(l => l.ExpiryDate!.Value.Date < today).ToList();
        var expiringSoon = withExpiry.Where(l =>
        {
            var days = (l.ExpiryDate!.Value.Date - today).Days;
            return days >= 0 && days <= l.WarningDays;
        }).ToList();

        return Ok(AppResponse<object>.Success(new
        {
            activeLotCount = lots.Count,
            totalLotQty = lots.Sum(l => l.QtyOnHand),
            lotInventoryValue = lots.Sum(l => l.QtyOnHand * l.UnitCost),
            expiredLotCount = expired.Count,
            expiredQty = expired.Sum(l => l.QtyOnHand),
            expiringSoonLotCount = expiringSoon.Count,
            expiringSoonQty = expiringSoon.Sum(l => l.QtyOnHand),
        }));
    }

    [HttpGet("stock/lots")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetStockLotsReport(
        [FromQuery] string? search,
        [FromQuery] string? filter,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        page = Math.Max(page, 1);
        pageSize = Math.Clamp(pageSize, 1, 200);
        var today = DateTime.UtcNow.Date;

        var query = dbContext.PosStockLots.AsNoTracking()
            .Include(l => l.Product)
            .Where(l => l.StoreId == storeId && l.Deleted == null && l.IsActive &&
                        l.Status == PosStockLotStatus.Active && l.QtyOnHand > 0);

        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            query = query.Where(l =>
                (l.Product != null && l.Product.Name.ToLower().Contains(s)) ||
                (l.Product != null && l.Product.ProductCode.ToLower().Contains(s)) ||
                (l.LotNo != null && l.LotNo.ToLower().Contains(s)));
        }

        if (string.Equals(filter, "expired", StringComparison.OrdinalIgnoreCase))
            query = query.Where(l => l.ExpiryDate != null && l.ExpiryDate < today);
        else if (string.Equals(filter, "expiring", StringComparison.OrdinalIgnoreCase))
            query = query.Where(l => l.ExpiryDate != null && l.ExpiryDate >= today &&
                                     l.ExpiryDate <= today.AddDays(30));

        var total = await query.CountAsync();
        var rows = await query
            .OrderBy(l => l.ExpiryDate ?? DateTime.MaxValue)
            .ThenBy(l => l.Product!.Name)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(l => new
            {
                l.Id,
                l.ProductId,
                l.VariantId,
                ProductCode = l.Product != null ? l.Product.ProductCode : null,
                ProductName = l.Product != null ? l.Product.Name : "",
                l.LotNo,
                l.ManufactureDate,
                l.ExpiryDate,
                l.QtyOnHand,
                l.UnitCost,
                stockValue = l.QtyOnHand * l.UnitCost,
                WarningDays = l.Product != null ? l.Product.ExpiryWarningDays : 30,
            })
            .ToListAsync();

        var items = rows.Select(r =>
        {
            int? daysUntil = r.ExpiryDate.HasValue
                ? (int?)(r.ExpiryDate.Value.Date - today).TotalDays
                : null;
            var status = !daysUntil.HasValue ? "ok"
                : daysUntil.Value < 0 ? "expired"
                : daysUntil.Value <= r.WarningDays ? "expiring" : "ok";
            return new
            {
                r.Id,
                r.ProductId,
                r.VariantId,
                r.ProductCode,
                r.ProductName,
                r.LotNo,
                r.ManufactureDate,
                r.ExpiryDate,
                r.QtyOnHand,
                r.UnitCost,
                r.stockValue,
                daysUntilExpiry = daysUntil,
                status,
            };
        }).ToList();

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
        [FromQuery] string filterBy = "soldByEmployee",
        [FromQuery] bool includeProductDetail = true,
        [FromQuery] bool includeTransactions = false,
        [FromQuery] int? dayStartHour = null)
    {
        var storeId = RequiredStoreId;
        var hour = await ResolveReportDayStartHourAsync(storeId, dayStartHour);
        var (fromDt, toDt, fromVn, toVnEx) = ResolvePosRange(from, to, hour);
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
            // Ưu tiên hồ sơ NV — SoldBy thường là tên, không phải email đăng nhập.
            if (effectiveEmployeeId.HasValue)
                filter = "soldByEmployee";
            if (string.IsNullOrWhiteSpace(effectiveStaff) && !effectiveEmployeeId.HasValue)
                return BadRequest(AppResponse<object>.Fail("Không xác định được tài khoản nhân viên"));
        }

        var baseQuery = dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive &&
                        (o.SaleDate ?? o.CreatedAt) >= fromDt &&
                        (o.SaleDate ?? o.CreatedAt) < toDt);
        baseQuery = ApplyStaffFilter(baseQuery, effectiveStaff, effectiveEmployeeId, filter);

        var completedQuery = baseQuery.Where(o => o.Status == PosSaleOrderStatus.Completed);
        var canceledQuery = baseQuery.Where(o => o.Status == PosSaleOrderStatus.Cancelled);

        var orderCount = await completedQuery.CountAsync();
        var subTotal = await completedQuery.SumAsync(o => (decimal?)o.SubTotal) ?? 0;
        var orderDiscount = await completedQuery.SumAsync(o => (decimal?)o.Discount) ?? 0;
        var netSales = await completedQuery.SumAsync(o => (decimal?)o.Total) ?? 0;
        var vat = await completedQuery.SumAsync(o => (decimal?)o.VatAmount) ?? 0;
        var actualReceived = await completedQuery.SumAsync(o => (decimal?)o.PaidAmount) ?? 0;
        var debtTotal = await completedQuery.SumAsync(o => (decimal?)(o.Total + o.VatAmount - o.PaidAmount)) ?? 0;
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

        string paymentLabel(PaymentMethodType method) => method switch
        {
            PaymentMethodType.Cash => "Tiền mặt",
            PaymentMethodType.BankTransfer => "Chuyển khoản",
            PaymentMethodType.VietQR => "VietQR",
            PaymentMethodType.Card => "Thẻ",
            PaymentMethodType.EWallet => "Ví điện tử",
            _ => "Khác",
        };

        // Phân tách theo từng dòng thu quỹ (marker sale), không theo chuỗi PaymentMethod gộp.
        var payments = new List<object>();
        var cashTotal = 0m;
        if (orderIds.Count > 0)
        {
            var orderIdSet = orderIds.ToHashSet();
            var saleCashTx = await dbContext.CashTransactions.AsNoTracking()
                .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive
                    && c.Status == CashTransactionStatus.Completed
                    && c.Type == CashTransactionType.Income
                    && c.InternalNote != null
                    && c.InternalNote.StartsWith(PosFinanceSyncHelper.SaleMarker))
                .ToListAsync();

            // Marker: "pos bán hàng #{orderId}|{index}"
            static Guid? ParseSaleOrderIdFromMarker(string? note)
            {
                if (string.IsNullOrEmpty(note)) return null;
                var prefix = PosFinanceSyncHelper.SaleMarker;
                if (!note.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) return null;
                var rest = note[prefix.Length..];
                var pipe = rest.IndexOf('|');
                var idPart = pipe >= 0 ? rest[..pipe] : rest;
                return Guid.TryParse(idPart, out var id) ? id : null;
            }

            var matched = saleCashTx
                .Where(c =>
                {
                    var oid = ParseSaleOrderIdFromMarker(c.InternalNote);
                    return oid.HasValue && orderIdSet.Contains(oid.Value);
                })
                .ToList();

            var paymentRows = matched
                .GroupBy(c => c.PaymentMethod)
                .Select(g => new
                {
                    paymentMethod = paymentLabel(g.Key),
                    total = g.Sum(x => x.Amount),
                    count = g.Count(),
                })
                .OrderByDescending(x => x.total)
                .ToList();
            payments = paymentRows.Cast<object>().ToList();
            cashTotal = paymentRows
                .FirstOrDefault(p => p.paymentMethod.Equals("Tiền mặt", StringComparison.OrdinalIgnoreCase))
                ?.total ?? 0m;
        }

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
                .OrderBy(o => o.SaleDate ?? o.CreatedAt)
                .Select(o => new
                {
                    o.Id,
                    o.OrderNo,
                    CreatedAt = o.SaleDate ?? o.CreatedAt,
                    qty = o.Lines.Sum(l => l.Qty),
                    revenue = o.SubTotal,
                    discount = o.Discount,
                    vat = o.VatAmount,
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
            from = fromVn,
            to = toVnEx.AddTicks(-1),
            dayStartHour = hour,
            overnight = hour > 0,
            filterBy = filter,
            staffEmail = effectiveStaff,
            soldByEmployeeId = effectiveEmployeeId,
            staffName,
            storeName,
            generatedAt = DateTime.UtcNow,
            orderCount,
            orderDiscount,
            totalSales = subTotal,
            vat,
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
        [FromQuery] string filterBy = "soldByEmployee",
        [FromQuery] int? dayStartHour = null)
    {
        var storeId = RequiredStoreId;
        var hour = await ResolveReportDayStartHourAsync(storeId, dayStartHour);
        var (fromDt, toDt, _, _) = ResolvePosRange(from, to, hour);
        var filter = filterBy.Equals("createdBy", StringComparison.OrdinalIgnoreCase)
            ? "createdBy"
            : filterBy.Equals("soldBy", StringComparison.OrdinalIgnoreCase)
                ? "soldBy"
                : "soldByEmployee";

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
                        (o.SaleDate ?? o.CreatedAt) >= fromDt &&
                        (o.SaleDate ?? o.CreatedAt) < toDt);

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

    [HttpGet("customer-debt")]
    [RequireModulePermission("PosSalesReport", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> CustomerDebtReport(
        [FromQuery] string? search,
        [FromQuery] decimal? debtFrom,
        [FromQuery] decimal? debtTo,
        [FromQuery] bool includeZeroDebt = false)
    {
        var storeId = RequiredStoreId;
        var custQ = dbContext.PosCustomers.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive);
        if (!includeZeroDebt) custQ = custQ.Where(c => c.CurrentDebt > 0);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            custQ = custQ.Where(c =>
                c.Name.ToLower().Contains(s) ||
                c.CustomerCode.ToLower().Contains(s) ||
                (c.Phone != null && c.Phone.Contains(s)));
        }
        if (debtFrom.HasValue) custQ = custQ.Where(c => c.CurrentDebt >= debtFrom);
        if (debtTo.HasValue) custQ = custQ.Where(c => c.CurrentDebt <= debtTo);

        var customers = await custQ
            .OrderByDescending(c => c.CurrentDebt)
            .ThenBy(c => c.Name)
            .Select(c => new
            {
                c.Id,
                c.CustomerCode,
                c.Name,
                c.Phone,
                c.TotalPurchase,
                c.CurrentDebt,
                c.PointBalance,
            })
            .ToListAsync();

        var customerIds = customers.Select(c => c.Id).ToList();
        var openOrders = customerIds.Count == 0
            ? []
            : await dbContext.PosSaleOrders.AsNoTracking()
                .Where(o => o.StoreId == storeId && o.Deleted == null &&
                            o.Status == PosSaleOrderStatus.Completed &&
                            o.CustomerId != null && customerIds.Contains(o.CustomerId.Value) &&
                            o.Total > o.PaidAmount)
                .GroupBy(o => o.CustomerId!.Value)
                .Select(g => new
                {
                    CustomerId = g.Key,
                    OpenOrderCount = g.Count(),
                    OpenOrderDebt = g.Sum(x => x.Total - x.PaidAmount),
                })
                .ToListAsync();

        var openMap = openOrders.ToDictionary(x => x.CustomerId);
        var items = customers.Select(c =>
        {
            openMap.TryGetValue(c.Id, out var oo);
            return new
            {
                c.Id,
                c.CustomerCode,
                c.Name,
                c.Phone,
                c.TotalPurchase,
                c.CurrentDebt,
                c.PointBalance,
                openOrderCount = oo?.OpenOrderCount ?? 0,
                openOrderDebt = oo?.OpenOrderDebt ?? 0m,
            };
        }).ToList();

        return Ok(AppResponse<object>.Success(new
        {
            totalCustomers = items.Count,
            sumDebt = items.Sum(x => x.CurrentDebt),
            items,
        }));
    }

    async Task<int> ResolveReportDayStartHourAsync(Guid storeId, int? overrideHour)
    {
        if (overrideHour.HasValue) return Math.Clamp(overrideHour.Value, 0, 23);
        var h = await dbContext.PosStoreSellSettings.AsNoTracking()
            .Where(s => s.StoreId == storeId && s.Deleted == null)
            .Select(s => (int?)s.ReportDayStartHour)
            .FirstOrDefaultAsync();
        return Math.Clamp(h ?? 0, 0, 23);
    }

    static (DateTime fromUtc, DateTime toUtcExclusive, DateTime fromVn, DateTime toVnExclusive)
        ResolvePosRange(DateTime? from, DateTime? to, int dayStartHour, int? defaultLookbackDays = null)
    {
        DateTime? defFrom = null;
        DateTime? defTo = null;
        if (defaultLookbackDays is int days)
        {
            var biz = VnTimeHelper.ResolveBusinessDate(VnTimeHelper.NowVn(), dayStartHour);
            defTo = biz;
            defFrom = biz.AddDays(-Math.Max(0, days));
        }
        return ReportHelpers.PosBusinessRange(from, to, dayStartHour, defFrom, defTo);
    }

    private static IQueryable<PosSaleOrder> ApplyStaffFilter(
        IQueryable<PosSaleOrder> query,
        string? staffEmail,
        Guid? soldByEmployeeId,
        string filterBy)
    {
        // Ưu tiên SoldByEmployeeId khi có — khớp hồ sơ NV, không so tên với email.
        if (soldByEmployeeId.HasValue &&
            !filterBy.Equals("createdBy", StringComparison.OrdinalIgnoreCase))
            return query.Where(o => o.SoldByEmployeeId == soldByEmployeeId);

        if (string.IsNullOrWhiteSpace(staffEmail)) return query;
        if (filterBy.Equals("createdBy", StringComparison.OrdinalIgnoreCase))
            return query.Where(o => o.CreatedBy == staffEmail);

        // soldBy: tên NV hoặc email đăng nhập (CreatedBy)
        return query.Where(o => o.SoldBy == staffEmail || o.CreatedBy == staffEmail);
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
