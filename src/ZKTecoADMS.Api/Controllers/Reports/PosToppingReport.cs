using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers.Reports;

/// <summary>
/// Báo cáo Topping cho người không chuyên: % ly (món cho chọn topping) có thêm topping, doanh thu / lãi topping,
/// topping bán chạy, món nào khách hay thêm topping; cảnh báo topping bán lỗ / hết hàng; việc nên làm.
/// Số lượng / tiền đã trừ hàng khách trả và phân bổ giảm giá đơn (cùng cách báo cáo Hàng hóa bán ra).
/// </summary>
internal static class PosToppingReport
{
    public sealed record ToppingRow(
        Guid ProductId, string Name, decimal Qty, decimal Revenue, decimal Cost, decimal Profit,
        decimal SharePct, decimal OnHand, bool TracksStock, string Level, string? Note);

    public sealed record DishRow(
        Guid ProductId, string Name, decimal Cups, decimal CupsWithTopping, decimal RatePct, decimal ToppingRevenue,
        decimal ToppingsPerCup);

    public sealed record DayRow(string Day, decimal Cups, decimal CupsWithTopping, decimal RatePct, decimal Revenue);

    public sealed record Recommendation(string Level, string Title, string Detail);

    public sealed record Result(
        string Verdict, string VerdictText, string VerdictDetail, object Summary,
        List<ToppingRow> Toppings, List<DishRow> Dishes, List<DayRow> Daily, List<Recommendation> Recommendations);

    /// <summary>Tỷ lệ ly có topping: ≥ 30% tốt, 15–30% trung bình, &lt; 15% thấp (cơ hội bán thêm).</summary>
    public static string RateLevel(decimal ratePct) => ratePct >= 30 ? "green" : ratePct >= 15 ? "yellow" : "red";

    public static async Task<Result> BuildAsync(
        ZKTecoDbContext db, Guid storeId, IReadOnlyCollection<Guid> orderIds, CancellationToken ct = default)
    {
        var lines = await PosReportMoney.NetLinesAsync(db, storeId, orderIds);
        var parentIds = lines.Select(l => l.ProductId).Distinct().ToList();
        var parents = await db.PosProducts.AsNoTracking()
            .Where(p => parentIds.Contains(p.Id))
            .Select(p => new { p.Id, p.Name, p.AllowToppings, p.ProductType })
            .ToDictionaryAsync(p => p.Id, ct);
        var groupLinked = (await db.PosProductToppingGroupLinks.AsNoTracking()
                .Where(l => parentIds.Contains(l.ProductId) && l.StoreId == storeId && l.Deleted == null && l.IsActive)
                .Select(l => l.ProductId).Distinct().ToListAsync(ct))
            .ToHashSet();

        // Món «cho chọn topping»: bật cho chọn topping / có nhóm topping, hoặc đã có ly được thêm topping.
        var picksByLine = lines.Select(l => (Line: l, Picks: PosSaleStockHelper.ParseToppingPicks(l.ToppingsJson))).ToList();
        var eligible = picksByLine
            .Where(x => x.Picks.Count > 0
                        || (parents.TryGetValue(x.Line.ProductId, out var p) && (p.AllowToppings || groupLinked.Contains(p.Id))))
            .ToList();

        var toppingAgg = new Dictionary<Guid, (string Name, decimal Qty, decimal Revenue)>();
        var dishAgg = new Dictionary<Guid, (string Name, decimal Cups, decimal With, decimal Revenue, decimal Portions)>();
        var dayAgg = new SortedDictionary<string, (decimal Cups, decimal With, decimal Revenue)>();
        foreach (var (l, picks) in eligible)
        {
            var cups = l.Qty;
            var with = picks.Count > 0 ? cups : 0;
            decimal revenue = 0, portions = 0;
            foreach (var t in picks)
            {
                var q = t.Qty * l.Qty;
                var r = t.UnitPrice * q * l.RevenueFactor;
                revenue += r;
                portions += q;
                var e = toppingAgg.GetValueOrDefault(t.ProductId, (string.IsNullOrWhiteSpace(t.Name) ? "Topping" : t.Name, 0, 0));
                toppingAgg[t.ProductId] = (e.Name, e.Qty + q, e.Revenue + r);
            }
            var name = parents.TryGetValue(l.ProductId, out var pp) ? pp.Name : l.ProductName;
            var d = dishAgg.GetValueOrDefault(l.ProductId, (name, 0, 0, 0, 0));
            dishAgg[l.ProductId] = (d.Name, d.Cups + cups, d.With + with, d.Revenue + revenue, d.Portions + portions);
            var day = (l.SoldAt ?? DateTime.UtcNow).AddHours(7).ToString("yyyy-MM-dd");
            var dd = dayAgg.GetValueOrDefault(day);
            dayAgg[day] = (dd.Cups + cups, dd.With + with, dd.Revenue + revenue);
        }

        var cogs = await PosReportMoney.CogsByProductAsync(db, storeId, orderIds);
        var toppingIds = toppingAgg.Keys.ToList();
        var toppingInfo = await db.PosProducts.AsNoTracking()
            .Where(p => toppingIds.Contains(p.Id))
            .Select(p => new { p.Id, p.OnHandQty, p.ProductType, p.CostPrice })
            .ToDictionaryAsync(p => p.Id, ct);
        var withRecipe = (await db.PosProductRecipeLines.AsNoTracking()
                .Where(r => toppingIds.Contains(r.ParentProductId) && r.Deleted == null)
                .Select(r => r.ParentProductId).Distinct().ToListAsync(ct))
            .ToHashSet();
        var totalToppingRevenue = toppingAgg.Values.Sum(x => x.Revenue);

        var toppings = toppingAgg.Select(kv =>
            {
                var (name, qty, rev) = kv.Value;
                var cost = Math.Round(cogs.GetValueOrDefault(kv.Key), 0);
                var revenue = Math.Round(rev, 0);
                var profit = revenue - cost;
                toppingInfo.TryGetValue(kv.Key, out var info);
                // Topping có định lượng: tồn nằm ở nguyên liệu, không xét «hết hàng» trên chính topping.
                var tracks = info != null && PosProductTypeRules.TracksInventory(info.ProductType) && !withRecipe.Contains(kv.Key);
                var onHand = info?.OnHandQty ?? 0;
                string level;
                string? note = null;
                if (revenue > 0 && profit < 0)
                {
                    level = "red";
                    note = "Bán lỗ: giá vốn cao hơn giá bán";
                }
                else if (tracks && onHand <= 0)
                {
                    level = "red";
                    note = "Hết hàng trong kho";
                }
                else if (revenue > 0 && profit / revenue < 0.3m)
                {
                    level = "yellow";
                    note = "Lãi thấp (< 30%)";
                }
                else if (cost <= 0 && revenue > 0)
                {
                    level = "yellow";
                    note = "Chưa có giá vốn — lãi đang tính 100%";
                }
                else level = "green";
                return new ToppingRow(kv.Key, name, Math.Round(qty, 2), revenue, cost, profit,
                    totalToppingRevenue > 0 ? Math.Round(rev / totalToppingRevenue * 100, 1) : 0,
                    onHand, tracks, level, note);
            })
            .OrderByDescending(t => t.Qty).ThenByDescending(t => t.Revenue)
            .ToList();

        var dishes = dishAgg.Select(kv => new DishRow(
                kv.Key, kv.Value.Name, Math.Round(kv.Value.Cups, 2), Math.Round(kv.Value.With, 2),
                kv.Value.Cups > 0 ? Math.Round(kv.Value.With / kv.Value.Cups * 100, 1) : 0,
                Math.Round(kv.Value.Revenue, 0),
                kv.Value.With > 0 ? Math.Round(kv.Value.Portions / kv.Value.With, 2) : 0))
            .OrderByDescending(d => d.Cups)
            .ToList();
        var daily = dayAgg.Select(kv => new DayRow(kv.Key, kv.Value.Cups, kv.Value.With,
                kv.Value.Cups > 0 ? Math.Round(kv.Value.With / kv.Value.Cups * 100, 1) : 0, Math.Round(kv.Value.Revenue, 0)))
            .ToList();

        var cupsTotal = dishes.Sum(d => d.Cups);
        var cupsWith = dishes.Sum(d => d.CupsWithTopping);
        var rate = cupsTotal > 0 ? Math.Round(cupsWith / cupsTotal * 100, 1) : 0;
        var revenueTotal = toppings.Sum(t => t.Revenue);
        var costTotal = toppings.Sum(t => t.Cost);
        var portionsTotal = toppings.Sum(t => t.Qty);
        var losing = toppings.Where(t => t.Note?.StartsWith("Bán lỗ") == true).ToList();
        var outOfStock = toppings.Where(t => t.Note == "Hết hàng trong kho").ToList();
        var groupCount = await db.PosToppingGroups.AsNoTracking()
            .CountAsync(g => g.StoreId == storeId && g.Deleted == null && g.IsActive, ct);

        string verdict, verdictText, verdictDetail;
        if (cupsTotal <= 0)
        {
            verdict = "none";
            verdictText = groupCount == 0 ? "Chưa dùng topping" : "Kỳ này chưa bán món có topping";
            verdictDetail = groupCount == 0
                ? "Tạo nhóm topping (vd «Topping trà sữa») rồi gắn vào các món để thu ngân chọn khi bán."
                : "Chưa có ly nào của món cho chọn topping trong kỳ đã chọn.";
        }
        else if (losing.Count > 0 || outOfStock.Count > 0)
        {
            verdict = "red";
            verdictText = losing.Count > 0
                ? $"{losing.Count} topping đang bán lỗ — cần chỉnh giá hoặc định lượng"
                : $"{outOfStock.Count} topping đã hết hàng — nhập thêm để không mất doanh thu";
            verdictDetail = string.Join(", ", losing.Concat(outOfStock).Take(4).Select(t => t.Name));
        }
        else
        {
            verdict = RateLevel(rate);
            verdictText = verdict switch
            {
                "green" => $"{rate:0.#}% ly có thêm topping — bán thêm tốt",
                "yellow" => $"{rate:0.#}% ly có thêm topping — còn có thể mời khách nhiều hơn",
                _ => $"Chỉ {rate:0.#}% ly có thêm topping — đang bỏ lỡ doanh thu",
            };
            verdictDetail = $"Topping mang về {revenueTotal:#,##0}đ, lãi {revenueTotal - costTotal:#,##0}đ.";
        }

        var recs = new List<Recommendation>();
        foreach (var t in losing.Take(3))
            recs.Add(new("red", $"Chỉnh giá «{t.Name}»",
                $"Bán {t.Revenue:#,##0}đ nhưng giá vốn {t.Cost:#,##0}đ (lỗ {-t.Profit:#,##0}đ). Tăng giá thêm hoặc giảm định lượng."));
        foreach (var t in outOfStock.Take(3))
            recs.Add(new("red", $"Nhập thêm «{t.Name}»", "Topping hết hàng trong kho — thu ngân bán sẽ bị báo hết."));
        if (cupsTotal > 0 && rate < 30)
            recs.Add(new(rate < 15 ? "yellow" : "info", "Mời khách thêm topping",
                "Bật «Tự mở hộp chọn topping» cho món, nhắc thu ngân hỏi «Anh/chị thêm trân châu không?», làm combo ly + topping giá ưu đãi."));
        var lowDishes = dishes.Where(d => d.Cups >= 10 && d.RatePct < 10).Take(3).ToList();
        if (lowDishes.Count > 0)
            recs.Add(new("info", "Món bán chạy nhưng ít khi thêm topping",
                $"{string.Join(", ", lowDishes.Select(d => $"{d.Name} ({d.RatePct:0.#}%)"))} — kiểm tra món đã gắn đúng nhóm topping chưa."));
        foreach (var t in toppings.Where(t => t.Note?.StartsWith("Chưa có giá vốn") == true).Take(2))
            recs.Add(new("info", $"Khai giá vốn / định lượng cho «{t.Name}»", "Chưa có giá vốn nên lãi topping đang tính cao hơn thực tế."));

        var summary = new
        {
            cups = cupsTotal,
            cupsWithTopping = cupsWith,
            ratePct = rate,
            rateLevel = cupsTotal > 0 ? RateLevel(rate) : "none",
            toppingRevenue = revenueTotal,
            toppingCost = costTotal,
            toppingProfit = revenueTotal - costTotal,
            marginPct = revenueTotal > 0 ? Math.Round((revenueTotal - costTotal) / revenueTotal * 100, 1) : 0,
            portions = portionsTotal,
            avgPerCup = cupsWith > 0 ? Math.Round(portionsTotal / cupsWith, 2) : 0,
            revenuePerCup = cupsTotal > 0 ? Math.Round(revenueTotal / cupsTotal, 0) : 0,
            toppingKinds = toppings.Count,
            groupCount,
        };
        return new Result(verdict, verdictText, verdictDetail, summary, toppings, dishes, daily, recs);
    }
}
