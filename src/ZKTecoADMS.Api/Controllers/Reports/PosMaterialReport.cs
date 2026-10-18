using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers.Reports;

/// <summary>
/// Báo cáo Nguyên vật liệu cho người không chuyên: mỗi NVL đã dùng bao nhiêu (theo định lượng món / topping / combo),
/// cho món nào, tốn bao nhiêu tiền, còn đủ dùng mấy ngày; nhập / hủy trong kỳ; kết luận xanh / vàng / đỏ + việc nên làm.
/// Số liệu lấy từ thẻ kho (đã trừ phần hoàn khi hủy đơn / trả hàng).
/// </summary>
internal static class PosMaterialReport
{
    const string RecipePrefix = "Định lượng:";
    const string ComboPrefix = "Bán combo:";

    public sealed record DishUse(string Name, decimal Qty, decimal Value);

    public sealed record MaterialRow(
        Guid ProductId, string Code, string Name, string Unit, string Type,
        decimal OnHand, decimal MinStock, decimal CostPrice,
        decimal UsedQty, decimal UsedValue, decimal ReceivedQty, decimal WastedQty, decimal WastedValue,
        decimal AvgPerDay, decimal? DaysLeft, string Level, string LevelText, List<DishUse> Dishes);

    public sealed record DayValue(string Day, decimal Value);

    public sealed record NoRecipeDish(Guid ProductId, string Name, decimal SoldQty, decimal OnHand);

    public sealed record Recommendation(string Level, string Title, string Detail);

    public sealed record Result(
        string Verdict, string VerdictText, string VerdictDetail, int Days,
        object Summary, List<MaterialRow> Materials, List<DayValue> Daily, List<DishUse> TopDishes,
        List<NoRecipeDish> NoRecipeDishes, List<Recommendation> Recommendations);

    /// <summary>Tên món từ ghi chú thẻ kho «Định lượng: Trà sữa» / «Bán combo: Combo 1 — hoàn định lượng: …».</summary>
    public static string DishOf(string? note)
    {
        if (string.IsNullOrWhiteSpace(note)) return "Khác";
        foreach (var prefix in new[] { RecipePrefix, ComboPrefix, PosSaleReturnLedger.RecipeReturnMarker, PosSaleReturnLedger.ComboReturnMarker })
        {
            var i = note.IndexOf(prefix, StringComparison.OrdinalIgnoreCase);
            if (i >= 0)
            {
                var name = note[(i + prefix.Length)..].Trim();
                return name.Length == 0 ? "Khác" : name;
            }
        }
        return "Khác";
    }

    /// <param name="tx">Thẻ kho đã lọc chi nhánh của người xem.</param>
    /// <param name="orderIds">Đơn hoàn tất trong kỳ — tìm món bán mà chưa khai định lượng.</param>
    public static async Task<Result> BuildAsync(
        ZKTecoDbContext db, Guid storeId, IQueryable<PosStockTransaction> tx,
        DateTime fromUtc, DateTime toUtc, IReadOnlyCollection<Guid> orderIds, CancellationToken ct = default)
    {
        // Câu kết luận / việc nên làm ghi số kiểu Việt («15.000đ», «0,4 ngày»); chỉ có hiệu lực trong phương thức async này.
        System.Globalization.CultureInfo.CurrentCulture = System.Globalization.CultureInfo.GetCultureInfo("vi-VN");
        var days = Math.Max(1, (int)Math.Ceiling((toUtc - fromUtc).TotalDays));
        var recipeComponentIds = await db.PosProductRecipeLines.AsNoTracking()
            .Where(r => r.StoreId == storeId && r.Deleted == null)
            .Select(r => r.ComponentProductId).Distinct().ToListAsync(ct);
        var products = await db.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null
                        && (p.ProductType == PosProductType.Material || recipeComponentIds.Contains(p.Id)))
            .Select(p => new { p.Id, p.ProductCode, p.Name, p.BaseUnitName, p.ProductType, p.OnHandQty, p.MinStockQty, p.CostPrice, p.IsActive })
            .ToListAsync(ct);
        var ids = products.Select(p => p.Id).ToList();
        var materialIds = products.Where(p => p.ProductType == PosProductType.Material).Select(p => p.Id).ToHashSet();

        var rows = await tx.AsNoTracking()
            .Where(t => t.StoreId == storeId && t.Deleted == null && ids.Contains(t.ProductId)
                        && t.CreatedAt >= fromUtc && t.CreatedAt < toUtc)
            .Select(t => new { t.ProductId, t.TransactionType, t.QtyChange, t.LineAmount, t.UnitCost, t.Note, t.SaleOrderId, t.CreatedAt })
            .ToListAsync(ct);

        // Dùng theo định lượng: phiếu bán (−) trừ phần hoàn khi hủy đơn / trả hàng (+).
        bool IsUse(Guid pid, PosStockTransactionType type, string? note) =>
            type == PosStockTransactionType.Sale
            && (materialIds.Contains(pid)
                || (note != null && (note.StartsWith(RecipePrefix) || note.StartsWith(ComboPrefix))));
        bool IsUseReversal(Guid pid, PosStockTransactionType type, string? note, Guid? orderId) =>
            type == PosStockTransactionType.Return && orderId != null
            && (materialIds.Contains(pid)
                || (note != null && (note.Contains(PosSaleReturnLedger.RecipeReturnMarker) || note.Contains(PosSaleReturnLedger.ComboReturnMarker))));

        // Hủy đơn ghi «Hủy đơn: HD…» (không có tên món) → lấy món của phiếu bán cùng đơn.
        var saleDish = rows.Where(t => t.SaleOrderId != null && IsUse(t.ProductId, t.TransactionType, t.Note))
            .GroupBy(t => (t.SaleOrderId!.Value, t.ProductId))
            .ToDictionary(g => g.Key, g => DishOf(g.First().Note));
        var uses = new List<(Guid Pid, string Dish, decimal Qty, decimal Value, DateTime At)>();
        foreach (var t in rows)
        {
            if (IsUse(t.ProductId, t.TransactionType, t.Note))
                uses.Add((t.ProductId, DishOf(t.Note), -t.QtyChange, t.LineAmount ?? 0, t.CreatedAt));
            else if (IsUseReversal(t.ProductId, t.TransactionType, t.Note, t.SaleOrderId))
            {
                var dish = DishOf(t.Note);
                if (dish == "Khác" && saleDish.TryGetValue((t.SaleOrderId!.Value, t.ProductId), out var d)) dish = d;
                uses.Add((t.ProductId, dish, -t.QtyChange, -(t.QtyChange * (t.UnitCost ?? 0)), t.CreatedAt));
            }
        }

        var materials = new List<MaterialRow>();
        foreach (var p in products)
        {
            var mine = uses.Where(u => u.Pid == p.Id).ToList();
            var usedQty = mine.Sum(u => u.Qty);
            var usedValue = mine.Sum(u => u.Value);
            var mineTx = rows.Where(r => r.ProductId == p.Id).ToList();
            var received = mineTx.Where(r => r.TransactionType is PosStockTransactionType.Purchase or PosStockTransactionType.StockIn
                                             && r.QtyChange > 0).Sum(r => r.QtyChange);
            var wasted = mineTx.Where(r => r.TransactionType is PosStockTransactionType.StockOut or PosStockTransactionType.Adjust
                                           && r.QtyChange < 0).ToList();
            var wastedQty = wasted.Sum(r => -r.QtyChange);
            var wastedValue = wasted.Sum(r => r.LineAmount ?? -r.QtyChange * (r.UnitCost ?? p.CostPrice));
            var avg = usedQty > 0 ? usedQty / days : 0;
            decimal? daysLeft = avg > 0 ? Math.Round(Math.Max(0, p.OnHandQty) / avg, 1) : null;
            var (level, text) = LevelOf(p.OnHandQty, p.MinStockQty, usedQty, daysLeft);
            if (!p.IsActive && usedQty <= 0) continue;
            materials.Add(new MaterialRow(
                p.Id, p.ProductCode, p.Name, p.BaseUnitName, p.ProductType.ToString(),
                p.OnHandQty, p.MinStockQty, p.CostPrice,
                Math.Round(usedQty, 4), Math.Round(usedValue, 0), Math.Round(received, 4),
                Math.Round(wastedQty, 4), Math.Round(wastedValue, 0),
                Math.Round(avg, 4), daysLeft, level, text,
                mine.GroupBy(u => u.Dish)
                    .Select(g => new DishUse(g.Key, Math.Round(g.Sum(x => x.Qty), 4), Math.Round(g.Sum(x => x.Value), 0)))
                    .Where(d => d.Qty != 0)
                    .OrderByDescending(d => d.Value).ThenByDescending(d => d.Qty).Take(8).ToList()));
        }
        materials = materials
            .OrderBy(m => Rank(m.Level)).ThenBy(m => m.DaysLeft ?? decimal.MaxValue).ThenByDescending(m => m.UsedValue)
            .ToList();

        var daily = uses.GroupBy(u => u.At.AddHours(7).Date)
            .OrderBy(g => g.Key)
            .Select(g => new DayValue(g.Key.ToString("yyyy-MM-dd"), Math.Round(g.Sum(x => x.Value), 0)))
            .ToList();
        var topDishes = uses.GroupBy(u => u.Dish)
            .Select(g => new DishUse(g.Key, Math.Round(g.Sum(x => x.Qty), 4), Math.Round(g.Sum(x => x.Value), 0)))
            .Where(d => d.Value > 0)
            .OrderByDescending(d => d.Value).Take(10).ToList();

        var noRecipe = await NoRecipeDishesAsync(db, storeId, orderIds, ct);

        var red = materials.Count(m => m.Level == "red");
        var yellow = materials.Count(m => m.Level == "yellow");
        var negative = materials.Count(m => m.OnHand < 0);
        var usedTotal = materials.Sum(m => m.UsedValue);
        var wasteTotal = materials.Sum(m => m.WastedValue);
        var usedCount = materials.Count(m => m.UsedQty > 0);
        var hasRecipes = recipeComponentIds.Count > 0;

        string verdict, verdictText, verdictDetail;
        if (materials.Count == 0)
        {
            verdict = "none";
            verdictText = "Chưa có nguyên vật liệu nào";
            verdictDetail = "Tạo hàng loại «Nguyên vật liệu» và khai định lượng cho món để biết mỗi ngày dùng bao nhiêu, còn đủ mấy ngày.";
        }
        else if (red > 0)
        {
            verdict = "red";
            verdictText = $"{red} nguyên liệu đã hết hoặc sắp hết trong 2 ngày — cần nhập ngay";
            verdictDetail = string.Join(", ", materials.Where(m => m.Level == "red").Take(4).Select(m => m.Name));
        }
        else if (yellow > 0 || negative > 0)
        {
            verdict = "yellow";
            verdictText = yellow > 0
                ? $"{yellow} nguyên liệu chỉ đủ dùng dưới 5 ngày — nên nhập trong tuần"
                : $"{negative} nguyên liệu bị âm kho — cần kiểm kê lại";
            verdictDetail = string.Join(", ", materials.Where(m => m.Level == "yellow" || m.OnHand < 0).Take(4).Select(m => m.Name));
        }
        else if (usedCount == 0)
        {
            verdict = "none";
            verdictText = "Kỳ này chưa dùng nguyên liệu nào";
            verdictDetail = hasRecipes
                ? "Chưa bán món có khai định lượng trong kỳ đã chọn."
                : "Món chưa khai định lượng nên bán không trừ nguyên liệu.";
        }
        else
        {
            verdict = "green";
            verdictText = "Nguyên liệu đủ dùng — không có gì sắp hết";
            verdictDetail = $"Đã dùng {usedCount} loại nguyên liệu, trị giá {usedTotal:#,##0}đ trong {days} ngày.";
        }

        var recs = new List<Recommendation>();
        foreach (var m in materials.Where(m => m.Level == "red").Take(5))
            recs.Add(new("red", $"Nhập ngay «{m.Name}»",
                m.OnHand <= 0
                    ? $"Đã hết (tồn {m.OnHand:0.##} {m.Unit}). Món dùng nhiều: {string.Join(", ", m.Dishes.Take(3).Select(d => d.Name))}."
                    : $"Còn {m.OnHand:0.##} {m.Unit}, dùng ~{m.AvgPerDay:0.##} {m.Unit}/ngày → đủ khoảng {m.DaysLeft:0.#} ngày."));
        foreach (var m in materials.Where(m => m.Level == "yellow").Take(5))
            recs.Add(new("yellow", $"Lên kế hoạch nhập «{m.Name}»",
                m.DaysLeft is decimal d
                    ? $"Đủ dùng khoảng {d:0.#} ngày (dùng ~{m.AvgPerDay:0.##} {m.Unit}/ngày)."
                    : $"Tồn {m.OnHand:0.##} {m.Unit} ≤ mức tối thiểu {m.MinStock:0.##}."));
        if (negative > 0)
            recs.Add(new("yellow", "Kiểm kê nguyên liệu bị âm kho",
                $"{negative} nguyên liệu tồn âm — thường do nhập hàng chưa ghi phiếu hoặc định lượng khai thừa. Vào Kho › Kiểm kho để chỉnh."));
        if (noRecipe.Count > 0)
            recs.Add(new("yellow", "Khai định lượng cho món pha chế / chế biến",
                $"{string.Join(", ", noRecipe.Take(4).Select(d => d.Name))} bán ra nhưng không trừ nguyên liệu (tồn món đang âm). Vào Hàng hóa › sửa món › Định lượng NVL."));
        if (wasteTotal > 0 && usedTotal > 0 && wasteTotal / usedTotal > 0.05m)
            recs.Add(new("yellow", "Hao hụt / hủy nguyên liệu cao",
                $"Xuất hủy / kiểm kê thiếu {wasteTotal:#,##0}đ = {wasteTotal / usedTotal * 100:0.#}% lượng dùng. Kiểm tra bảo quản, hạn dùng và định lượng."));
        if (!hasRecipes && materials.Count > 0)
            recs.Add(new("info", "Khai định lượng để trừ nguyên liệu tự động",
                "Có nguyên liệu nhưng chưa món nào khai định lượng — bán hàng không trừ nguyên liệu, báo cáo này sẽ trống."));

        var summary = new
        {
            materialCount = materials.Count,
            usedCount,
            usedValue = usedTotal,
            usedPerDay = Math.Round(usedTotal / days, 0),
            redCount = red,
            yellowCount = yellow,
            negativeCount = negative,
            wastedValue = wasteTotal,
            noRecipeDishCount = noRecipe.Count,
            recipeConfigured = hasRecipes,
        };
        return new Result(verdict, verdictText, verdictDetail, days, summary, materials, daily, topDishes, noRecipe, recs);
    }

    /// <summary>Hết / sắp hết theo số ngày còn đủ dùng (mức dùng bình quân trong kỳ) và tồn tối thiểu.</summary>
    public static (string Level, string Text) LevelOf(decimal onHand, decimal minStock, decimal usedQty, decimal? daysLeft)
    {
        if (onHand <= 0 && (usedQty > 0 || minStock > 0)) return ("red", "Đã hết");
        if (daysLeft is decimal d && d < 2) return ("red", "Sắp hết (< 2 ngày)");
        if (daysLeft is decimal d2 && d2 < 5) return ("yellow", "Đủ < 5 ngày");
        if (minStock > 0 && onHand <= minStock) return ("yellow", "Dưới tồn tối thiểu");
        if (usedQty <= 0) return ("none", "Không dùng trong kỳ");
        return ("green", "Đủ dùng");
    }

    static int Rank(string level) => level switch { "red" => 0, "yellow" => 1, "green" => 2, _ => 3 };

    /// <summary>Món bán trong kỳ, không khai định lượng mà tồn món âm — thường là món pha chế quên khai NVL.</summary>
    static async Task<List<NoRecipeDish>> NoRecipeDishesAsync(
        ZKTecoDbContext db, Guid storeId, IReadOnlyCollection<Guid> orderIds, CancellationToken ct)
    {
        if (orderIds.Count == 0) return [];
        var sold = await db.PosSaleOrderLines.AsNoTracking()
            .Where(l => l.StoreId == storeId && l.Deleted == null && orderIds.Contains(l.SaleOrderId))
            .GroupBy(l => l.ProductId)
            .Select(g => new { ProductId = g.Key, Qty = g.Sum(x => x.Qty) })
            .ToListAsync(ct);
        var soldIds = sold.Select(s => s.ProductId).ToList();
        var withRecipe = (await db.PosProductRecipeLines.AsNoTracking()
                .Where(r => r.StoreId == storeId && r.Deleted == null && soldIds.Contains(r.ParentProductId))
                .Select(r => r.ParentProductId).Distinct().ToListAsync(ct))
            .ToHashSet();
        var candidates = await db.PosProducts.AsNoTracking()
            .Where(p => soldIds.Contains(p.Id) && p.ProductType == PosProductType.Goods && p.OnHandQty < 0)
            .Select(p => new { p.Id, p.Name, p.OnHandQty })
            .ToListAsync(ct);
        var qty = sold.ToDictionary(s => s.ProductId, s => s.Qty);
        return candidates.Where(p => !withRecipe.Contains(p.Id))
            .Select(p => new NoRecipeDish(p.Id, p.Name, qty.GetValueOrDefault(p.Id), p.OnHandQty))
            .OrderByDescending(p => p.SoldQty).Take(10).ToList();
    }
}
