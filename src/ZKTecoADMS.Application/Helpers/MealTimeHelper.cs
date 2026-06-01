namespace ZKTecoADMS.Application.Helpers;

/// <summary>So sánh khung giờ trong ngày (hỗ trợ ca qua đêm).</summary>
public static class MealTimeHelper
{
    public static bool TimeRangesOverlap(TimeSpan startA, TimeSpan endA, TimeSpan startB, TimeSpan endB)
    {
        if (endA < startA)
            return startB < endA || endB > startA || TimeRangesOverlap(startA, TimeSpan.FromHours(24), startB, endB);
        if (endB < startB)
            return startA < endB || endA > startB || TimeRangesOverlap(startA, endA, startB, TimeSpan.FromHours(24));
        return startA <= endB && endA >= startB;
    }
}
