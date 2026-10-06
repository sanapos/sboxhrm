using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

public partial class PosCustomersController
{
    public sealed record HistoryLineDto(
        Guid ProductId, string ProductName, string? UnitName, decimal Qty, decimal ReturnedQty,
        decimal UnitPrice, decimal DiscountAmount, decimal LineTotal, string? LineNote);

    public sealed record HistoryOrderDto(
        Guid Id, string OrderNo, DateTime Date, decimal Total, decimal PaidAmount, decimal Discount,
        string? PaymentMethod, string? SoldBy, List<HistoryLineDto> Lines);

    public sealed record HistoryProductDto(
        Guid ProductId, string ProductName, string? UnitName, int TimesBought, decimal TotalQty, decimal TotalAmount,
        decimal LastPrice, DateTime LastDate, decimal MinPrice, decimal MaxPrice, decimal? CurrentPrice);

    /// <summary>
    /// Lịch sử mua của một khách (màn bán hàng tra nhanh): đơn đã hoàn thành kèm từng món (SL, đơn giá, giảm, đã trả lại)
    /// + tổng hợp theo mặt hàng (số lần mua, giá gần nhất, thấp / cao nhất) — để tra khách mua gì, giá bao nhiêu.
    /// </summary>
    [HttpGet("{id:guid}/purchase-history")]
    [RequireAnyModulePermission(ModulePermissionAction.View, "PosSell", "PosCustomers", "PosSaleOrders")]
    public async Task<ActionResult<AppResponse<object>>> PurchaseHistory(
        Guid id, [FromQuery] string? search, [FromQuery] int days = 365, [FromQuery] int limit = 60)
    {
        var storeId = RequiredStoreId;
        var customer = await dbContext.PosCustomers.AsNoTracking()
            .Where(c => c.Id == id && c.StoreId == storeId && c.Deleted == null)
            .Select(c => new { c.Id, c.Name, c.Phone, c.CustomerCode, c.TotalPurchase, c.CurrentDebt })
            .FirstOrDefaultAsync();
        if (customer == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy khách hàng"));

        days = Math.Clamp(days, 7, 3650);
        limit = Math.Clamp(limit, 1, 200);
        var since = DateTime.UtcNow.AddDays(-days);
        var orders = await dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.CustomerId == id && o.Deleted == null && o.IsActive
                        && o.Status == PosSaleOrderStatus.Completed && (o.SaleDate ?? o.CreatedAt) >= since)
            .OrderByDescending(o => o.SaleDate ?? o.CreatedAt)
            .Take(limit)
            .Select(o => new
            {
                o.Id, o.OrderNo, Date = o.SaleDate ?? o.CreatedAt, o.Total, o.PaidAmount,
                Discount = o.Discount + o.VoucherDiscount + o.PointsDiscount, o.PaymentMethod, o.SoldBy,
                Lines = o.Lines.Where(l => l.Deleted == null)
                    .Select(l => new { l.Id, l.ProductId, l.ProductName, l.UnitName, l.Qty, l.UnitPrice, l.DiscountAmount, l.LineTotal, l.LineNote })
                    .ToList(),
            })
            .ToListAsync();

        var returned = await PosSaleReturnLedger.ReturnedQtyByLineAsync(dbContext, storeId, orders.Select(o => o.Id).ToList());

        var q = VnSearch.FoldText(search);
        var result = orders
            .Select(o => new HistoryOrderDto(o.Id, o.OrderNo, o.Date, o.Total, o.PaidAmount, o.Discount, o.PaymentMethod, o.SoldBy,
                o.Lines.Select(l => new HistoryLineDto(l.ProductId, l.ProductName, l.UnitName, l.Qty,
                    returned.GetValueOrDefault(l.Id), l.UnitPrice, l.DiscountAmount, l.LineTotal, l.LineNote)).ToList()))
            .Where(o => q.Length == 0 || o.OrderNo.Contains(search!.Trim(), StringComparison.OrdinalIgnoreCase)
                        || o.Lines.Any(l => VnSearch.Fold(l.ProductName).Contains(q)))
            .ToList();

        var productIds = result.SelectMany(o => o.Lines.Select(l => l.ProductId)).Distinct().ToList();
        var current = await dbContext.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null && productIds.Contains(p.Id))
            .Select(p => new { p.Id, p.BasePrice })
            .ToDictionaryAsync(p => p.Id, p => p.BasePrice);

        // Tổng hợp theo mặt hàng: giá «gần nhất» = đơn giá thực (sau giảm dòng) ở lần mua mới nhất.
        var products = result
            .SelectMany(o => o.Lines.Select(l => (o.Date, Line: l)))
            .Where(x => q.Length == 0 || VnSearch.Fold(x.Line.ProductName).Contains(q))
            .GroupBy(x => x.Line.ProductId)
            .Select(g =>
            {
                decimal Net(HistoryLineDto l) => l.Qty > 0 ? Math.Round(l.LineTotal / l.Qty, 0) : l.UnitPrice;
                var last = g.OrderByDescending(x => x.Date).First();
                return new HistoryProductDto(g.Key, last.Line.ProductName, last.Line.UnitName, g.Count(),
                    g.Sum(x => x.Line.Qty - x.Line.ReturnedQty), g.Sum(x => x.Line.LineTotal),
                    Net(last.Line), last.Date, g.Min(x => Net(x.Line)), g.Max(x => Net(x.Line)),
                    current.TryGetValue(g.Key, out var cp) ? cp : null);
            })
            .OrderByDescending(p => p.LastDate)
            .ToList();

        return Ok(AppResponse<object>.Success(new
        {
            customer = new
            {
                customer.Id, customer.Name, customer.Phone, customer.CustomerCode, customer.TotalPurchase, customer.CurrentDebt,
            },
            days,
            orderCount = result.Count,
            totalAmount = result.Sum(o => o.Total),
            orders = result,
            products,
        }));
    }
}
