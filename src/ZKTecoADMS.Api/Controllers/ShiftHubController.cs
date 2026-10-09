using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Application.Queries.Leaves.GetPendingLeaves;
using ZKTecoADMS.Application.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Trung tâm ca làm việc: gom lịch làm việc, đăng ký ca, nghỉ phép, đổi ca và định mức nhân sự vào
/// một chỗ — bảng xếp ca tuần cho quản lý (kèm độ phủ định mức), lịch của tôi cho nhân viên, số việc chờ duyệt.
/// Duyệt / tạo vẫn dùng các endpoint nghiệp vụ sẵn có (giữ nguyên chuỗi duyệt, phạm vi, thông báo).
/// </summary>
[ApiController]
[Route("api/shift-hub")]
[Authorize]
public class ShiftHubController(ZKTecoDbContext db, IMediator mediator, IDataScopeService dataScope)
    : AuthenticatedControllerBase
{
    static DateTime VnToday => DateTime.UtcNow.AddHours(7).Date;

    sealed record Tpl(Guid Id, string Name, string? Code, TimeSpan Start, TimeSpan End, int Break, bool Active);

    async Task<List<Tpl>> TemplatesAsync(Guid storeId, CancellationToken ct) =>
        (await db.ShiftTemplates.AsNoTracking()
            .Where(t => t.StoreId == storeId)
            .OrderBy(t => t.StartTime)
            .Select(t => new { t.Id, t.Name, t.Code, t.StartTime, t.EndTime, t.BreakTimeMinutes, t.IsActive })
            .ToListAsync(ct))
        .Select(t => new Tpl(t.Id, t.Name, t.Code, t.StartTime, t.EndTime, t.BreakTimeMinutes, t.IsActive))
        .ToList();

    static object TplDto(Tpl t, int index) => new
    {
        id = t.Id,
        name = t.Name,
        code = t.Code,
        start = t.Start.ToString(@"hh\:mm"),
        end = t.End.ToString(@"hh\:mm"),
        hours = ShiftCoverageRules.ShiftHours(t.Start, t.End, t.Break),
        overnight = t.End <= t.Start,
        colorIndex = index,
        active = t.Active,
    };

    static (DateTime from, DateTime to) Range(DateTime? from, DateTime? to)
    {
        var f = (from ?? VnToday.AddDays(-(((int)VnToday.DayOfWeek + 6) % 7))).Date; // mặc định: thứ Hai tuần này
        var t = (to ?? f.AddDays(6)).Date;
        if (t < f) (f, t) = (t, f);
        if ((t - f).TotalDays > 41) t = f.AddDays(41); // tối đa 6 tuần / lần
        return (f, t);
    }

    static string Key(DateTime d) => d.ToString("yyyy-MM-dd");

    // ═════════════ ĐỘ PHỦ ĐỊNH MỨC ═════════════

    sealed record Cov(DateTime Date, Guid ShiftId, int Scheduled, int OnLeave, int Pending, int Min, int Max, int Warn, bool HasQuota)
    {
        public int Effective => Scheduled - OnLeave;
    }

    async Task<List<Cov>> CoverageAsync(Guid storeId, DateTime from, DateTime to, List<Tpl> templates, string? department,
        CancellationToken ct)
    {
        var toEx = to.AddDays(1);
        var quotas = await db.ShiftStaffingQuotas.AsNoTracking()
            .Where(q => q.StoreId == storeId && q.Deleted == null)
            .ToListAsync(ct);
        var schedules = await db.WorkSchedules.AsNoTracking()
            .Where(w => w.StoreId == storeId && w.Deleted == null && !w.IsDayOff && w.ShiftId != null
                        && w.Date >= from && w.Date < toEx)
            .Select(w => new { w.Date, ShiftId = w.ShiftId!.Value, w.EmployeeUserId, w.Employee.Department, w.Employee.ApplicationUserId })
            .ToListAsync(ct);
        var pendings = await db.ScheduleRegistrations.AsNoTracking()
            .Where(r => r.StoreId == storeId && r.Deleted == null && r.Status == ScheduleRegistrationStatus.Pending
                        && !r.IsDayOff && r.ShiftId != null && r.Date >= from && r.Date < toEx)
            .Select(r => new { r.Date, ShiftId = r.ShiftId!.Value, r.Employee.Department })
            .ToListAsync(ct);
        var leaves = await db.Leaves.AsNoTracking()
            .Where(l => l.StoreId == storeId && l.Deleted == null && l.Status == LeaveStatus.Approved
                        && l.StartDate < toEx && l.EndDate >= from)
            .Select(l => new { l.EmployeeUserId, l.StartDate, l.EndDate, l.ShiftIds })
            .ToListAsync(ct);

        bool InDept(string? d) => string.IsNullOrWhiteSpace(department)
                                  || string.Equals(d, department, StringComparison.OrdinalIgnoreCase);

        var result = new List<Cov>();
        for (var day = from; day <= to; day = day.AddDays(1))
        {
            foreach (var t in templates.Where(t => t.Active))
            {
                var quota = StaffingQuotaResolver.PickQuotaForDepartment(
                    quotas.Where(q => q.ShiftTemplateId == t.Id).ToList(), department);
                // Định mức theo bộ phận chỉ đếm người thuộc bộ phận đó
                var scopeDept = quota?.Department ?? department;
                bool InScope(string? d) => string.IsNullOrWhiteSpace(scopeDept)
                                           || string.Equals(d, scopeDept, StringComparison.OrdinalIgnoreCase);
                var sch = schedules.Where(s => s.Date.Date == day && s.ShiftId == t.Id && InScope(s.Department) && InDept(s.Department)).ToList();
                var onLeave = sch.Count(s => s.ApplicationUserId.HasValue && leaves.Any(l =>
                    l.EmployeeUserId == s.ApplicationUserId.Value
                    && ShiftCoverageRules.LeaveCovers(l.StartDate, l.EndDate, l.ShiftIds, day, t.Id)));
                var pend = pendings.Count(p => p.Date.Date == day && p.ShiftId == t.Id && InScope(p.Department) && InDept(p.Department));
                var (min, max) = quota == null ? (0, 0) : StaffingQuotaResolver.ResolveLimitsForDate(quota, day);
                result.Add(new Cov(day, t.Id, sch.Count, onLeave, pend, min, max, quota?.WarningThreshold ?? 0, quota != null));
            }
        }
        return result;
    }

    static object CovDto(Cov c) => new
    {
        date = Key(c.Date),
        shiftId = c.ShiftId,
        scheduled = c.Scheduled,
        onLeave = c.OnLeave,
        effective = c.Effective,
        pending = c.Pending,
        min = c.Min,
        max = c.Max,
        hasQuota = c.HasQuota,
        remaining = c.HasQuota ? ShiftCoverageRules.Remaining(c.Effective, c.Max) : null,
        status = ShiftCoverageRules.Status(c.Effective, c.Min, c.Max, c.Warn, c.HasQuota),
    };

    // ═════════════ BẢNG XẾP CA (QUẢN LÝ) ═════════════

    /// <summary>
    /// Bảng xếp ca theo tuần: mỗi nhân viên × ngày (ca đã xếp / nghỉ / đăng ký chờ duyệt / nghỉ phép / đổi ca chờ),
    /// độ phủ định mức từng ca × ngày, tổng giờ công dự kiến.
    /// </summary>
    [HttpGet("board")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("WorkSchedule", ModulePermissionAction.View)]
    public async Task<IActionResult> GetBoard([FromQuery] DateTime? from, [FromQuery] DateTime? to,
        [FromQuery] string? department, [FromQuery] string? search, CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var (f, t) = Range(from, to);
        var toEx = t.AddDays(1);
        var templates = await TemplatesAsync(storeId, ct);

        var empQ = db.Employees.AsNoTracking()
            .Where(e => e.StoreId == storeId && e.Deleted == null && e.WorkStatus == EmployeeWorkStatus.Active);
        if (IsManager && !IsAdmin)
        {
            var subs = await dataScope.GetSubordinateUserIdsAsync(CurrentUserId, storeId);
            if (subs.Count > 0) empQ = empQ.Where(e => e.ApplicationUserId != null && subs.Contains(e.ApplicationUserId.Value));
        }
        if (!string.IsNullOrWhiteSpace(department)) empQ = empQ.Where(e => e.Department == department);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var k = VnSearch.FoldText(search);
            empQ = empQ.Where(e => VnSearch.Has(e.LastName + " " + e.FirstName, k) || VnSearch.Has(e.EmployeeCode, k));
        }
        var emps = await empQ.OrderBy(e => e.Department).ThenBy(e => e.FirstName)
            .Select(e => new { e.Id, e.ApplicationUserId, Name = (e.LastName + " " + e.FirstName).Trim(), e.EmployeeCode, e.Department, e.Position, e.PhotoUrl })
            .ToListAsync(ct);
        var empIds = emps.Select(e => e.Id).ToList();
        var userIds = emps.Where(e => e.ApplicationUserId.HasValue).Select(e => e.ApplicationUserId!.Value).ToList();

        var schedules = await db.WorkSchedules.AsNoTracking()
            .Where(w => w.StoreId == storeId && w.Deleted == null && empIds.Contains(w.EmployeeUserId) && w.Date >= f && w.Date < toEx)
            .Select(w => new { w.Id, w.EmployeeUserId, w.Date, w.ShiftId, w.IsDayOff, w.StartTime, w.EndTime, w.Note })
            .ToListAsync(ct);
        var regs = await db.ScheduleRegistrations.AsNoTracking()
            .Where(r => r.StoreId == storeId && r.Deleted == null && r.Status == ScheduleRegistrationStatus.Pending
                        && empIds.Contains(r.EmployeeUserId) && r.Date >= f && r.Date < toEx)
            .Select(r => new { r.Id, r.EmployeeUserId, r.Date, r.ShiftId, r.IsDayOff, r.Note, r.CreatedAt })
            .ToListAsync(ct);
        var leaves = await db.Leaves.AsNoTracking()
            .Where(l => l.StoreId == storeId && l.Deleted == null && userIds.Contains(l.EmployeeUserId)
                        && (l.Status == LeaveStatus.Pending || l.Status == LeaveStatus.Approved)
                        && l.StartDate < toEx && l.EndDate >= f)
            .Select(l => new { l.Id, l.EmployeeUserId, l.StartDate, l.EndDate, l.ShiftIds, l.Status, l.Type, l.IsHalfShift })
            .ToListAsync(ct);
        var swaps = await db.ShiftSwapRequests.AsNoTracking()
            .Where(s => s.StoreId == storeId && s.Deleted == null
                        && (s.Status == ShiftSwapStatus.Pending || s.Status == ShiftSwapStatus.TargetAccepted)
                        && ((s.RequesterDate >= f && s.RequesterDate < toEx) || (s.TargetDate >= f && s.TargetDate < toEx)))
            .Select(s => new { s.Id, s.RequesterUserId, s.TargetUserId, s.RequesterDate, s.TargetDate, s.Status })
            .ToListAsync(ct);

        var tplMap = templates.ToDictionary(x => x.Id);
        var days = Enumerable.Range(0, (t - f).Days + 1).Select(i => f.AddDays(i)).ToList();

        var rows = emps.Select(e =>
        {
            var cells = new Dictionary<string, object>();
            double hours = 0;
            int shifts = 0, offs = 0;
            foreach (var d in days)
            {
                // Một ngày có thể nhiều ca: ca làm đứng trước ngày nghỉ, ô hiển thị ca đầu + «+N ca»; tổng giờ tính đủ mọi ca.
                var dayRows = schedules.Where(s => s.EmployeeUserId == e.Id && s.Date.Date == d)
                    .OrderBy(s => s.IsDayOff)
                    .ThenBy(s => s.StartTime ?? (s.ShiftId.HasValue && tplMap.ContainsKey(s.ShiftId.Value) ? tplMap[s.ShiftId.Value].Start : TimeSpan.Zero))
                    .ToList();
                var ws = dayRows.FirstOrDefault();
                var moreShifts = dayRows.Count(s => !s.IsDayOff) - (ws is { IsDayOff: false } ? 1 : 0);
                var reg = regs.Where(r => r.EmployeeUserId == e.Id && r.Date.Date == d).OrderByDescending(r => r.CreatedAt).FirstOrDefault();
                var lv = e.ApplicationUserId.HasValue
                    ? leaves.Where(l => l.EmployeeUserId == e.ApplicationUserId.Value
                                        && ShiftCoverageRules.LeaveCovers(l.StartDate, l.EndDate, l.ShiftIds, d, ws?.ShiftId))
                        .OrderBy(l => l.Status == LeaveStatus.Approved ? 0 : 1).FirstOrDefault()
                    : null;
                var swap = e.ApplicationUserId.HasValue && swaps.Any(s =>
                    (s.RequesterUserId == e.ApplicationUserId && s.RequesterDate.Date == d) ||
                    (s.TargetUserId == e.ApplicationUserId && s.TargetDate.Date == d));
                if (ws == null && reg == null && lv == null && !swap) continue;

                foreach (var row in dayRows)
                {
                    if (row.IsDayOff) offs++;
                    else if (row.ShiftId.HasValue && tplMap.TryGetValue(row.ShiftId.Value, out var tp))
                    {
                        shifts++;
                        if (lv == null || lv.Status != LeaveStatus.Approved)
                            hours += ShiftCoverageRules.ShiftHours(row.StartTime ?? tp.Start, row.EndTime ?? tp.End, tp.Break);
                    }
                }
                cells[Key(d)] = new
                {
                    scheduleId = ws?.Id,
                    shiftId = ws?.ShiftId,
                    isDayOff = ws?.IsDayOff ?? false,
                    start = ws?.StartTime?.ToString(@"hh\:mm"),
                    end = ws?.EndTime?.ToString(@"hh\:mm"),
                    note = ws?.Note,
                    moreShifts,
                    items = dayRows.Select(r => new { scheduleId = r.Id, shiftId = r.ShiftId, isDayOff = r.IsDayOff }),
                    registration = reg == null ? null : new { id = reg.Id, shiftId = reg.ShiftId, isDayOff = reg.IsDayOff, note = reg.Note },
                    leave = lv == null ? null : new { id = lv.Id, status = lv.Status.ToString(), type = lv.Type.ToString(), halfShift = lv.IsHalfShift },
                    swapPending = swap,
                };
            }
            return new
            {
                id = e.Id,
                userId = e.ApplicationUserId,
                name = e.Name,
                code = e.EmployeeCode,
                department = e.Department,
                position = e.Position,
                photoUrl = e.PhotoUrl,
                cells,
                totals = new { shifts, dayOff = offs, hours = Math.Round(hours, 1) },
            };
        }).ToList();

        var coverage = await CoverageAsync(storeId, f, t, templates, department, ct);
        var departments = await db.Employees.AsNoTracking()
            .Where(e => e.StoreId == storeId && e.Deleted == null && e.Department != null && e.Department != "")
            .Select(e => e.Department!).Distinct().OrderBy(d => d).ToListAsync(ct);

        return Ok(AppResponse<object>.Success(new
        {
            from = Key(f),
            to = Key(t),
            today = Key(VnToday),
            days = days.Select(Key),
            templates = templates.Select((x, i) => TplDto(x, i)),
            departments,
            employees = rows,
            coverage = coverage.Select(CovDto),
            summary = new
            {
                employees = rows.Count,
                unscheduled = rows.Count(r => r.totals.shifts == 0 && r.totals.dayOff == 0),
                plannedHours = Math.Round(rows.Sum(r => r.totals.hours), 1),
                pendingRegistrations = regs.Count,
                pendingLeaves = leaves.Count(l => l.Status == LeaveStatus.Pending),
                swapsPending = swaps.Count,
                shortSlots = coverage.Count(c => ShiftCoverageRules.Status(c.Effective, c.Min, c.Max, c.Warn, c.HasQuota) == ShiftCoverageRules.Short),
                overSlots = coverage.Count(c => ShiftCoverageRules.Status(c.Effective, c.Min, c.Max, c.Warn, c.HasQuota) == ShiftCoverageRules.Over),
            },
        }));
    }

    // ═════════════ LỊCH CỦA TÔI (NHÂN VIÊN) ═════════════

    /// <summary>
    /// Lịch của tôi theo ngày: ca đã xếp, đăng ký gần nhất, nghỉ phép, đổi ca; kèm số chỗ còn trống từng ca
    /// (để đăng ký) và yêu cầu đổi ca đang chờ tôi trả lời.
    /// </summary>
    [HttpGet("my")]
    [RequireModulePermission("WorkSchedule", ModulePermissionAction.View)]
    public async Task<IActionResult> GetMy([FromQuery] DateTime? from, [FromQuery] DateTime? to, CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var uid = CurrentUserId;
        var (f, t) = Range(from, to);
        var toEx = t.AddDays(1);
        var emp = await db.Employees.AsNoTracking()
            .Where(e => e.StoreId == storeId && e.Deleted == null && (e.ApplicationUserId == uid || e.Id == EmployeeId))
            .Select(e => new { e.Id, Name = (e.LastName + " " + e.FirstName).Trim(), e.EmployeeCode, e.Department, e.Position })
            .FirstOrDefaultAsync(ct);
        var templates = await TemplatesAsync(storeId, ct);
        var tplMap = templates.ToDictionary(x => x.Id);
        var empId = emp?.Id ?? Guid.Empty;

        var schedules = await db.WorkSchedules.AsNoTracking()
            .Where(w => w.StoreId == storeId && w.Deleted == null && w.EmployeeUserId == empId && w.Date >= f && w.Date < toEx)
            .Select(w => new { w.Id, w.Date, w.ShiftId, w.IsDayOff, w.StartTime, w.EndTime, w.Note })
            .ToListAsync(ct);
        var regs = await db.ScheduleRegistrations.AsNoTracking()
            .Where(r => r.StoreId == storeId && r.Deleted == null && r.EmployeeUserId == empId && r.Date >= f && r.Date < toEx)
            .OrderByDescending(r => r.CreatedAt)
            .Select(r => new { r.Id, r.Date, r.ShiftId, r.IsDayOff, r.Status, r.RejectionReason, r.Note })
            .ToListAsync(ct);
        var leaves = await db.Leaves.AsNoTracking()
            .Where(l => l.StoreId == storeId && l.Deleted == null && l.EmployeeUserId == uid
                        && l.Status != LeaveStatus.Cancelled && l.StartDate < toEx && l.EndDate >= f)
            .Select(l => new { l.Id, l.StartDate, l.EndDate, l.ShiftIds, l.Status, l.Type, l.IsHalfShift, l.Reason, l.RejectionReason })
            .ToListAsync(ct);
        var swaps = await db.ShiftSwapRequests.AsNoTracking()
            .Where(s => s.StoreId == storeId && s.Deleted == null && (s.RequesterUserId == uid || s.TargetUserId == uid)
                        && ((s.RequesterDate >= f && s.RequesterDate < toEx) || (s.TargetDate >= f && s.TargetDate < toEx)
                            || s.Status == ShiftSwapStatus.Pending))
            .Select(s => new
            {
                s.Id, s.RequesterUserId, s.TargetUserId, s.RequesterDate, s.TargetDate, s.RequesterShiftId, s.TargetShiftId,
                s.Status, s.Reason, s.RejectionReason,
                RequesterName = (s.RequesterUser.LastName + " " + s.RequesterUser.FirstName).Trim(),
                TargetName = (s.TargetUser.LastName + " " + s.TargetUser.FirstName).Trim(),
            })
            .ToListAsync(ct);
        var coverage = await CoverageAsync(storeId, f, t, templates, emp?.Department, ct);

        string TplLabel(Guid? id) => id.HasValue && tplMap.TryGetValue(id.Value, out var x)
            ? $"{x.Name} {x.Start:hh\\:mm}–{x.End:hh\\:mm}" : "";
        object SwapDto(dynamic s) => new
        {
            id = (Guid)s.Id,
            status = ((ShiftSwapStatus)s.Status).ToString(),
            iAmRequester = (Guid)s.RequesterUserId == uid,
            otherName = (Guid)s.RequesterUserId == uid ? (string)s.TargetName : (string)s.RequesterName,
            myDate = Key((Guid)s.RequesterUserId == uid ? (DateTime)s.RequesterDate : (DateTime)s.TargetDate),
            myShift = TplLabel((Guid)s.RequesterUserId == uid ? (Guid)s.RequesterShiftId : (Guid)s.TargetShiftId),
            theirDate = Key((Guid)s.RequesterUserId == uid ? (DateTime)s.TargetDate : (DateTime)s.RequesterDate),
            theirShift = TplLabel((Guid)s.RequesterUserId == uid ? (Guid)s.TargetShiftId : (Guid)s.RequesterShiftId),
            reason = (string?)s.Reason,
            rejectionReason = (string?)s.RejectionReason,
        };

        double hours = 0;
        var days = Enumerable.Range(0, (t - f).Days + 1).Select(i => f.AddDays(i)).Select(d =>
        {
            var dayRows = schedules.Where(s => s.Date.Date == d)
                .OrderBy(s => s.IsDayOff)
                .ThenBy(s => s.StartTime ?? (s.ShiftId.HasValue && tplMap.ContainsKey(s.ShiftId.Value) ? tplMap[s.ShiftId.Value].Start : TimeSpan.Zero))
                .ToList();
            var ws = dayRows.FirstOrDefault();
            var reg = regs.FirstOrDefault(r => r.Date.Date == d);
            var lv = leaves.Where(l => ShiftCoverageRules.LeaveCovers(l.StartDate, l.EndDate, l.ShiftIds, d, ws?.ShiftId)).ToList();
            if (!lv.Any(l => l.Status == LeaveStatus.Approved))
                foreach (var row in dayRows.Where(r => !r.IsDayOff && r.ShiftId.HasValue))
                    if (tplMap.TryGetValue(row.ShiftId!.Value, out var tp))
                        hours += ShiftCoverageRules.ShiftHours(row.StartTime ?? tp.Start, row.EndTime ?? tp.End, tp.Break);
            return new
            {
                date = Key(d),
                isPast = d < VnToday,
                isToday = d == VnToday,
                schedule = ws == null ? null : new
                {
                    id = ws.Id,
                    shiftId = ws.ShiftId,
                    isDayOff = ws.IsDayOff,
                    start = (ws.StartTime ?? (ws.ShiftId.HasValue && tplMap.ContainsKey(ws.ShiftId.Value) ? tplMap[ws.ShiftId.Value].Start : null))?.ToString(@"hh\:mm"),
                    end = (ws.EndTime ?? (ws.ShiftId.HasValue && tplMap.ContainsKey(ws.ShiftId.Value) ? tplMap[ws.ShiftId.Value].End : null))?.ToString(@"hh\:mm"),
                    note = ws.Note,
                },
                // Mọi ca trong ngày (ca đầu cũng nằm trong `schedule` để tương thích bản cũ).
                schedules = dayRows.Select(r => new
                {
                    id = r.Id,
                    shiftId = r.ShiftId,
                    isDayOff = r.IsDayOff,
                    start = (r.StartTime ?? (r.ShiftId.HasValue && tplMap.ContainsKey(r.ShiftId.Value) ? tplMap[r.ShiftId.Value].Start : null))?.ToString(@"hh\:mm"),
                    end = (r.EndTime ?? (r.ShiftId.HasValue && tplMap.ContainsKey(r.ShiftId.Value) ? tplMap[r.ShiftId.Value].End : null))?.ToString(@"hh\:mm"),
                    note = r.Note,
                }),
                registration = reg == null ? null : new
                {
                    id = reg.Id, shiftId = reg.ShiftId, isDayOff = reg.IsDayOff,
                    status = reg.Status.ToString(), rejectionReason = reg.RejectionReason, note = reg.Note,
                },
                leaves = lv.Select(l => new
                {
                    id = l.Id, status = l.Status.ToString(), type = l.Type.ToString(), halfShift = l.IsHalfShift,
                    reason = l.Reason, rejectionReason = l.RejectionReason,
                    from = Key(l.StartDate), to = Key(l.EndDate),
                }),
                swaps = swaps.Where(s => (s.RequesterUserId == uid ? s.RequesterDate : s.TargetDate).Date == d).Select(SwapDto),
                slots = coverage.Where(c => c.Date == d).Select(CovDto),
            };
        }).ToList();

        return Ok(AppResponse<object>.Success(new
        {
            employee = emp,
            from = Key(f),
            to = Key(t),
            today = Key(VnToday),
            templates = templates.Where(x => x.Active).Select((x, i) => TplDto(x, i)),
            days,
            incomingSwaps = swaps.Where(s => s.TargetUserId == uid && s.Status == ShiftSwapStatus.Pending).Select(SwapDto),
            summary = new
            {
                shifts = schedules.Count(s => !s.IsDayOff && s.ShiftId != null),
                dayOff = schedules.Count(s => s.IsDayOff),
                hours = Math.Round(hours, 1),
                pendingRegistrations = regs.Count(r => r.Status == ScheduleRegistrationStatus.Pending),
                pendingLeaves = leaves.Count(l => l.Status == LeaveStatus.Pending),
                pendingSwaps = swaps.Count(s => s.Status is ShiftSwapStatus.Pending or ShiftSwapStatus.TargetAccepted),
            },
        }));
    }

    /// <summary>Đồng nghiệp có ca trong ngày (để chọn người đổi ca) — cùng bộ phận lên trước.</summary>
    [HttpGet("swap-options")]
    [RequireModulePermission("ShiftSwap", ModulePermissionAction.View)]
    public async Task<IActionResult> GetSwapOptions([FromQuery] DateTime date, CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var uid = CurrentUserId;
        var d = date.Date;
        var me = await db.Employees.AsNoTracking()
            .Where(e => e.StoreId == storeId && e.ApplicationUserId == uid)
            .Select(e => new { e.Id, e.Department }).FirstOrDefaultAsync(ct);
        var templates = (await TemplatesAsync(storeId, ct)).ToDictionary(x => x.Id);
        var rows = await db.WorkSchedules.AsNoTracking()
            .Where(w => w.StoreId == storeId && w.Deleted == null && !w.IsDayOff && w.ShiftId != null
                        && w.Date >= d && w.Date < d.AddDays(1)
                        && w.Employee.ApplicationUserId != null && w.Employee.ApplicationUserId != uid
                        && w.Employee.Deleted == null)
            .Select(w => new
            {
                w.ShiftId,
                UserId = w.Employee.ApplicationUserId,
                Name = (w.Employee.LastName + " " + w.Employee.FirstName).Trim(),
                w.Employee.Department,
                w.Employee.Position,
            })
            .ToListAsync(ct);
        return Ok(AppResponse<object>.Success(rows
            .OrderBy(r => string.Equals(r.Department, me?.Department, StringComparison.OrdinalIgnoreCase) ? 0 : 1)
            .ThenBy(r => r.Name)
            .Select(r => new
            {
                userId = r.UserId,
                name = r.Name,
                department = r.Department,
                position = r.Position,
                shiftId = r.ShiftId,
                shift = templates.TryGetValue(r.ShiftId!.Value, out var x) ? $"{x.Name} {x.Start:hh\\:mm}–{x.End:hh\\:mm}" : "",
                sameDepartment = string.Equals(r.Department, me?.Department, StringComparison.OrdinalIgnoreCase),
            })));
    }

    // ═════════════ SỐ VIỆC CHỜ DUYỆT ═════════════

    /// <summary>Số việc chờ: đăng ký ca, đơn nghỉ (theo đúng chuỗi duyệt), đổi ca chờ quản lý, đổi ca chờ tôi, ca giờ chờ duyệt.</summary>
    [HttpGet("counts")]
    public async Task<IActionResult> GetCounts(CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var uid = CurrentUserId;
        var swapsForMe = await db.ShiftSwapRequests.CountAsync(s => s.StoreId == storeId && s.Deleted == null
            && s.TargetUserId == uid && s.Status == ShiftSwapStatus.Pending
            && s.RequesterDate >= VnToday && s.TargetDate >= VnToday, ct);
        if (!IsManager)
            return Ok(AppResponse<object>.Success(new { swapsForMe, registrations = 0, leaves = 0, swaps = 0, shifts = 0, total = swapsForMe }));

        var today = VnToday;
        var registrations = await db.ScheduleRegistrations.CountAsync(r => r.StoreId == storeId && r.Deleted == null
            && r.Status == ScheduleRegistrationStatus.Pending && r.Date >= today.AddDays(-7), ct);
        var swaps = await db.ShiftSwapRequests.CountAsync(s => s.StoreId == storeId && s.Deleted == null
            && s.Status == ShiftSwapStatus.TargetAccepted
            && s.RequesterDate >= today && s.TargetDate >= today, ct);
        var shifts = await db.Shifts.CountAsync(s => s.StoreId == storeId && s.Status == ShiftStatus.Pending, ct);
        var leaves = 0;
        try
        {
            List<Guid>? subs = IsManager && !IsAdmin ? await dataScope.GetSubordinateUserIdsAsync(uid, storeId) : null;
            var res = await mediator.Send(new GetPendingLeavesQuery(storeId, uid, IsManager, new PaginationRequest { PageNumber = 1, PageSize = 500 }, subs), ct);
            leaves = res.Data?.TotalCount ?? 0;
        }
        catch { /* không chặn đếm các mục khác */ }
        return Ok(AppResponse<object>.Success(new
        {
            swapsForMe, registrations, leaves, swaps, shifts,
            total = swapsForMe + registrations + leaves + swaps + shifts,
        }));
    }
}
