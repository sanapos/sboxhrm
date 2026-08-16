using ZKTecoADMS.Api.Controllers;

namespace ZKTecoADMS.Api.Controllers.Reports;

/// <summary>
/// Bung ToppingsJson thành SKU riêng: DT món cha = LineTotal − topping;
/// SL topping = SL món × SL topping trên dòng.
/// </summary>
internal static class PosReportLineExpand
{
    public readonly record struct LineIn(
        Guid ProductId,
        string ProductName,
        decimal Qty,
        decimal LineTotal,
        decimal DiscountAmount,
        string? ToppingsJson,
        DateTime? SoldAt);

    public sealed record ProductAgg(
        Guid ProductId,
        string ProductName,
        decimal Qty,
        decimal Revenue,
        decimal LineDiscount,
        DateTime? LastSoldAt);

    public static List<ProductAgg> Aggregate(IEnumerable<LineIn> lines)
    {
        var map = new Dictionary<Guid, ProductAgg>();
        void Add(Guid id, string name, decimal qty, decimal revenue, decimal discount, DateTime? soldAt)
        {
            if (map.TryGetValue(id, out var e))
            {
                map[id] = e with
                {
                    Qty = e.Qty + qty,
                    Revenue = e.Revenue + revenue,
                    LineDiscount = e.LineDiscount + discount,
                    LastSoldAt = Max(e.LastSoldAt, soldAt),
                    ProductName = string.IsNullOrWhiteSpace(e.ProductName) ? name : e.ProductName,
                };
            }
            else
            {
                map[id] = new ProductAgg(id, name, qty, revenue, discount, soldAt);
            }
        }

        foreach (var l in lines)
        {
            var picks = PosSaleStockHelper.ParseToppingPicks(l.ToppingsJson);
            var extra = picks.Sum(p => p.UnitPrice * p.Qty * l.Qty);
            if (extra < 0) extra = 0;
            if (extra > l.LineTotal) extra = l.LineTotal;
            Add(l.ProductId, l.ProductName, l.Qty, l.LineTotal - extra, l.DiscountAmount, l.SoldAt);
            foreach (var p in picks)
            {
                var tQty = p.Qty * l.Qty;
                if (tQty <= 0) continue;
                var name = string.IsNullOrWhiteSpace(p.Name) ? "Topping" : p.Name;
                Add(p.ProductId, name, tQty, p.UnitPrice * tQty, 0, l.SoldAt);
            }
        }

        return map.Values.OrderByDescending(x => x.Revenue).ToList();
    }

    static DateTime? Max(DateTime? a, DateTime? b)
    {
        if (!a.HasValue) return b;
        if (!b.HasValue) return a;
        return a.Value >= b.Value ? a : b;
    }
}
