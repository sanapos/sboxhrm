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

    /// <summary>Lỗi khi thêm/sửa dòng lịch so với các dòng khác cùng ngày; null nếu hợp lệ.</summary>
    public static string? Validate(IEnumerable<WorkSchedule> othersSameDay, Guid? shiftId, bool isDayOff)
    {
        var others = othersSameDay.ToList();
        if (isDayOff)
        {
            if (others.Any(o => o.IsDayOff)) return "Nhân viên đã có ngày nghỉ trong ngày này";
            if (others.Any(o => !o.IsDayOff && o.ShiftId != null))
                return "Nhân viên đang có ca trong ngày này — hãy gỡ ca trước khi đặt ngày nghỉ";
            return null;
        }
        if (others.Any(o => o.IsDayOff)) return "Nhân viên đang nghỉ trong ngày này — hãy gỡ ngày nghỉ trước khi xếp ca";
        if (others.Any(o => o.ShiftId == shiftId)) return "Nhân viên đã được xếp ca này trong ngày";
        return null;
    }

    public static bool AnyConflict(IEnumerable<WorkSchedule> existing, Guid employeeId, DateTime date, Guid? shiftId, bool isDayOff)
        => existing.Any(e => ConflictsWith(e, employeeId, date, shiftId, isDayOff));
}
