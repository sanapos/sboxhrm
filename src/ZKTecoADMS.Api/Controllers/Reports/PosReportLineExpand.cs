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
        decimal QtyRate = 1m,
        // Đơn chứa dòng — để làm tròn phần phân bổ giảm giá đơn sao cho tổng theo hàng khớp tổng đơn.
        Guid OrderId = default,
        // Tổng thật của đơn (Total) — đích làm tròn khi chỉ lệch tối đa 1đ (tiền hoàn đã làm tròn khác phần chia).
        decimal? OrderTotal = null);

    public sealed record ProductAgg(
        Guid ProductId,
        string ProductName,
        decimal Qty,
        decimal Revenue,
        decimal LineDiscount,
        DateTime? LastSoldAt,
        // Số hóa đơn có bán món này (đếm đơn khác nhau).
        int OrderCount = 0);

    public static List<ProductAgg> Aggregate(IEnumerable<LineIn> lines)
    {
        var map = new Dictionary<Guid, ProductAgg>();
        var ordersByProduct = new Dictionary<Guid, HashSet<Guid>>();
        void Add(Guid id, string name, decimal qty, decimal revenue, decimal discount, DateTime? soldAt, Guid orderId)
        {
            if (orderId != Guid.Empty)
            {
                if (!ordersByProduct.TryGetValue(id, out var set)) ordersByProduct[id] = set = new HashSet<Guid>();
                set.Add(orderId);
            }
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

        // Phần doanh thu từng món / topping theo đơn (chưa làm tròn).
        var parts = new List<(Guid OrderId, Guid ProductId, string Name, decimal Qty, decimal Revenue, decimal Discount, DateTime? SoldAt)>();
        var orderTotals = new Dictionary<Guid, decimal>();
        foreach (var l in lines)
        {
            var picks = PosSaleStockHelper.ParseToppingPicks(l.ToppingsJson);
            var extra = picks.Sum(p => p.UnitPrice * p.Qty * l.Qty);
            if (extra < 0) extra = 0;
            if (extra > l.LineTotal) extra = l.LineTotal;
            var f = l.RevenueFactor;
            if (l.OrderTotal.HasValue) orderTotals[l.OrderId] = l.OrderTotal.Value;
            parts.Add((l.OrderId, l.ProductId, l.ProductName, l.Qty * (l.QtyRate > 0 ? l.QtyRate : 1),
                (l.LineTotal - extra) * f, l.DiscountAmount, l.SoldAt));
            foreach (var p in picks)
            {
                var tQty = p.Qty * l.Qty;
                if (tQty <= 0) continue;
                var name = string.IsNullOrWhiteSpace(p.Name) ? "Topping" : p.Name;
                parts.Add((l.OrderId, p.ProductId, name, tQty, p.UnitPrice * tQty * f, 0, l.SoldAt));
            }
        }

        // Phân bổ giảm giá đơn tạo số lẻ (VD 14.062,5). Làm tròn tới đồng THEO TỪNG ĐƠN, phần dư dồn vào món lớn
        // nhất → tổng theo hàng = tổng đơn (trước đây lệch 0,5đ so với báo cáo doanh thu).
        foreach (var g in parts.Select((x, i) => (x, i)).GroupBy(t => t.x.OrderId))
        {
            var raw = g.Sum(t => t.x.Revenue);
            var target = orderTotals.TryGetValue(g.Key, out var total) && Math.Abs(total - raw) <= 1m
                ? total
                : Math.Round(raw, 0, MidpointRounding.AwayFromZero);
            var rounded = g.Select(t => (t.i, R: Math.Round(t.x.Revenue, 0, MidpointRounding.AwayFromZero))).ToList();
            var diff = target - rounded.Sum(t => t.R);
            if (diff != 0 && rounded.Count > 0)
            {
                var big = rounded.OrderByDescending(t => t.R).First();
                rounded[rounded.IndexOf(big)] = (big.i, big.R + diff);
            }
            foreach (var (i, r) in rounded)
            {
                var x = parts[i];
                Add(x.ProductId, x.Name, x.Qty, r, x.Discount, x.SoldAt, x.OrderId);
            }
        }

        return map.Values
            .Select(x => x with { OrderCount = ordersByProduct.TryGetValue(x.ProductId, out var o) ? o.Count : 0 })
            .OrderByDescending(x => x.Revenue).ToList();
    }

    static DateTime? Max(DateTime? a, DateTime? b)
    {
        if (!a.HasValue) return b;
        if (!b.HasValue) return a;
        return a.Value >= b.Value ? a : b;
    }
}
