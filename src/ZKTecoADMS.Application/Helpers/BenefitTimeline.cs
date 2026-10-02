using System.Linq.Expressions;

namespace ZKTecoADMS.Application.Helpers;

/// <summary>
/// Lịch sử hồ sơ lương của nhân viên: mỗi phiên bản (EmployeeBenefit) áp dụng từ EffectiveDate đến EndDate.
/// Các phiên bản không chồng nhau; phiên bản mới nhất có EndDate = null.
/// Phiên bản đầu tiên của nhân viên coi như áp dụng từ trước (dữ liệu cũ gán giữa tháng vẫn tính cả tháng).
/// </summary>
public static class BenefitTimeline
{
    /// <summary>Hôm nay theo giờ Việt Nam.</summary>
    public static DateTime VnToday() => DateTime.UtcNow.AddHours(7).Date;

    /// <summary>Phiên bản áp dụng trong ngày <paramref name="day"/> (so theo ngày, bỏ giờ).</summary>
    public static Expression<Func<EmployeeBenefit, bool>> CoversDay(DateTime day)
    {
        var start = day.Date;
        var next = start.AddDays(1);
        return eb => eb.EffectiveDate < next && (eb.EndDate == null || eb.EndDate >= start);
    }

    /// <summary>Phiên bản có hiệu lực ít nhất một ngày trong [from, to].</summary>
    public static Expression<Func<EmployeeBenefit, bool>> Overlaps(DateTime from, DateTime to)
    {
        var start = from.Date;
        var next = to.Date.AddDays(1);
        return eb => eb.EffectiveDate < next && (eb.EndDate == null || eb.EndDate >= start);
    }

    /// <summary>Thời điểm kết thúc phiên bản trước khi phiên bản mới bắt đầu (cuối ngày hôm trước).</summary>
    public static DateTime EndBefore(DateTime effectiveDate) => effectiveDate.Date.AddTicks(-1);

    /// <summary>Kế hoạch áp phiên bản mới từ <paramref name="effectiveDate"/>.</summary>
    public sealed record Plan(
        /// <summary>Phiên bản bắt đầu từ ngày đó trở đi — bị thay thế (xóa).</summary>
        IReadOnlyList<EmployeeBenefit> Replaced,
        /// <summary>Phiên bản đang chạy qua ngày đó — kết thúc ở cuối ngày hôm trước.</summary>
        IReadOnlyList<EmployeeBenefit> Ended,
        /// <summary>Phiên bản liền trước (để chuyển quỹ phép).</summary>
        EmployeeBenefit? Previous);

    public static Plan PlanNewVersion(IEnumerable<EmployeeBenefit> existing, DateTime effectiveDate)
    {
        var day = effectiveDate.Date;
        var list = existing.OrderBy(e => e.EffectiveDate).ToList();
        var replaced = list.Where(e => e.EffectiveDate.Date >= day).ToList();
        var ended = list.Where(e => e.EffectiveDate.Date < day && (e.EndDate == null || e.EndDate.Value >= day)).ToList();
        var previous = list.Where(e => e.EffectiveDate.Date < day).OrderByDescending(e => e.EffectiveDate).FirstOrDefault();
        return new Plan(replaced, ended, previous);
    }

    /// <summary>Một đoạn hồ sơ lương trong kỳ (đã cắt theo kỳ).</summary>
    public sealed record Segment(EmployeeBenefit Version, DateTime From, DateTime To);

    /// <summary>
    /// Cắt lịch sử thành các đoạn trong [from, to]. Phiên bản sớm nhất được kéo về đầu kỳ
    /// (dữ liệu cũ không có lịch sử trước ngày gán).
    /// </summary>
    public static List<Segment> Segments(IEnumerable<EmployeeBenefit> versions, DateTime from, DateTime to)
    {
        var start = from.Date;
        var end = to.Date;
        var all = versions.OrderBy(v => v.EffectiveDate).ToList();
        var first = all.FirstOrDefault();
        var outList = new List<Segment>();
        for (var i = 0; i < all.Count; i++)
        {
            var v = all[i];
            var vFrom = v == first ? DateTime.MinValue : v.EffectiveDate.Date;
            var vTo = v.EndDate?.Date ?? DateTime.MaxValue.Date;
            // Dữ liệu cũ: bản trước kết thúc đúng ngày bản sau bắt đầu → ngày đó thuộc bản sau.
            if (i + 1 < all.Count && all[i + 1].EffectiveDate.Date <= vTo)
                vTo = all[i + 1].EffectiveDate.Date.AddDays(-1);
            var s = vFrom > start ? vFrom : start;
            var e = vTo < end ? vTo : end;
            if (s > e) continue;
            outList.Add(new Segment(v, s, e));
        }
        return outList;
    }

    /// <summary>Phiên bản áp dụng vào ngày <paramref name="day"/> (bản đầu tiên tính từ trước). Null = chưa thiết lập.</summary>
    public static EmployeeBenefit? PickCurrent(IEnumerable<EmployeeBenefit> versions, DateTime day) =>
        Segments(versions, day, day).LastOrDefault()?.Version;

    /// <summary>Phiên bản đã lên lịch nhưng chưa tới ngày áp dụng.</summary>
    public static EmployeeBenefit? PickUpcoming(IEnumerable<EmployeeBenefit> versions, DateTime day) =>
        versions.Where(v => v.EffectiveDate.Date > day.Date).OrderBy(v => v.EffectiveDate).FirstOrDefault();
}
