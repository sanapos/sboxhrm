namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>Dữ liệu để chấm điểm rủi ro một lần chấm công mobile ngoài vị trí.</summary>
public sealed record MobilePunchRiskInput
{
    /// <summary>Khoảng cách tới vị trí khai báo gần nhất (m); null = không có GPS / chưa khai báo vị trí</summary>
    public double? Distance { get; init; }

    /// <summary>Bán kính của vị trí gần nhất (m)</summary>
    public double Radius { get; init; } = 100;

    public double? GpsAccuracy { get; init; }

    /// <summary>Điểm khớp mặt (%); null = không dùng khuôn mặt</summary>
    public double? FaceScore { get; init; }

    public bool LivenessPassed { get; init; } = true;
    public bool HasSitePhoto { get; init; }
    public bool HasReason { get; init; }

    /// <summary>Số lần chấm ngoài vị trí của nhân viên trong tháng (không tính lần này)</summary>
    public int OutsideCountThisMonth { get; init; }

    /// <summary>Lệch so với giờ bắt đầu/kết thúc ca (phút); null = không có lịch</summary>
    public int? MinutesFromShift { get; init; }

    public bool IsTravel { get; init; }
}

public sealed record MobilePunchRisk(int Score, string Level, List<string> Flags)
{
    public bool IsTrusted => Level == MobilePunchRiskScorer.Trusted;
}

/// <summary>
/// Chấm điểm rủi ro 0–100 cho lần chấm ngoài vị trí: khoảng cách, độ chính xác GPS, khuôn mặt,
/// ảnh hiện trường, lệch ca, tần suất. «Tin cậy» còn đòi hỏi ở gần vị trí khai báo.
/// </summary>
public static class MobilePunchRiskScorer
{
    public const string Trusted = "trusted";
    public const string Review = "review";
    public const string High = "high";

    public static MobilePunchRisk Score(MobilePunchRiskInput i, int trustedMaxDistance = 300, double trustedMinFace = 85)
    {
        var score = 0;
        var flags = new List<string>();

        if (i.Distance is not { } d)
        {
            score += 50;
            flags.Add("Không xác định được vị trí GPS");
        }
        else
        {
            var beyond = Math.Max(0, d - i.Radius);
            if (d <= trustedMaxDistance) score += 5;
            else if (beyond <= 1000) { score += 25; flags.Add($"Cách vị trí gần nhất {FormatDistance(d)}"); }
            else if (beyond <= 5000) { score += 40; flags.Add($"Cách vị trí gần nhất {FormatDistance(d)}"); }
            else { score += 55; flags.Add($"Rất xa vị trí khai báo ({FormatDistance(d)})"); }
        }

        if (i.GpsAccuracy is { } acc)
        {
            if (acc > 100) { score += 15; flags.Add($"GPS kém chính xác (±{Math.Round(acc)} m)"); }
            else if (acc > 50) { score += 7; flags.Add($"GPS sai số ±{Math.Round(acc)} m"); }
        }

        if (i.FaceScore is not { } face)
        {
            score += 10;
            flags.Add("Không xác thực khuôn mặt");
        }
        else if (face < trustedMinFace)
        {
            score += 15;
            flags.Add($"Khớp khuôn mặt thấp ({Math.Round(face)}%)");
        }

        if (!i.LivenessPassed) { score += 10; flags.Add("Không qua kiểm tra người thật"); }
        if (!i.HasSitePhoto) score += 5;
        if (!i.HasReason) score += 3;

        if (i.MinutesFromShift is { } m)
        {
            if (m > 90) { score += 15; flags.Add($"Lệch ca {m} phút"); }
            else if (m > 30) { score += 5; flags.Add($"Lệch ca {m} phút"); }
        }

        if (i.OutsideCountThisMonth >= 15) { score += 10; flags.Add($"Chấm ngoài vị trí {i.OutsideCountThisMonth} lần trong tháng"); }
        if (i.IsTravel) flags.Add("Chấm đi đường");

        score = Math.Clamp(score, 0, 100);
        var nearEnough = i.Distance is { } dd && dd <= trustedMaxDistance;
        var level = score <= 20 && nearEnough ? Trusted : score <= 45 ? Review : High;
        return new MobilePunchRisk(score, level, flags);
    }

    /// <summary>Có được tự duyệt không: bật cài đặt, tin cậy, không phải chấm đi đường.</summary>
    public static bool CanAutoApprove(MobilePunchRisk risk, bool autoApproveTrusted, bool isTravel)
        => autoApproveTrusted && risk.IsTrusted && !isTravel;

    public static string FormatDistance(double meters)
        => meters >= 1000 ? $"{meters / 1000:0.#} km".Replace('.', ',') : $"{Math.Round(meters)} m";
}
