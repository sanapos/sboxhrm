namespace ZKTecoADMS.Application.Helpers;

/// <summary>
/// Khóa món tạm trong ngày KD. Qua ngày KD mới (theo giờ cắt báo cáo) tự hết hiệu lực — không cần job reset.
/// </summary>
public static class PosDailySoldOutHelper
{
    public static DateTime BusinessDate(int reportDayStartHour) =>
        VnTimeHelper.ResolveBusinessDate(VnTimeHelper.NowVn(), reportDayStartHour);

    public static bool IsLockedToday(DateTime? dailySoldOutOn, DateTime businessDate) =>
        dailySoldOutOn.HasValue && dailySoldOutOn.Value.Date == businessDate.Date;
}
