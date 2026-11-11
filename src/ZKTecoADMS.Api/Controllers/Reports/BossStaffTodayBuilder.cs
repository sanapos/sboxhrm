using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers.Reports;

/// <summary>
/// «Nhân viên hôm nay» của SBOX BOSS (màn Nhân viên hôm nay + ô «Đã chấm công» ở Tổng quan): giờ chấm đầu / cuối,
/// ca, đi trễ, nghỉ phép. Đi trễ CHỈ theo ca gán trong thiết lập lương («shifts:» của mẫu lương, mức lương ca) —
/// giống bảng công, báo cáo Đi trễ / Về sớm, phạt và Tổng quan HRM; quá ân hạn thì tính đủ phút từ giờ vào ca.
/// Lịch xếp ca chỉ dùng để biết hôm nay ai nghỉ / ai phải đi làm. Trước đây trễ tính theo lịch xếp ca và trừ ân hạn.
/// </summary>
public static class BossStaffTodayBuilder
{
    public sealed record Row(
        Guid Id, string? Code, string Name,
        DateTime? FirstPunch, DateTime? LastPunch,
        bool HasShift, bool DayOff, string? ShiftName, string? ShiftStart, string? ShiftEnd,
        int LateMinutes, bool OnLeave, bool LeaveHalf, string? LeaveType);

    public sealed record Result(bool HasSchedules, IReadOnlyList<Row> Staff);

    static bool IsOvertime(string? shiftType)
    {
        var t = (shiftType ?? string.Empty).Trim().ToLowerInvariant();
        return t.Contains("tăng ca") || t.Contains("tang ca") || t.Contains("overtime");
    }

    static string? Hm(TimeSpan? t) => t is TimeSpan v ? $"{v.Hours:00}:{v.Minutes:00}" : null;

    public static async Task<Result> BuildAsync(
        ZKTecoDbContext db, Guid storeId, IQueryable<Employee> employees, CancellationToken ct)
    {
        var staff = await employees
            .OrderBy(e => e.FirstName)
            .Select(e => new { e.Id, e.EmployeeCode, e.LastName, e.FirstName })
            .ToListAsync(ct);
        var ids = staff.Select(e => e.Id).ToList();
        var today = VnTimeHelper.NowVn().Date;

        // Attendance.EmployeeId là khóa DeviceUser — nối qua DeviceUser mới ra nhân viên.
        var punches = await db.AttendanceLogs.AsNoTracking()
            .Where(a => a.AttendanceTime >= today && a.AttendanceTime < today.AddDays(1) && a.EmployeeId != null)
            .Join(db.DeviceUsers, a => a.EmployeeId, du => (Guid?)du.Id, (a, du) => new { du.EmployeeId, a.AttendanceTime })
            .Where(p => p.EmployeeId != null && ids.Contains(p.EmployeeId.Value))
            .GroupBy(p => p.EmployeeId!.Value)
            .Select(g => new { Id = g.Key, First = g.Min(p => p.AttendanceTime), Last = g.Max(p => p.AttendanceTime) })
            .ToListAsync(ct);
        var byEmployee = punches.ToDictionary(p => p.Id);

        // Lịch hôm nay: chỉ để biết ai nghỉ / ai phải làm (và giờ ca hiển thị khi chưa chấm).
        var schedules = await db.WorkSchedules.AsNoTracking()
            .Where(w => ids.Contains(w.EmployeeUserId) && w.Date >= today && w.Date < today.AddDays(1) && w.Deleted == null)
            .Select(w => new
            {
                w.EmployeeUserId, w.IsDayOff,
                Start = w.StartTime ?? (w.Shift != null ? w.Shift.StartTime : (TimeSpan?)null),
                End = w.EndTime ?? (w.Shift != null ? w.Shift.EndTime : (TimeSpan?)null),
                ShiftName = w.Shift != null ? w.Shift.Name : null,
            })
            .ToListAsync(ct);
        var scheduleByEmployee = schedules
            .GroupBy(w => w.EmployeeUserId)
            .ToDictionary(g => g.Key, g => g.OrderBy(w => w.IsDayOff).ThenBy(w => w.Start ?? TimeSpan.MaxValue).First());

        // Ca trong thiết lập lương + ngày nghỉ tuần của mẫu lương.
        var resolver = await ShiftAssignmentResolver.LoadAsync(db, storeId, ids, ct);
        var benefits = await db.EmployeeBenefits.AsNoTracking()
            .Where(eb => ids.Contains(eb.EmployeeId) && eb.EffectiveDate <= today.AddDays(1))
            .Select(eb => new { eb.EmployeeId, eb.EffectiveDate, eb.Benefit!.WeeklyOffDays, eb.Benefit.PaidLeaveType })
            .ToListAsync(ct);
        var weeklyOffByEmployee = benefits
            .GroupBy(b => b.EmployeeId)
            .ToDictionary(g => g.Key, g =>
            {
                var cur = g.OrderByDescending(x => x.EffectiveDate).First();
                return DashboardController.ParseWeeklyOff(cur.WeeklyOffDays, cur.PaidLeaveType);
            });

        // Nghỉ phép đã duyệt hôm nay (đơn gắn NV qua EmployeeId hoặc tài khoản).
        var userIds = await db.Employees.AsNoTracking()
            .Where(e => ids.Contains(e.Id) && e.ApplicationUserId != null)
            .Select(e => new { e.Id, UserId = e.ApplicationUserId!.Value })
            .ToListAsync(ct);
        var employeeByUser = userIds.GroupBy(x => x.UserId).ToDictionary(g => g.Key, g => g.First().Id);
        var userKeys = employeeByUser.Keys.ToList();
        var leaves = await db.Leaves.AsNoTracking()
            .Where(l => l.Status == LeaveStatus.Approved && l.StartDate < today.AddDays(1) && l.EndDate >= today
                && ((l.EmployeeId != null && ids.Contains(l.EmployeeId.Value)) || userKeys.Contains(l.EmployeeUserId)))
            .Select(l => new { l.EmployeeId, l.EmployeeUserId, l.Type, l.IsHalfShift })
            .ToListAsync(ct);
        var leaveByEmployee = new Dictionary<Guid, (LeaveType Type, bool Half)>();
        foreach (var l in leaves)
        {
            var empId = l.EmployeeId ?? (employeeByUser.TryGetValue(l.EmployeeUserId, out var e) ? e : (Guid?)null);
            if (empId is Guid id) leaveByEmployee.TryAdd(id, (l.Type, l.IsHalfShift));
        }

        var anyAssigned = false;
        var rows = new List<Row>(staff.Count);
        foreach (var e in staff)
        {
            byEmployee.TryGetValue(e.Id, out var p);
            scheduleByEmployee.TryGetValue(e.Id, out var w);
            var hasLeave = leaveByEmployee.TryGetValue(e.Id, out var lv);
            var assigned = resolver.AssignedFor(e.Id).Where(c => !IsOvertime(c.ShiftType)).ToList();
            if (assigned.Count > 0) anyAssigned = true;

            bool dayOff, hasShift;
            if (w != null)
            {
                dayOff = w.IsDayOff;
                hasShift = !w.IsDayOff;
            }
            else
            {
                var off = weeklyOffByEmployee.TryGetValue(e.Id, out var wo) && wo.Contains(today.DayOfWeek);
                dayOff = off && assigned.Count > 0;
                hasShift = assigned.Count > 0 && !off;
            }

            string? shiftName = null, shiftStart = null, shiftEnd = null;
            var late = 0;
            if (p != null && assigned.Count > 0)
            {
                var fit = ShiftMatchHelper.FindBestForCheckIn(assigned, VnTimeHelper.AttendanceWallClock(p.First).TimeOfDay);
                if (fit != null)
                {
                    late = fit.EffectiveLateIn;
                    shiftName = fit.Shift.Name;
                    shiftStart = Hm(fit.Shift.StartTime);
                    shiftEnd = Hm(fit.Shift.EndTime);
                    hasShift = true;
                }
            }
            if (shiftStart == null && hasShift)
            {
                if (w is { IsDayOff: false })
                {
                    shiftName = w.ShiftName;
                    shiftStart = Hm(w.Start);
                    shiftEnd = Hm(w.End);
                }
                else if (assigned.OrderBy(c => c.StartTime).FirstOrDefault() is { } first)
                {
                    shiftName = first.Name;
                    shiftStart = Hm(first.StartTime);
                    shiftEnd = Hm(first.EndTime);
                }
            }

            var name = $"{e.LastName} {e.FirstName}".Trim();
            rows.Add(new Row(
                e.Id, e.EmployeeCode, string.IsNullOrEmpty(name) ? (e.EmployeeCode ?? "Nhân viên") : name,
                p?.First, p?.Last, hasShift, dayOff, shiftName, shiftStart, shiftEnd, late,
                hasLeave, hasLeave && lv.Half, hasLeave ? lv.Type.ToString() : null));
        }

        return new Result(schedules.Count > 0 || anyAssigned, rows);
    }
}
