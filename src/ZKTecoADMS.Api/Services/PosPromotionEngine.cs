using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Bản server của pos_promotion_engine.dart — tính tiền khuyến mãi tự áp cho giỏ hàng.
/// Dùng để kiểm tra quyền «Giảm giá khi bán»: khuyến mãi do hệ thống tính không phải giảm tay,
/// nên thu ngân không có quyền giảm giá vẫn bán được hàng đang khuyến mãi. Giữ khớp với bản Dart.
/// </summary>
public static class PosPromotionEngine
{
    public sealed record Line(string Key, Guid ProductId, Guid? CategoryId, bool HasBarcode, decimal Qty, decimal Gross)
    {
        public decimal Unit => Qty > 0 ? Gross / Qty : 0;
    }

    public sealed class Result
    {
        public Dictionary<string, decimal> LineDiscount { get; } = new();
        public decimal BillDiscount { get; set; }
    }

    sealed class Promo
    {
        public required PosPromotion Entity { get; init; }
        public required JsonElement Config { get; init; }
        public HashSet<Guid> Resolved { get; init; } = [];

        public decimal Num(string key, decimal fallback = 0)
        {
            if (Config.ValueKind != JsonValueKind.Object || !Config.TryGetProperty(key, out var v)) return fallback;
            if (v.ValueKind == JsonValueKind.Number && v.TryGetDecimal(out var d)) return d;
            if (v.ValueKind == JsonValueKind.String && decimal.TryParse(v.GetString(), System.Globalization.NumberStyles.Any,
                    System.Globalization.CultureInfo.InvariantCulture, out var s)) return s;
            return fallback;
        }

        public string? Str(string key)
        {
            if (Config.ValueKind != JsonValueKind.Object || !Config.TryGetProperty(key, out var v)) return null;
            var s = v.ValueKind == JsonValueKind.String ? v.GetString() : v.ToString();
            return string.IsNullOrEmpty(s) ? null : s;
        }

        public bool Matches(Line l)
        {
            if (Entity.Type == "near_expiry") return Resolved.Contains(l.ProductId);
            if (Config.ValueKind != JsonValueKind.Object || !Config.TryGetProperty("target", out var t) ||
                t.ValueKind != JsonValueKind.Object) return true;
            var scope = t.TryGetProperty("scope", out var sc) ? sc.ToString() : "all";
            switch (scope)
            {
                case "categories":
                    if (l.CategoryId == null || !t.TryGetProperty("categoryIds", out var cats) ||
                        cats.ValueKind != JsonValueKind.Array) return false;
                    var cid = l.CategoryId.Value.ToString();
                    return cats.EnumerateArray().Any(e => string.Equals(e.ToString(), cid, StringComparison.OrdinalIgnoreCase));
                case "products":
                    if (!t.TryGetProperty("products", out var ps) || ps.ValueKind != JsonValueKind.Array) return false;
                    var pid = l.ProductId.ToString();
                    return ps.EnumerateArray().Any(e =>
                    {
                        var id = e.ValueKind == JsonValueKind.Object && e.TryGetProperty("id", out var i) ? i.ToString() : e.ToString();
                        return string.Equals(id, pid, StringComparison.OrdinalIgnoreCase);
                    });
                case "barcoded":
                    return l.HasBarcode;
                default:
                    return true;
            }
        }

        /// <summary>Khớp PosPromotion.isLiveAt (Dart) — [now] là giờ Việt Nam.</summary>
        public bool IsLiveAt(DateTime now, bool hasCustomer)
        {
            var p = Entity;
            if (!p.IsActive) return false;
            if (p.MembersOnly && !hasCustomer) return false;
            var from = p.TimeFromMinutes;
            var to = p.TimeToMinutes;
            var m = now.Hour * 60 + now.Minute;
            var overnightTail = from != null && to != null && from > to && m < to;
            var day = (overnightTail ? now.AddDays(-1) : now).Date;
            if (p.ValidFrom != null && day < p.ValidFrom.Value.Date) return false;
            if (p.ValidTo != null && day > p.ValidTo.Value.Date) return false;
            if (p.DaysOfWeekMask != 0)
            {
                var bit = ((int)day.DayOfWeek + 6) % 7; // Thứ 2 = bit0 … CN = bit6
                if ((p.DaysOfWeekMask & (1 << bit)) == 0) return false;
            }
            if (from != null && to != null && from != to)
            {
                var inside = from < to ? m >= from && m < to : m >= from || m < to;
                if (!inside) return false;
            }
            return true;
        }
    }

    /// <summary>Nạp chương trình đang bật của cửa hàng (kèm hàng cận hạn đã tính).</summary>
    public static async Task<List<object>> LoadAsync(ZKTecoDbContext db, Guid storeId, CancellationToken ct = default)
    {
        var rows = await db.PosPromotions.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.IsActive)
            .ToListAsync(ct);
        var list = new List<object>();
        foreach (var p in rows)
        {
            JsonElement cfg;
            try { cfg = JsonDocument.Parse(string.IsNullOrWhiteSpace(p.ConfigJson) ? "{}" : p.ConfigJson).RootElement.Clone(); }
            catch { cfg = JsonDocument.Parse("{}").RootElement.Clone(); }
            HashSet<Guid> resolved = [];
            if (p.Type == "near_expiry")
            {
                var days = cfg.TryGetProperty("nearExpiryDays", out var d) && d.TryGetInt32(out var n) ? n : 3;
                resolved = (await NearExpiryProductIdsAsync(db, storeId, days, ct)).ToHashSet();
            }
            list.Add(new Promo { Entity = p, Config = cfg, Resolved = resolved });
        }
        return list;
    }

    /// <summary>Dựng danh sách chương trình từ entity (không tính hàng cận hạn) — dùng cho test.</summary>
    public static List<object> FromEntities(IEnumerable<PosPromotion> rows) =>
        rows.Select(p => (object)new Promo
        {
            Entity = p,
            Config = JsonDocument.Parse(string.IsNullOrWhiteSpace(p.ConfigJson) ? "{}" : p.ConfigJson).RootElement.Clone(),
        }).ToList();

    static async Task<List<Guid>> NearExpiryProductIdsAsync(ZKTecoDbContext db, Guid storeId, int days, CancellationToken ct)
    {
        var today = PosStockLotHelper.ExpiryCutoffUtc();
        var until = today.AddDays(Math.Clamp(days, 0, 365));
        return await db.PosStockLots.AsNoTracking()
            .Where(l => l.StoreId == storeId && l.Deleted == null && l.IsActive &&
                        l.Status == PosStockLotStatus.Active && l.QtyOnHand > 0 &&
                        l.ExpiryDate != null && l.ExpiryDate >= today)
            .GroupBy(l => l.ProductId)
            .Where(g => g.Min(l => l.ExpiryDate) <= until)
            .Select(g => g.Key)
            .ToListAsync(ct);
    }

    sealed class Cand(Promo p, decimal amount)
    {
        public Promo P { get; } = p;
        public decimal Amount { get; set; } = amount;
    }

    /// <summary>Tính khuyến mãi (giảm tay coi như 0 — dùng để biết phần nào là khuyến mãi).</summary>
    public static Result Compute(IReadOnlyList<object> promotions, IReadOnlyList<Line> lines, DateTime nowVn, bool hasCustomer)
    {
        var res = new Result();
        var live = promotions.Cast<Promo>().Where(p => p.IsLiveAt(nowVn, hasCustomer)).ToList();
        if (live.Count == 0 || lines.Count == 0) return res;

        var cands = lines.ToDictionary(l => l.Key, _ => new List<Cand>());
        void Add(Promo p, string key, decimal amount)
        {
            if (amount <= 0.0001m) return;
            var list = cands[key];
            var existing = list.FirstOrDefault(c => ReferenceEquals(c.P, p));
            if (existing != null) existing.Amount += amount;
            else list.Add(new Cand(p, amount));
        }

        foreach (var p in live)
        {
            switch (p.Entity.Type)
            {
                case "time_discount":
                case "near_expiry":
                {
                    var pct = p.Num("percent");
                    var perUnit = p.Num("amountPerUnit");
                    var salePrice = p.Num("salePrice");
                    foreach (var l in lines.Where(p.Matches))
                    {
                        decimal off = salePrice > 0 ? Math.Max(0, l.Unit - salePrice)
                            : pct > 0 ? l.Unit * Math.Min(pct, 100) / 100
                            : Math.Min(perUnit, l.Unit);
                        Add(p, l.Key, off * l.Qty);
                    }
                    break;
                }
                case "qty_discount":
                {
                    var tiers = new List<(decimal Min, decimal Pct)>();
                    if (p.Config.TryGetProperty("tiers", out var tArr) && tArr.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var t in tArr.EnumerateArray())
                        {
                            if (t.ValueKind != JsonValueKind.Object) continue;
                            var min = t.TryGetProperty("minQty", out var a) && a.TryGetDecimal(out var av) ? av : 0;
                            var pc = t.TryGetProperty("percent", out var b) && b.TryGetDecimal(out var bv) ? bv : 0;
                            if (min > 0 && pc > 0) tiers.Add((min, pc));
                        }
                    }
                    if (tiers.Count == 0) break;
                    tiers.Sort((x, y) => y.Min.CompareTo(x.Min));
                    var mixed = p.Config.TryGetProperty("mixed", out var mx) && mx.ValueKind == JsonValueKind.True;
                    foreach (var g in lines.Where(p.Matches).GroupBy(l => mixed ? "*" : l.ProductId.ToString()))
                    {
                        var q = g.Sum(l => l.Qty);
                        var tier = tiers.FirstOrDefault(t => q >= t.Min);
                        if (tier.Min <= 0) continue;
                        foreach (var l in g) Add(p, l.Key, l.Gross * Math.Min(tier.Pct, 100) / 100);
                    }
                    break;
                }
                case "buy_x_get_y":
                {
                    var buy = (int)Math.Floor(p.Num("buyQty", 1));
                    var get = (int)Math.Floor(p.Num("getQty", 1));
                    var giftPct = Math.Min(p.Num("giftPercent", 100), 100) / 100;
                    var giftId = p.Str("giftProductId");
                    if (buy <= 0 || get <= 0) break;
                    if (giftId == null)
                    {
                        foreach (var g in lines.Where(p.Matches).GroupBy(l => l.ProductId))
                        {
                            var q = (int)Math.Floor(g.Sum(l => l.Qty));
                            var free = q / (buy + get) * get;
                            foreach (var l in g)
                            {
                                if (free <= 0) break;
                                var take = Math.Min(free, (int)Math.Floor(l.Qty));
                                Add(p, l.Key, take * l.Unit * giftPct);
                                free -= take;
                            }
                        }
                    }
                    else
                    {
                        var buyCount = (int)Math.Floor(lines
                            .Where(l => !string.Equals(l.ProductId.ToString(), giftId, StringComparison.OrdinalIgnoreCase) && p.Matches(l))
                            .Sum(l => l.Qty));
                        decimal left = buyCount / buy * get;
                        foreach (var l in lines.Where(l => string.Equals(l.ProductId.ToString(), giftId, StringComparison.OrdinalIgnoreCase)))
                        {
                            if (left <= 0) break;
                            var take = Math.Min(left, l.Qty);
                            Add(p, l.Key, take * l.Unit * giftPct);
                            left -= take;
                        }
                    }
                    break;
                }
                case "combo_price":
                {
                    var n = (int)Math.Floor(p.Num("comboQty"));
                    var price = p.Num("comboPrice");
                    if (n <= 1 || price <= 0) break;
                    var units = new List<(string Key, decimal Unit)>();
                    foreach (var l in lines.Where(p.Matches))
                        for (var i = 0; i < (int)Math.Floor(l.Qty); i++) units.Add((l.Key, l.Unit));
                    units.Sort((a, b) => b.Unit.CompareTo(a.Unit));
                    for (var i = 0; i + n <= units.Count; i += n)
                    {
                        var group = units.GetRange(i, n);
                        var sum = group.Sum(u => u.Unit);
                        var off = sum - price;
                        if (off <= 0) continue;
                        foreach (var u in group) Add(p, u.Key, off * u.Unit / sum);
                    }
                    break;
                }
                case "addon_price":
                {
                    var addonId = p.Str("addonProductId");
                    var addonPrice = p.Num("addonPrice");
                    var maxPer = p.Num("maxPerTrigger", 1);
                    if (addonId == null) break;
                    var triggers = Math.Floor(lines
                        .Where(l => !string.Equals(l.ProductId.ToString(), addonId, StringComparison.OrdinalIgnoreCase) && p.Matches(l))
                        .Sum(l => l.Qty));
                    if (triggers <= 0) break;
                    var allowed = maxPer > 0 ? triggers * maxPer : decimal.MaxValue;
                    foreach (var l in lines.Where(l => string.Equals(l.ProductId.ToString(), addonId, StringComparison.OrdinalIgnoreCase)))
                    {
                        if (allowed <= 0) continue;
                        var take = Math.Min(allowed, l.Qty);
                        Add(p, l.Key, take * Math.Max(0, l.Unit - addonPrice));
                        allowed -= take;
                    }
                    break;
                }
            }
        }

        // Mỗi dòng: chương trình không cộng dồn lớn nhất + mọi chương trình cộng dồn; không vượt thành tiền.
        decimal afterLines = 0;
        foreach (var l in lines)
        {
            var list = cands[l.Key];
            var exclusive = list.Where(c => !c.P.Entity.Stackable)
                .OrderByDescending(c => c.Amount).ThenByDescending(c => c.P.Entity.Priority).ToList();
            var chosen = new List<Cand>();
            if (exclusive.Count > 0) chosen.Add(exclusive[0]);
            chosen.AddRange(list.Where(c => c.P.Entity.Stackable));
            var sum = chosen.Sum(c => c.Amount);
            var cap = Math.Max(0, l.Gross);
            var scale = sum > cap && sum > 0 ? cap / sum : 1m;
            sum = 0;
            foreach (var c in chosen)
            {
                var a = Math.Round(c.Amount * scale, 0, MidpointRounding.AwayFromZero);
                if (a > 0) sum += a;
            }
            if (sum > 0) res.LineDiscount[l.Key] = sum;
            afterLines += Math.Max(0, cap - sum);
        }

        // Giảm hóa đơn.
        var billCands = new List<Cand>();
        foreach (var p in live.Where(p => p.Entity.Type == "bill_discount"))
        {
            var minBill = p.Num("minBill");
            if (afterLines < minBill || afterLines <= 0) continue;
            var pct = p.Num("billPercent");
            var off = pct > 0 ? afterLines * Math.Min(pct, 100) / 100 : p.Num("billAmount");
            var maxOff = p.Num("maxDiscount");
            if (maxOff > 0) off = Math.Min(off, maxOff);
            if (off > 0) billCands.Add(new Cand(p, off));
        }
        if (billCands.Count > 0)
        {
            var chosen = new List<Cand>();
            var ex = billCands.Where(c => !c.P.Entity.Stackable).OrderByDescending(c => c.Amount).FirstOrDefault();
            if (ex != null) chosen.Add(ex);
            chosen.AddRange(billCands.Where(c => c.P.Entity.Stackable));
            decimal total = 0;
            foreach (var c in chosen)
            {
                var a = Math.Round(Math.Min(c.Amount, afterLines - total), 0, MidpointRounding.AwayFromZero);
                if (a > 0) total += a;
            }
            res.BillDiscount = total;
        }
        return res;
    }

    /// <summary>
    /// Khuyến mãi tối đa trong ±10 phút quanh giờ server — máy bán lệch giờ vài phút ở mốc
    /// đầu/cuối khung giờ không bị chặn oan.
    /// </summary>
    public static Result ComputeTolerant(IReadOnlyList<object> promotions, IReadOnlyList<Line> lines, bool hasCustomer)
    {
        var nowVn = DateTime.UtcNow.AddHours(7);
        var best = new Result();
        foreach (var shift in new[] { 0, -10, 10 })
        {
            var r = Compute(promotions, lines, nowVn.AddMinutes(shift), hasCustomer);
            foreach (var (k, v) in r.LineDiscount)
                best.LineDiscount[k] = Math.Max(best.LineDiscount.GetValueOrDefault(k), v);
            best.BillDiscount = Math.Max(best.BillDiscount, r.BillDiscount);
        }
        return best;
    }
}
