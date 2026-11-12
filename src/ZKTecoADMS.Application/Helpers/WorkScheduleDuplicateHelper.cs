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

    /// <summary>
    /// Hai ca trùng giờ (tính cả ca qua đêm). Ca có giờ vào = giờ ra (ca linh hoạt) không xét trùng.
    /// </summary>
    public static bool Overlaps(ShiftTemplate a, ShiftTemplate b)
    {
        if (a.Id == b.Id) return true;
        if (a.StartTime == a.EndTime || b.StartTime == b.EndTime) return false;
        static (int S, int E) Span(ShiftTemplate t)
        {
            var s = (int)t.StartTime.TotalMinutes;
            var e = (int)t.EndTime.TotalMinutes;
            return (s, e <= s ? e + 1440 : e);
        }
        static bool Hit((int S, int E) x, (int S, int E) y) => x.S < y.E && y.S < x.E;
        var (sa, ea) = Span(a);
        var (sb, eb) = Span(b);
        return Hit((sa, ea), (sb, eb)) || Hit((sa + 1440, ea + 1440), (sb, eb)) || Hit((sa, ea), (sb + 1440, eb + 1440));
    }

    /// <summary>
    /// Lỗi khi thêm [shift] vào ngày đã có các ca [otherShiftIds] mà trùng giờ; null nếu không trùng.
    /// Một người làm nhiều ca trong ngày được, nhưng các ca không được chồng giờ — muốn thay ca thì «Đổi ca».
    /// </summary>
    public static string? OverlapError(
        IEnumerable<Guid?> otherShiftIds, ShiftTemplate shift, IReadOnlyDictionary<Guid, ShiftTemplate> templates)
    {
        foreach (var id in otherShiftIds)
        {
            if (id is not Guid g || g == shift.Id || !templates.TryGetValue(g, out var other)) continue;
            if (Overlaps(other, shift))
                return $"{shift.Name} trùng giờ với {other.Name} đã xếp trong ngày — muốn thay ca thì chọn «Đổi sang ca này»";
        }
        return null;
    }

    public static bool AnyConflict(IEnumerable<WorkSchedule> existing, Guid employeeId, DateTime date, Guid? shiftId, bool isDayOff)
        => existing.Any(e => ConflictsWith(e, employeeId, date, shiftId, isDayOff));
}
