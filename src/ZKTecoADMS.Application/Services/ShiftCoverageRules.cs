namespace ZKTecoADMS.Application.Services;

/// <summary>
/// Định mức nhân sự theo ca: số người thực tế có mặt = đã xếp ca − nghỉ phép đã duyệt;
/// so với tối thiểu / tối đa của định mức (theo thứ trong tuần nếu có).
/// </summary>
public static class ShiftCoverageRules
{
    public const string NoQuota = "none", Short = "short", Tight = "tight", Ok = "ok", Full = "full", Over = "over";

    /// <summary>
    /// Trạng thái định mức: thiếu (&lt; tối thiểu), sát ngưỡng (còn ≤ <paramref name="warningThreshold"/> người
    /// nữa là thiếu — tức hiệu lực ≤ min + ngưỡng khi min &gt; 0), đủ, kín chỗ (= tối đa), vượt (&gt; tối đa).
    /// </summary>
    public static string Status(int effective, int min, int max, int warningThreshold = 0, bool hasQuota = true)
    {
        if (!hasQuota) return NoQuota;
        if (effective < min) return Short;
        if (max > 0 && effective > max) return Over;
        if (max > 0 && effective == max) return Full;
        if (min > 0 && warningThreshold > 0 && effective - min < warningThreshold) return Tight;
        return Ok;
    }

    /// <summary>Số chỗ còn nhận thêm (null = không giới hạn).</summary>
    public static int? Remaining(int effective, int max) => max > 0 ? Math.Max(0, max - effective) : null;

    /// <summary>Số giờ ca (qua nửa đêm nếu giờ kết thúc ≤ giờ bắt đầu), trừ giờ nghỉ.</summary>
    public static double ShiftHours(TimeSpan start, TimeSpan end, int breakMinutes = 0)
    {
        var span = end - start;
        if (span <= TimeSpan.Zero) span += TimeSpan.FromDays(1);
        return Math.Max(0, Math.Round((span.TotalMinutes - Math.Max(0, breakMinutes)) / 60.0, 2));
    }

    /// <summary>Đơn nghỉ có phủ ca này trong ngày này không (không chọn ca cụ thể = nghỉ cả ngày).</summary>
    public static bool LeaveCovers(DateTime leaveStart, DateTime leaveEnd, IReadOnlyCollection<Guid> leaveShiftIds,
        DateTime day, Guid? shiftId) =>
        day.Date >= leaveStart.Date && day.Date <= leaveEnd.Date
        && (leaveShiftIds.Count == 0 || shiftId == null || leaveShiftIds.Contains(shiftId.Value));
}
