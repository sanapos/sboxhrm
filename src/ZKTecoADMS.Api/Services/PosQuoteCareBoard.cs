using System.Text.RegularExpressions;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Bảng theo dõi chăm sóc khách tiềm năng từ báo giá: điểm tiềm năng thang 10 (nóng 8–10, ấm 5–7,
/// lạnh 0–4), xu hướng so với lần chấm trước, lịch hẹn quá hạn / hôm nay, khách lâu chưa liên hệ.
/// </summary>
public static class PosQuoteCareBoard
{
    /// <summary>Quá số ngày này không liên hệ → "bỏ quên".</summary>
    public const int StaleDays = 7;

    /// <summary>Giờ Việt Nam cho mốc "hôm nay" của lịch hẹn.</summary>
    static readonly TimeSpan LocalOffset = TimeSpan.FromHours(7);

    /// <summary>Hoạt động do hệ thống ghi (tạo / sửa / đổi trạng thái) — không tính là chăm sóc khách.</summary>
    static readonly HashSet<string> SystemKinds = new(StringComparer.OrdinalIgnoreCase) { "Created", "Edit", "Status" };

    public record ScorePoint(int Score, DateTime At);

    public record CareItem(
        Guid QuoteId,
        string QuoteNo,
        string? CustomerName,
        string? CustomerPhone,
        decimal Total,
        string Status,
        int? Score,
        int? PreviousScore,
        int Trend,
        string Band,
        DateTime? LastContactAt,
        string? LastContactKind,
        string? LastContent,
        int? DaysSinceContact,
        bool Stale,
        DateTime? NextFollowUpAt,
        string FollowUp,
        int ContactCount,
        Guid? OwnerEmployeeId,
        string? OwnerName,
        IReadOnlyList<ScorePoint> ScoreHistory);

    public record CareSummary(
        int Total,
        int Hot,
        int Warm,
        int Cold,
        int Unscored,
        int Overdue,
        int DueToday,
        int Stale,
        double? AverageScore,
        decimal PipelineValue,
        decimal WeightedValue);

    public static string BandOf(int? score) => score switch
    {
        null => "none",
        >= 8 => "hot",
        >= 5 => "warm",
        _ => "cold",
    };

    public static (CareSummary Summary, List<CareItem> Items) Build(
        IReadOnlyList<PosQuote> quotes,
        IReadOnlyList<PosQuoteActivity> activities,
        IReadOnlyDictionary<Guid, string> employeeNames,
        DateTime nowUtc)
    {
        var byQuote = activities.Where(a => a.Deleted == null)
            .GroupBy(a => a.QuoteId)
            .ToDictionary(g => g.Key, g => g.OrderBy(a => a.CreatedAt).ToList());
        var today = (nowUtc + LocalOffset).Date;

        var items = new List<CareItem>(quotes.Count);
        foreach (var q in quotes)
        {
            var acts = byQuote.GetValueOrDefault(q.Id) ?? [];
            var history = acts
                .Select(a => (Score: ScoreOf(a), a.CreatedAt))
                .Where(x => x.Score != null)
                .Select(x => new ScorePoint(x.Score!.Value, x.CreatedAt))
                .ToList();
            int? score = history.Count > 0 ? history[^1].Score : q.PotentialScore is >= 0 and <= 10 ? q.PotentialScore : null;
            int? previous = history.Count > 1 ? history[^2].Score : null;
            var trend = score is int s && previous is int p ? Math.Sign(s - p) : 0;

            var contacts = acts.Where(a => !SystemKinds.Contains(a.Kind)).ToList();
            var last = contacts.LastOrDefault();
            // Lịch hẹn: lấy theo lần ghi gần nhất có hẹn; ghi chăm sóc sau hẹn đó mà không hẹn tiếp
            // → coi như đã xử lý (không còn quá hạn).
            var lastWithFollowUp = contacts.LastOrDefault(a => a.NextFollowUpAt != null);
            DateTime? next = lastWithFollowUp != null && ReferenceEquals(lastWithFollowUp, last)
                ? lastWithFollowUp.NextFollowUpAt
                : null;
            var followUp = next is DateTime n ? FollowUpState(n, today) : "none";

            var since = last?.CreatedAt ?? q.CreatedAt;
            var days = (int)Math.Floor((nowUtc - since).TotalDays);
            var stale = days > StaleDays && followUp is not ("upcoming" or "today");

            items.Add(new CareItem(
                q.Id,
                q.QuoteNo,
                q.CustomerName,
                q.CustomerPhone,
                q.Total,
                q.Status.ToString(),
                score,
                previous,
                trend,
                BandOf(score),
                last?.CreatedAt,
                last?.Kind,
                last == null ? null : StripScoreTag(last.Content),
                last == null ? null : Math.Max(0, days),
                stale,
                next,
                followUp,
                contacts.Count,
                q.QuotedByEmployeeId,
                q.QuotedByEmployeeId is Guid eid ? employeeNames.GetValueOrDefault(eid) : q.QuotedBy,
                history.TakeLast(10).ToList()));
        }

        items = items
            .OrderBy(i => i.FollowUp switch { "overdue" => 0, "today" => 1, _ => 2 })
            .ThenByDescending(i => i.Score ?? -1)
            .ThenByDescending(i => i.Stale)
            .ThenByDescending(i => i.Total)
            .ToList();

        var scored = items.Where(i => i.Score != null).ToList();
        var summary = new CareSummary(
            items.Count,
            items.Count(i => i.Band == "hot"),
            items.Count(i => i.Band == "warm"),
            items.Count(i => i.Band == "cold"),
            items.Count(i => i.Band == "none"),
            items.Count(i => i.FollowUp == "overdue"),
            items.Count(i => i.FollowUp == "today"),
            items.Count(i => i.Stale),
            scored.Count > 0 ? Math.Round(scored.Average(i => i.Score!.Value), 1) : null,
            items.Sum(i => i.Total),
            // Doanh thu kỳ vọng = giá trị × điểm/10 (khách chưa chấm điểm không tính).
            Math.Round(scored.Sum(i => i.Total * i.Score!.Value / 10m), 0));
        return (summary, items);
    }

    static string FollowUpState(DateTime nextUtc, DateTime todayLocal)
    {
        var day = (DateTime.SpecifyKind(nextUtc, DateTimeKind.Utc) + LocalOffset).Date;
        if (day < todayLocal) return "overdue";
        return day == todayLocal ? "today" : "upcoming";
    }

    static readonly Regex ScoreTag = new(@"^\[\[TN:(\d{1,2})\]\]\s*", RegexOptions.Compiled);

    /// <summary>Điểm của một lần ghi: cột PotentialScore, hoặc tiền tố [[TN:n]] (dữ liệu cũ).</summary>
    public static int? ScoreOf(PosQuoteActivity a)
    {
        if (a.PotentialScore is int n && n is >= 0 and <= 10) return n;
        var m = ScoreTag.Match(a.Content ?? "");
        return m.Success && int.TryParse(m.Groups[1].Value, out var v) && v is >= 0 and <= 10 ? v : null;
    }

    static string StripScoreTag(string? content)
    {
        var s = ScoreTag.Replace(content ?? "", "").Trim();
        return s.Length > 160 ? s[..160] + "…" : s;
    }
}
