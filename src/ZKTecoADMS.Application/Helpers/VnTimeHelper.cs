namespace ZKTecoADMS.Application.Helpers;

/// <summary>
/// Quy ước múi giờ VN (UTC+7) cho toàn hệ thống.
/// <list type="bullet">
/// <item><see cref="AttendanceWallClock"/> — AttendanceTime / PunchTime từ máy ZKTeco &amp; mobile (giờ tường VN trong DB).</item>
/// <item><see cref="UtcToVn"/> — CreatedAt, audit, giao dịch lưu UTC (Npgsql legacy: Kind=Unspecified, mặt số UTC).</item>
/// </list>
/// </summary>
public static class VnTimeHelper
{
    public const int OffsetHours = 7;

    public static DateTime NowVn() => DateTime.UtcNow.AddHours(OffsetHours);

    /// <summary>UTC → hiển thị / so sánh giờ VN (cột audit, POS, …).</summary>
    public static DateTime UtcToVn(DateTime value) =>
        value.Kind switch
        {
            DateTimeKind.Utc => value.AddHours(OffsetHours),
            DateTimeKind.Local => value.ToUniversalTime().AddHours(OffsetHours),
            _ => value.AddHours(OffsetHours),
        };

    /// <summary>Chấm công — giá trị DB đã là giờ tường VN; chỉ quy đổi nếu Kind=Utc.</summary>
    public static DateTime AttendanceWallClock(DateTime value) =>
        value.Kind == DateTimeKind.Utc ? value.AddHours(OffsetHours) : value;

    public static DateTime AttendanceDate(DateTime value) => AttendanceWallClock(value).Date;

    public static (DateTime startLocal, DateTime endLocal, DateTime queryStart, DateTime queryEndExclusive)
        AttendanceMonthRange(int year, int month)
    {
        var start = new DateTime(year, month, 1);
        var endExclusive = start.AddMonths(1);
        return (start, endExclusive.AddDays(-1), start, endExclusive);
    }

    public static (DateTime fromLocal, DateTime toLocal, DateTime queryStart, DateTime queryEndExclusive)
        AttendanceDateRange(DateTime? from, DateTime? to)
    {
        var now = NowVn().Date;
        var f = (from ?? now.AddDays(-30)).Date;
        var t = (to ?? now).Date;
        if (t < f) t = f;
        return (f, t, f, t.AddDays(1));
    }

    public static (DateTime dateLocal, DateTime queryStart, DateTime queryEndExclusive)
        AttendanceDayRange(DateTime? date)
    {
        var local = (date ?? NowVn()).Date;
        return (local, local, local.AddDays(1));
    }
}
