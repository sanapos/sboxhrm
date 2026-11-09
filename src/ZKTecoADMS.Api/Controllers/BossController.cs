using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// App SBOX BOSS: «Cần duyệt» gộp mọi việc chờ chủ / quản lý xử lý (nghỉ phép, tăng ca, sửa công, chấm công mobile,
/// đổi ca, ca theo giờ, ứng lương, công tác phí, phiếu phạt, phiếu thu chi chờ duyệt) thành MỘT danh sách — app duyệt
/// bằng đúng endpoint duyệt sẵn có của từng loại (giữ chuỗi duyệt nhiều cấp, phiếu thu phạt, sổ quỹ…).
/// «issues»: vấn đề vận hành hôm nay chưa có trong <see cref="OverviewController"/> (ca thu ngân lệch quỹ).
/// </summary>
[ApiController]
[Route("api/boss")]
[Authorize(Policy = PolicyNames.AtLeastManager)]
public class BossController(ZKTecoDbContext db) : AuthenticatedControllerBase
{
    const int PerKind = 100;

    /// <summary>Một việc chờ duyệt. <see cref="Kind"/> quyết định endpoint duyệt phía app.</summary>
    public record InboxItem(
        string Kind, string Id, string Title, string Person, string? Detail, decimal? Amount,
        DateTime? When, DateTime CreatedAt, bool Urgent);

    static string Name(string? last, string? first, string? fallback = null)
    {
        var n = $"{last} {first}".Trim();
        return n.Length > 0 ? n : (fallback ?? "Không rõ");
    }

    static string LeaveLabel(LeaveType t) => t switch
    {
        LeaveType.AnnualLeave => "Nghỉ phép năm",
        LeaveType.Holiday => "Nghỉ lễ",
        LeaveType.PersonalPaid => "Nghỉ việc riêng có lương",
        LeaveType.PersonalUnpaid => "Nghỉ không lương",
        LeaveType.SickLeave => "Nghỉ ốm",
        LeaveType.MaternityLeave => "Nghỉ thai sản",
        LeaveType.CompensatoryLeave => "Nghỉ bù",
        LeaveType.LongTermLeave => "Nghỉ dài hạn",
        _ => "Nghỉ",
    };

    static string PenaltyLabel(PenaltyTicketType t) => t switch
    {
        PenaltyTicketType.Late => "Đi trễ",
        PenaltyTicketType.EarlyLeave => "Về sớm",
        PenaltyTicketType.ForgotCheck => "Quên chấm công",
        PenaltyTicketType.UnauthorizedLeave => "Nghỉ không phép",
        PenaltyTicketType.Violation => "Vi phạm nội quy",
        PenaltyTicketType.Repeat => "Tái phạm",
        _ => "Vi phạm",
    };

    static string Dm(DateTime d) => d.ToString("dd/MM");

    [HttpGet("inbox")]
    public async Task<ActionResult<AppResponse<object>>> Inbox(CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var items = new List<InboxItem>();
        var todayVn = VnTimeHelper.NowVn().Date;

        // ── Máy POS đang chờ duyệt từ xa (hết hạn sau 3 phút) — luôn xếp đầu ──
        items.AddRange(PosRemoteApprovals.Pending(storeId).Select(r => new InboxItem(
            "posApproval", r.Id.ToString(), "Máy bán hàng xin duyệt", r.RequestedBy,
            r.Reason + (string.IsNullOrWhiteSpace(r.Detail) ? "" : $" · {r.Detail}")
                + $" · còn {Math.Max(0, (int)(r.ExpiresAt - DateTime.UtcNow).TotalSeconds)} giây",
            r.Amount, r.CreatedAt, r.CreatedAt, true)));

        // ── Nhân sự ──
        var leaves = await db.Leaves.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null && x.Status == LeaveStatus.Pending)
            .OrderBy(x => x.StartDate).Take(PerKind)
            .Select(x => new
            {
                x.Id, x.Type, x.StartDate, x.EndDate, x.IsHalfShift, x.Reason, x.CreatedAt,
                x.EmployeeUser.LastName, x.EmployeeUser.FirstName, x.EmployeeUser.Email,
            })
            .ToListAsync(ct);
        items.AddRange(leaves.Select(x => new InboxItem(
            "leave", x.Id.ToString(), LeaveLabel(x.Type) + (x.IsHalfShift ? " (nửa ca)" : ""),
            Name(x.LastName, x.FirstName, x.Email),
            (x.StartDate.Date == x.EndDate.Date ? Dm(x.StartDate) : $"{Dm(x.StartDate)} – {Dm(x.EndDate)}")
                + (string.IsNullOrWhiteSpace(x.Reason) ? "" : $" · {x.Reason}"),
            null, x.StartDate, x.CreatedAt, x.StartDate.Date <= todayVn.AddDays(1))));

        var overtimes = await db.Overtimes.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null && x.Status == OvertimeStatus.Pending)
            .OrderBy(x => x.Date).Take(PerKind)
            .Select(x => new
            {
                x.Id, x.Date, x.StartTime, x.EndTime, x.PlannedHours, x.Reason, x.CreatedAt,
                x.EmployeeUser.LastName, x.EmployeeUser.FirstName, x.EmployeeUser.Email,
            })
            .ToListAsync(ct);
        items.AddRange(overtimes.Select(x => new InboxItem(
            "overtime", x.Id.ToString(), $"Tăng ca {x.PlannedHours:0.#} giờ",
            Name(x.LastName, x.FirstName, x.Email),
            $"{Dm(x.Date)} {x.StartTime:hh\\:mm}–{x.EndTime:hh\\:mm}"
                + (string.IsNullOrWhiteSpace(x.Reason) ? "" : $" · {x.Reason}"),
            null, x.Date, x.CreatedAt, x.Date.Date <= todayVn)));

        var corrections = await db.AttendanceCorrectionRequests.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null && x.Status == CorrectionStatus.Pending)
            .OrderByDescending(x => x.CreatedAt).Take(PerKind)
            .Select(x => new
            {
                x.Id, x.Action, x.EmployeeName, x.NewDate, x.NewTime, x.OldDate, x.OldTime, x.Reason, x.CreatedAt,
                x.EmployeeUser.LastName, x.EmployeeUser.FirstName,
            })
            .ToListAsync(ct);
        items.AddRange(corrections.Select(x =>
        {
            var d = x.NewDate ?? x.OldDate;
            var t = x.NewTime ?? x.OldTime;
            var action = x.Action switch { CorrectionAction.Add => "Thêm giờ chấm", CorrectionAction.Edit => "Sửa giờ chấm", _ => "Xóa giờ chấm" };
            return new InboxItem(
                "correction", x.Id.ToString(), action,
                string.IsNullOrWhiteSpace(x.EmployeeName) ? Name(x.LastName, x.FirstName) : x.EmployeeName,
                $"{(d.HasValue ? Dm(d.Value) : "")} {(t.HasValue ? t.Value.ToString("hh\\:mm") : "")}".Trim()
                    + (string.IsNullOrWhiteSpace(x.Reason) ? "" : $" · {x.Reason}"),
                null, d, x.CreatedAt, false);
        }));

        var mobile = await db.MobileAttendanceRecords.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null && x.Status == "pending")
            .OrderByDescending(x => x.PunchTime).Take(PerKind)
            .Select(x => new { x.Id, x.EmployeeName, x.PunchTime, x.LocationName, x.IsOutside, x.RiskLevel, x.OutsideReason, x.CreatedAt })
            .ToListAsync(ct);
        items.AddRange(mobile.Select(x => new InboxItem(
            "mobileAttendance", x.Id.ToString(), x.IsOutside ? "Chấm công ngoài vị trí" : "Chấm công điện thoại",
            x.EmployeeName,
            $"{x.PunchTime:dd/MM HH:mm}"
                + (string.IsNullOrWhiteSpace(x.LocationName) ? "" : $" · {x.LocationName}")
                + (string.IsNullOrWhiteSpace(x.OutsideReason) ? "" : $" · {x.OutsideReason}"),
            null, x.PunchTime, x.CreatedAt, x.RiskLevel == "high")));

        var swaps = await db.ShiftSwapRequests.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null && x.Status == ShiftSwapStatus.TargetAccepted)
            .OrderBy(x => x.RequesterDate).Take(PerKind)
            .Select(x => new
            {
                x.Id, x.RequesterDate, x.TargetDate, x.Reason, x.CreatedAt,
                RLast = x.RequesterUser.LastName, RFirst = x.RequesterUser.FirstName,
                TLast = x.TargetUser.LastName, TFirst = x.TargetUser.FirstName,
                RShift = x.RequesterShift.Name, TShift = x.TargetShift.Name,
            })
            .ToListAsync(ct);
        items.AddRange(swaps.Select(x => new InboxItem(
            "shiftSwap", x.Id.ToString(), $"Đổi ca với {Name(x.TLast, x.TFirst)}",
            Name(x.RLast, x.RFirst),
            $"{x.RShift} {Dm(x.RequesterDate)} ⇄ {x.TShift} {Dm(x.TargetDate)}"
                + (string.IsNullOrWhiteSpace(x.Reason) ? "" : $" · {x.Reason}"),
            null, x.RequesterDate, x.CreatedAt, x.RequesterDate.Date <= todayVn.AddDays(1))));

        var shifts = await db.Shifts.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null && x.Status == ShiftStatus.Pending)
            .OrderBy(x => x.StartTime).Take(PerKind)
            .Select(x => new { x.Id, x.StartTime, x.EndTime, x.Description, x.CreatedAt, x.EmployeeUser.LastName, x.EmployeeUser.FirstName, x.EmployeeUser.Email })
            .ToListAsync(ct);
        items.AddRange(shifts.Select(x => new InboxItem(
            "shift", x.Id.ToString(), "Đăng ký ca theo giờ", Name(x.LastName, x.FirstName, x.Email),
            $"{x.StartTime:dd/MM HH:mm}–{x.EndTime:HH:mm}"
                + (string.IsNullOrWhiteSpace(x.Description) ? "" : $" · {x.Description}"),
            null, x.StartTime, x.CreatedAt, x.StartTime.Date <= todayVn)));

        // ── Tiền ──
        var advances = await db.AdvanceRequests.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null && x.Status == AdvanceRequestStatus.Pending)
            .OrderByDescending(x => x.RequestDate).Take(PerKind)
            .Select(x => new
            {
                x.Id, x.Amount, x.Reason, x.RequestDate, x.CreatedAt,
                ELast = x.Employee != null ? x.Employee.LastName : null, EFirst = x.Employee != null ? x.Employee.FirstName : null,
                ULast = x.EmployeeUser != null ? x.EmployeeUser.LastName : null, UFirst = x.EmployeeUser != null ? x.EmployeeUser.FirstName : null,
            })
            .ToListAsync(ct);
        items.AddRange(advances.Select(x => new InboxItem(
            "advance", x.Id.ToString(), "Ứng lương",
            x.ELast != null || x.EFirst != null ? Name(x.ELast, x.EFirst) : Name(x.ULast, x.UFirst),
            string.IsNullOrWhiteSpace(x.Reason) ? null : x.Reason, x.Amount, x.RequestDate, x.CreatedAt, false)));

        var trips = await db.BusinessTripCases.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null
                && (x.Status == BusinessTripCaseStatus.AdvancePending || x.Status == BusinessTripCaseStatus.SettlementPending))
            .OrderByDescending(x => x.CreatedAt).Take(PerKind)
            .Select(x => new
            {
                x.Id, x.Status, x.Title, x.Destination, x.AdvanceAmount, x.SettledAmount, x.TripFromDate, x.CreatedAt,
                ELast = x.Employee != null ? x.Employee.LastName : null, EFirst = x.Employee != null ? x.Employee.FirstName : null,
            })
            .ToListAsync(ct);
        items.AddRange(trips.Select(x =>
        {
            var settle = x.Status == BusinessTripCaseStatus.SettlementPending;
            return new InboxItem(
                settle ? "tripSettlement" : "tripAdvance", x.Id.ToString(),
                settle ? "Quyết toán công tác" : "Tạm ứng công tác", Name(x.ELast, x.EFirst),
                x.Title + (string.IsNullOrWhiteSpace(x.Destination) ? "" : $" · {x.Destination}"),
                settle ? x.SettledAmount : x.AdvanceAmount, x.TripFromDate, x.CreatedAt, false);
        }));

        var penalties = await db.PenaltyTickets.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null && x.Status == PenaltyTicketStatus.Pending)
            .OrderByDescending(x => x.ViolationDate).Take(PerKind)
            .Select(x => new { x.Id, x.TicketCode, x.Type, x.Amount, x.ViolationDate, x.MinutesLateOrEarly, x.Description, x.CreatedAt, x.Employee.LastName, x.Employee.FirstName })
            .ToListAsync(ct);
        items.AddRange(penalties.Select(x => new InboxItem(
            "penalty", x.Id.ToString(),
            $"Phạt {PenaltyLabel(x.Type).ToLowerInvariant()}" + (x.MinutesLateOrEarly is > 0 ? $" {x.MinutesLateOrEarly} phút" : ""),
            Name(x.LastName, x.FirstName),
            $"{Dm(x.ViolationDate)} · {x.TicketCode}" + (string.IsNullOrWhiteSpace(x.Description) ? "" : $" · {x.Description}"),
            x.Amount, x.ViolationDate, x.CreatedAt, false)));

        var cash = await db.CashTransactions.AsNoTracking().ApplyBranchScope(HttpContext.BranchContext())
            .Where(x => x.StoreId == storeId && x.Deleted == null && x.IsActive && x.Status == CashTransactionStatus.Pending)
            .OrderByDescending(x => x.TransactionDate).Take(PerKind)
            .Select(x => new
            {
                x.Id, x.Type, x.Amount, x.Description, x.TransactionCode, x.ContactName, x.TransactionDate, x.CreatedAt,
                CLast = x.CreatedByUser != null ? x.CreatedByUser.LastName : null,
                CFirst = x.CreatedByUser != null ? x.CreatedByUser.FirstName : null,
            })
            .ToListAsync(ct);
        items.AddRange(cash.Select(x => new InboxItem(
            "cash", x.Id.ToString(), x.Type == CashTransactionType.Income ? "Phiếu thu chờ duyệt" : "Phiếu chi chờ duyệt",
            x.CLast != null || x.CFirst != null ? Name(x.CLast, x.CFirst) : (x.ContactName ?? "Không rõ"),
            $"{x.TransactionCode} · {x.Description}" + (string.IsNullOrWhiteSpace(x.ContactName) ? "" : $" · {x.ContactName}"),
            x.Amount, x.TransactionDate, x.CreatedAt, false)));

        var ordered = items
            .OrderByDescending(x => x.Kind == "posApproval")
            .ThenByDescending(x => x.Urgent)
            .ThenByDescending(x => x.CreatedAt)
            .ToList();
        var counts = ordered.GroupBy(x => x.Kind).ToDictionary(g => g.Key, g => g.Count());
        return Ok(AppResponse<object>.Success(new { total = ordered.Count, counts, items = ordered }));
    }

    /// <summary>
    /// Nhân viên hôm nay: giờ chấm đầu / cuối của từng người trong phạm vi được xem (chi nhánh đang chọn; quản lý
    /// thì cấp dưới và nhân viên chi nhánh được phép). Lượt chấm nối qua DeviceUser vì Attendance.EmployeeId là khóa DeviceUser.
    /// </summary>
    [HttpGet("staff-today")]
    [RequireModulePermission("Attendance", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> StaffToday(
        [FromServices] IDataScopeService dataScope, CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var bctx = HttpContext.BranchContext();
        var hq = bctx?.HeadquarterBranchId ?? Guid.Empty;
        var employees = db.Employees.AsNoTracking()
            .Where(e => e.StoreId == storeId && e.Deleted == null && e.WorkStatus != EmployeeWorkStatus.Resigned);
        if (bctx is { StoreUsesBranches: true, FilterBranchId: Guid selected })
            employees = employees.Where(e => (e.BranchId ?? hq) == selected);
        if (!SeesWholeStore)
        {
            var allowed = bctx is { StoreUsesBranches: true, AllowedBranchIds: { } a } ? a.ToList() : [];
            var subordinates = await dataScope.GetSubordinateEmployeeIdsAsync(CurrentUserId, storeId);
            employees = employees.Where(e => subordinates.Contains(e.Id) || allowed.Contains(e.BranchId ?? hq));
        }

        var staff = await employees
            .OrderBy(e => e.FirstName)
            .Select(e => new { e.Id, e.EmployeeCode, e.LastName, e.FirstName })
            .ToListAsync(ct);
        var ids = staff.Select(e => e.Id).ToList();
        var today = VnTimeHelper.NowVn().Date;
        var punches = await db.AttendanceLogs.AsNoTracking()
            .Where(a => a.AttendanceTime >= today && a.AttendanceTime < today.AddDays(1) && a.EmployeeId != null)
            .Join(db.DeviceUsers, a => a.EmployeeId, du => (Guid?)du.Id, (a, du) => new { du.EmployeeId, a.AttendanceTime })
            .Where(p => p.EmployeeId != null && ids.Contains(p.EmployeeId.Value))
            .GroupBy(p => p.EmployeeId!.Value)
            .Select(g => new { Id = g.Key, First = g.Min(p => p.AttendanceTime), Last = g.Max(p => p.AttendanceTime) })
            .ToListAsync(ct);
        var byEmployee = punches.ToDictionary(p => p.Id);

        // Ca hôm nay theo lịch làm việc (giờ riêng của lịch, không có thì giờ của mẫu ca) — để biết ai đi trễ,
        // ai «chưa chấm» mà đã tới giờ ca, ai hôm nay không có ca. Cửa hàng không xếp lịch thì hasSchedules = false.
        var schedules = await db.WorkSchedules.AsNoTracking()
            .Where(w => ids.Contains(w.EmployeeUserId) && w.Date >= today && w.Date < today.AddDays(1))
            .Select(w => new
            {
                w.EmployeeUserId, w.IsDayOff,
                Start = w.StartTime ?? (w.Shift != null ? w.Shift.StartTime : (TimeSpan?)null),
                End = w.EndTime ?? (w.Shift != null ? w.Shift.EndTime : (TimeSpan?)null),
                ShiftName = w.Shift != null ? w.Shift.Name : null,
                Grace = w.Shift != null ? w.Shift.LateGraceMinutes : 0,
            })
            .ToListAsync(ct);
        // Nhiều ca trong ngày: lấy ca bắt đầu sớm nhất để tính trễ lần chấm đầu.
        var scheduleByEmployee = schedules
            .GroupBy(w => w.EmployeeUserId)
            .ToDictionary(g => g.Key, g => g.OrderBy(w => w.IsDayOff).ThenBy(w => w.Start ?? TimeSpan.MaxValue).First());

        // Nghỉ phép đã duyệt hôm nay (đơn gắn NV qua EmployeeId hoặc tài khoản ApplicationUser).
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

        static string? Hm(TimeSpan? t) => t is TimeSpan v ? $"{v.Hours:00}:{v.Minutes:00}" : null;
        return Ok(AppResponse<object>.Success(new
        {
            hasSchedules = schedules.Count > 0,
            now = VnTimeHelper.NowVn(),
            staff = staff.Select(e =>
            {
                byEmployee.TryGetValue(e.Id, out var p);
                scheduleByEmployee.TryGetValue(e.Id, out var w);
                var hasLeave = leaveByEmployee.TryGetValue(e.Id, out var lv);
                var shiftStart = w is { IsDayOff: false, Start: TimeSpan st } ? today + st : (DateTime?)null;
                var late = 0;
                if (p != null && shiftStart is DateTime start)
                {
                    var diff = (int)Math.Floor((p.First - start).TotalMinutes);
                    if (diff > (w?.Grace ?? 0)) late = diff;
                }
                return new
                {
                    id = e.Id,
                    code = e.EmployeeCode,
                    name = Name(e.LastName, e.FirstName, e.EmployeeCode),
                    firstPunch = p?.First,
                    lastPunch = p?.Last,
                    hasShift = w is { IsDayOff: false },
                    dayOff = w?.IsDayOff ?? false,
                    shiftName = w?.ShiftName,
                    shiftStart = w is { IsDayOff: false } ? Hm(w.Start) : null,
                    shiftEnd = w is { IsDayOff: false } ? Hm(w.End) : null,
                    lateMinutes = late,
                    onLeave = hasLeave,
                    leaveHalf = hasLeave && lv.Half,
                    leaveType = hasLeave ? lv.Type.ToString() : null,
                };
            }),
        }));
    }

    /// <summary>Ca thu ngân đóng trong 2 ngày gần nhất bị lệch quỹ (đếm thực tế ≠ máy tính).</summary>
    [HttpGet("issues")]
    public async Task<ActionResult<AppResponse<object>>> Issues(CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var since = DateTime.UtcNow.AddDays(-2);
        var shifts = await db.PosCashierShifts.AsNoTracking().ApplyBranchScope(HttpContext.BranchContext())
            .Where(s => s.StoreId == storeId && s.ClosedAt != null && s.ClosedAt >= since
                && s.Difference != null && s.Difference != 0)
            .OrderByDescending(s => s.ClosedAt)
            .Select(s => new
            {
                s.Id, s.OpenedAt, s.ClosedAt, s.OpenedByName, s.ClosedByName, s.ExpectedCash, s.CountedCash, s.Difference, s.Note,
            })
            .Take(50)
            .ToListAsync(ct);
        var openShifts = await db.PosCashierShifts.AsNoTracking().ApplyBranchScope(HttpContext.BranchContext())
            .CountAsync(s => s.StoreId == storeId && s.ClosedAt == null && s.OpenedAt < DateTime.UtcNow.AddHours(-16), ct);
        return Ok(AppResponse<object>.Success(new
        {
            cashierDiffs = shifts,
            cashierDiffTotal = shifts.Sum(s => s.Difference ?? 0),
            staleOpenShifts = openShifts,
        }));
    }
}
