namespace ZKTecoADMS.Api.Services;

using ZKTecoADMS.Application.Helpers;

internal static class AiAssistantVnTime
{
    public const int OffsetHours = VnTimeHelper.OffsetHours;

    public static DateTime NowVn() => VnTimeHelper.NowVn();

    /// <summary>UTC-stored values → VN.</summary>
    public static DateTime ToVn(DateTime utc) => VnTimeHelper.UtcToVn(utc);

    /// <summary>Chấm công — giờ tường VN trong DB.</summary>
    public static DateTime AttendanceToVn(DateTime punch) => VnTimeHelper.AttendanceWallClock(punch);

    public static (DateTime dateLocal, DateTime utcStart, DateTime utcEnd) DayRange(DateTime? date)
    {
        var (local, start, end) = VnTimeHelper.AttendanceDayRange(date);
        return (local, start, end);
    }
}
