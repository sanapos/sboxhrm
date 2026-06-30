using ClosedXML.Excel;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Controllers.Reports;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
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
}
