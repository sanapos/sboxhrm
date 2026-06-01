using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Helpers;

internal static class WorkScheduleDuplicateHelper
{
    public static bool ConflictsWith(WorkSchedule existing, Guid employeeId, DateTime date, Guid? shiftId, bool isDayOff)
    {
        if (existing.EmployeeUserId != employeeId || existing.Date.Date != date.Date)
            return false;

        if (isDayOff)
            return existing.IsDayOff;

        if (existing.IsDayOff)
            return false;

        return existing.ShiftId == shiftId;
    }

    public static bool AnyConflict(IEnumerable<WorkSchedule> existing, Guid employeeId, DateTime date, Guid? shiftId, bool isDayOff)
        => existing.Any(e => ConflictsWith(e, employeeId, date, shiftId, isDayOff));
}
