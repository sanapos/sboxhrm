using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Báo cáo chăm sóc khách theo khoảng ngày (giờ Việt Nam): số lần chăm sóc theo loại / ngày / người ghi,
/// số khách được chăm sóc, lịch hẹn đã giữ đúng hay đã quá hạn. Chỉ tính lần do người ghi
/// (bỏ <see cref="PosQuoteCareBoard.SystemKinds"/>).
/// </summary>
public static class PosQuoteCareLog
{
    static readonly TimeSpan LocalOffset = TimeSpan.FromHours(7);

    /// <summary>Hẹn được coi là giữ đúng nếu có lần chăm sóc mới trong vòng 1 ngày sau giờ hẹn.</summary>
    static readonly TimeSpan FollowUpGrace = TimeSpan.FromDays(1);

    public static readonly string[] Kinds = ["Call", "Meeting", "Note", "FollowUp"];

    public record DayRow(string Date, int Count, int Call, int Meeting, int Note, int FollowUp);

    public record FollowUpStats(int Set, int Done, int Overdue, int Upcoming);

    public record Summary(
        int Total,
        int Quotes,
        int Customers,
        Dictionary<string, int> ByKind,
        double? AverageScore,
        FollowUpStats FollowUps);

    public static DateTime LocalDayStartUtc(DateOnly day) =>
        DateTime.SpecifyKind(day.ToDateTime(TimeOnly.MinValue) - LocalOffset, DateTimeKind.Utc);

    public static DateOnly LocalDay(DateTime utc) => DateOnly.FromDateTime(utc + LocalOffset);

    /// <param name="inRange">Lần chăm sóc ghi trong khoảng [from, to] (đã lọc người / loại).</param>
    /// <param name="later">Mọi lần chăm sóc của các báo giá đó từ đầu khoảng tới nay — xét hẹn đã giữ chưa.</param>
    public static (Summary Summary, List<DayRow> ByDay) Build(
        IReadOnlyList<PosQuoteActivity> inRange,
        IReadOnlyList<PosQuoteActivity> later,
        IReadOnlyDictionary<Guid, PosQuote> quotes,
        DateOnly from,
        DateOnly to,
        DateTime nowUtc)
    {
        var acts = inRange.Where(a => !PosQuoteCareBoard.SystemKinds.Contains(a.Kind)).ToList();
        var byKind = Kinds.ToDictionary(k => k, k => acts.Count(a => a.Kind == k));
        var customers = acts
            .Select(a => quotes.TryGetValue(a.QuoteId, out var q) ? PosQuoteCareBoard.CustomerKey(q) ?? "q:" + q.Id : "q:" + a.QuoteId)
            .Distinct().Count();
        var scores = acts.Select(PosQuoteCareBoard.ScoreOf).Where(s => s != null).Select(s => s!.Value).ToList();

        var byQuote = later.Where(a => !PosQuoteCareBoard.SystemKinds.Contains(a.Kind))
            .GroupBy(a => a.QuoteId)
            .ToDictionary(g => g.Key, g => g.OrderBy(a => a.CreatedAt).ToList());
        int done = 0, overdue = 0, upcoming = 0;
        var withFollowUp = acts.Where(a => a.NextFollowUpAt != null).ToList();
        foreach (var a in withFollowUp)
        {
            var due = a.NextFollowUpAt!.Value;
            var next = byQuote.TryGetValue(a.QuoteId, out var list)
                ? list.FirstOrDefault(x => x.Id != a.Id && x.CreatedAt > a.CreatedAt)
                : null;
            if (next != null && next.CreatedAt <= due + FollowUpGrace) done++;
            else if (due > nowUtc) upcoming++;
            else overdue++;
        }

        var days = new List<DayRow>();
        var byDate = acts.GroupBy(a => LocalDay(a.CreatedAt)).ToDictionary(g => g.Key, g => g.ToList());
        for (var d = from; d <= to; d = d.AddDays(1))
        {
            var l = byDate.GetValueOrDefault(d) ?? [];
            days.Add(new DayRow(d.ToString("yyyy-MM-dd"), l.Count,
                l.Count(a => a.Kind == "Call"), l.Count(a => a.Kind == "Meeting"),
                l.Count(a => a.Kind == "Note"), l.Count(a => a.Kind == "FollowUp")));
        }

        return (new Summary(
            acts.Count,
            acts.Select(a => a.QuoteId).Distinct().Count(),
            customers,
            byKind,
            scores.Count > 0 ? Math.Round(scores.Average(), 1) : null,
            new FollowUpStats(withFollowUp.Count, done, overdue, upcoming)), days);
    }
}
