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
        DateTime? SoldAt,
        // Tỷ lệ tiền thực thu (giảm giá đơn / voucher / điểm) — nhân vào doanh thu món + topping.
        decimal RevenueFactor = 1m,
        // 1 ĐVT bán = QtyRate đơn vị cơ bản (Thùng = 24) — SL món cộng theo đơn vị cơ bản.
        decimal QtyRate = 1m);

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
            var f = l.RevenueFactor;
            Add(l.ProductId, l.ProductName, l.Qty * (l.QtyRate > 0 ? l.QtyRate : 1), (l.LineTotal - extra) * f, l.DiscountAmount, l.SoldAt);
            foreach (var p in picks)
            {
                var tQty = p.Qty * l.Qty;
                if (tQty <= 0) continue;
                var name = string.IsNullOrWhiteSpace(p.Name) ? "Topping" : p.Name;
                Add(p.ProductId, name, tQty, p.UnitPrice * tQty * f, 0, l.SoldAt);
            }
        }

        // Phân bổ giảm giá đơn tạo số lẻ — làm tròn 2 chữ số (đồng) khi trả kết quả.
        return map.Values
            .Select(x => x with { Revenue = Math.Round(x.Revenue, 2, MidpointRounding.AwayFromZero) })
            .OrderByDescending(x => x.Revenue).ToList();
    }

    static DateTime? Max(DateTime? a, DateTime? b)
    {
        if (!a.HasValue) return b;
        if (!b.HasValue) return a;
        return a.Value >= b.Value ? a : b;
    }
}
