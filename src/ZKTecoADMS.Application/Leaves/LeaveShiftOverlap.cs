using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Leaves;

public static class LeaveShiftOverlap
{
    /// <summary>
    /// True when date ranges overlap and shift sets intersect (empty shift list = full-day block).
    /// </summary>
    public static bool ConflictsWith(Leave existing, DateTime startDate, DateTime endDate, IReadOnlyList<Guid> newShiftIds)
    {
        if (existing.Status == LeaveStatus.Rejected) return false;
        if (existing.StartDate > endDate || existing.EndDate < startDate) return false;

        var existingIds = existing.ShiftIds ?? new List<Guid>();
        if (existingIds.Count == 0 || newShiftIds.Count == 0) return true;

        return existingIds.Any(newShiftIds.Contains);
    }
}
