using System.Text.Json;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Services.Kpi;

/// <summary>Kết quả lương KPI của 1 chỉ tiêu (doanh thu / point) của 1 nhân viên.</summary>
public sealed record KpiTargetPay(
    decimal CompletionPct,
    decimal BasePay,     // đạt ≥100% = lương hoàn thành; chưa đạt = lương hoàn thành × % đạt
    decimal Adjustment,  // thưởng vượt (≥100%) hoặc thưởng / phạt theo mốc (<100%); âm = phạt
    decimal Total);      // tổng lương KPI của chỉ tiêu (không âm)

/// <summary>
/// MỘT công thức lương KPI duy nhất cho: tab Lương KPI, bảng lương tháng, báo cáo KPI.
/// Trước đây bảng lương tự tính lại trên app với công thức khác (chưa đạt 100% = 0đ,
/// mốc phạt «%» bị hiểu thành số tiền, chỉ lấy 1 chỉ tiêu / NV) → lệch với tab Lương KPI.
/// </summary>
public static class KpiPayCalculator
{
    static readonly JsonSerializerOptions JsonOpts = new() { PropertyNameCaseInsensitive = true };

    /// <summary>
    /// Chưa đạt 100%: lương = Lương hoàn thành × % đạt, cộng/trừ theo mốc phạt/thưởng (PenaltyTiersJson).
    /// Đạt ≥ 100%: lương = Lương hoàn thành + thưởng vượt theo các mốc (BonusTiersJson).
    /// Chưa nhập thực tế → 0.
    /// </summary>
    public static KpiTargetPay Compute(KpiEmployeeTarget t)
    {
        if (!t.ActualValue.HasValue || t.TargetValue == 0)
            return new KpiTargetPay(0, 0, 0, 0);

        var pct = t.ActualValue.Value / t.TargetValue * 100m;
        decimal basePay, adjustment;
        if (pct < 100m)
        {
            basePay = Math.Round(t.CompletionSalary * pct / 100m, 0);
            adjustment = PenaltyOrBonus(t, pct);
        }
        else
        {
            basePay = t.CompletionSalary;
            adjustment = Math.Max(0, OverTargetBonus(t));
        }
        var total = Math.Max(0, basePay + adjustment);
        return new KpiTargetPay(Math.Round(pct, 2), basePay, adjustment, total);
    }

    /// <summary>Thưởng vượt chỉ tiêu theo mốc (không gồm lương hoàn thành).</summary>
    public static decimal OverTargetBonus(KpiEmployeeTarget t)
    {
        if (!t.ActualValue.HasValue || t.TargetValue == 0) return 0;
        var act = t.ActualValue.Value;
        var tgt = t.TargetValue;
        if (act / tgt * 100m < 100m) return 0;
        var tiers = Parse(t.BonusTiersJson);
        decimal bonus = 0;
        foreach (var band in tiers)
        {
            var fromVal = tgt * (decimal)band.FromPct / 100m;
            var toVal = band.ToPct < 0 ? act : tgt * (decimal)band.ToPct / 100m;
            if (act <= fromVal) continue;
            switch (band.RateType)
            {
                case 2: // số tiền cố định khi vượt mốc
                    bonus += band.Rate;
                    break;
                case 3: // % lương hoàn thành
                    bonus += Math.Round(t.CompletionSalary * band.Rate / 100m, 0);
                    break;
                default:
                {
                    var inBand = Math.Min(act, toVal) - fromVal;
                    if (inBand <= 0) continue;
                    bonus += band.RateType == 1
                        ? inBand * band.Rate / 100m // % phần giá trị vượt
                        : inBand * band.Rate;        // đồng / đơn vị vượt
                    break;
                }
            }
        }
        return Math.Round(bonus, 0);
    }

    /// <summary>
    /// Mốc phạt / thưởng khi chưa đạt 100%: RateType 1 = % lương hoàn thành, còn lại = số tiền.
    /// Rate &lt; 0 là phạt.
    /// </summary>
    public static decimal PenaltyOrBonus(KpiEmployeeTarget t, decimal pct)
    {
        foreach (var band in Parse(t.PenaltyTiersJson))
        {
            var fromPct = (decimal)band.FromPct;
            var toPct = band.ToPct < 0 ? 100m : (decimal)band.ToPct;
            if (pct >= fromPct && pct < toPct)
                return band.RateType == 1
                    ? Math.Round(t.CompletionSalary * band.Rate / 100m, 0)
                    : band.Rate;
        }
        return 0;
    }

    /// <summary>
    /// Tỷ lệ thưởng theo tổng điểm KPI: lấy mốc có «điểm tối thiểu» lớn nhất ≤ điểm
    /// (không bị hụt ở khoảng lẻ như 89.5 nằm giữa 80–89 và 90–100). Dưới mốc thấp nhất → 0.
    /// </summary>
    public static decimal BonusRateForScore(IEnumerable<KpiBonusRule> rules, decimal score) =>
        rules.Where(r => r.MinScore <= score)
            .OrderByDescending(r => r.MinScore)
            .Select(r => r.BonusRate)
            .FirstOrDefault();

    static List<BandTier> Parse(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return [];
        try
        {
            return JsonSerializer.Deserialize<List<BandTier>>(json, JsonOpts) ?? [];
        }
        catch
        {
            return [];
        }
    }
}
