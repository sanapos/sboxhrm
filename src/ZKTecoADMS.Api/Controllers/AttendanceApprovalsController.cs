using ZKTecoADMS.Application.Helpers;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Commands.AttendanceCorrections;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

public class AttendanceApprovalItemDto
{
    /// <summary>mobile / correction</summary>
    public string Kind { get; set; } = "";
    public Guid Id { get; set; }
    public string EmployeeName { get; set; } = "";
    public string? EmployeeCode { get; set; }
    public string? PhotoUrl { get; set; }
    public string? Department { get; set; }
    public Guid? BranchId { get; set; }
    /// <summary>Thời điểm chấm / thời điểm xin sửa</summary>
    public DateTime Time { get; set; }
    public DateTime CreatedAt { get; set; }
    public string Title { get; set; } = "";
    public string? Subtitle { get; set; }
    public string? Reason { get; set; }
    public string? RiskLevel { get; set; }
    public int RiskScore { get; set; }
    public List<string> Flags { get; set; } = [];
    public double? Distance { get; set; }
    public string? LocationName { get; set; }
    public string? SitePhotoUrl { get; set; }
    public double? FaceScore { get; set; }
    public int? PunchType { get; set; }
    public bool IsOutside { get; set; }
    public bool IsTravel { get; set; }
    public int? CorrectionAction { get; set; }
    public string? Step { get; set; }
    public bool Overdue { get; set; }
}

public class ApproveAndFineRequest
{
    public string? Note { get; set; }
    public decimal? Amount { get; set; }
}

/// <summary>
/// Hộp duyệt chấm công v2: gộp chấm công Mobile ngoài vị trí và yêu cầu sửa/bổ sung công,
/// ngữ cảnh ngày công, «duyệt kèm phạt quên chấm công» thực hiện trọn vẹn trên server.
/// Duyệt/từ chối từng bản vẫn qua API gốc (mobile-attendance/approve, AttendanceCorrections/{id}/approve).
/// </summary>
[ApiController]
[Route("api/attendance-approvals")]
public class AttendanceApprovalsController(
    ZKTecoDbContext db,
    IMediator mediator,
    ISystemNotificationService notifications,
    ILogger<AttendanceApprovalsController> logger) : AuthenticatedControllerBase
{
    private static string PunchLabel(int t) => t switch
    {
        0 => "Vào ca", 1 => "Ra ca", 2 => "Bắt đầu đi", 3 => "Đến điểm làm", 4 => "Nghỉ trưa / OT vào", 5 => "Nghỉ trưa / OT ra", _ => "Chấm công",
    };

    private static List<string> Flags(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return [];
        try { return JsonSerializer.Deserialize<List<string>>(json) ?? []; } catch { return []; }
    }

    private sealed record Emp(Guid Id, Guid? UserId, string Name, string Code, string? Dept, string? Photo, Guid? BranchId);

    private async Task<List<Emp>> EmployeesAsync(Guid storeId) => await db.Employees.AsNoTracking()
        .Where(e => e.StoreId == storeId)
        .Select(e => new Emp(e.Id, e.ApplicationUserId, (e.LastName + " " + e.FirstName).Trim(), e.EmployeeCode, e.Department, e.PhotoUrl, e.BranchId))
        .ToListAsync();

    [HttpGet("inbox")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.View, "AttendanceApproval", "AttendanceCorrection", "MobileAttendanceApproval", "MobileAttendance")]
    public async Task<ActionResult<AppResponse<object>>> Inbox(
        [FromQuery] string? kind, [FromQuery] string? risk, [FromQuery] string? search, [FromQuery] Guid? branchId)
    {
        var storeId = RequiredStoreId;
        var emps = await EmployeesAsync(storeId);
        var byId = emps.ToDictionary(e => e.Id);
        var byUser = emps.Where(e => e.UserId.HasValue).GroupBy(e => e.UserId!.Value).ToDictionary(g => g.Key, g => g.First());
        var byCode = emps.Where(e => !string.IsNullOrEmpty(e.Code)).GroupBy(e => e.Code).ToDictionary(g => g.Key, g => g.First());
        Emp? FindOdoo(string odoo) => Guid.TryParse(odoo, out var g)
            ? byUser.GetValueOrDefault(g) ?? byId.GetValueOrDefault(g)
            : byCode.GetValueOrDefault(odoo);
        var nowUtc = DateTime.UtcNow;
        var items = new List<AttendanceApprovalItemDto>();

        var mobile = await db.MobileAttendanceRecords.AsNoTracking()
            .Where(r => r.StoreId == storeId && r.Status == "pending" && r.Deleted == null)
            .OrderByDescending(r => r.PunchTime)
            .Take(1000)
            .ToListAsync();
        foreach (var r in mobile)
        {
            var e = FindOdoo(r.OdooEmployeeId);
            var level = r.RiskLevel ?? (r.DistanceFromLocation is > 1000 ? MobilePunchRiskScorer.High : MobilePunchRiskScorer.Review);
            items.Add(new AttendanceApprovalItemDto
            {
                Kind = "mobile",
                Id = r.Id,
                EmployeeName = e?.Name ?? r.EmployeeName,
                EmployeeCode = e?.Code,
                PhotoUrl = e?.Photo,
                Department = e?.Dept,
                BranchId = e?.BranchId,
                Time = r.PunchTime,
                CreatedAt = r.CreatedAt,
                Title = $"{PunchLabel(r.PunchType)} {r.PunchTime:HH:mm}",
                Subtitle = r.LocationName == null ? "Không xác định vị trí"
                    : r.DistanceFromLocation is { } d ? $"{r.LocationName} · cách {MobilePunchRiskScorer.FormatDistance(d)}" : r.LocationName,
                Reason = r.OutsideReason ?? r.Note,
                RiskLevel = level,
                RiskScore = r.RiskScore,
                Flags = Flags(r.RiskFlags),
                Distance = r.DistanceFromLocation,
                LocationName = r.LocationName,
                SitePhotoUrl = string.IsNullOrWhiteSpace(r.SitePhotoUrl) ? null : r.SitePhotoUrl,
                FaceScore = r.FaceMatchScore,
                PunchType = r.PunchType,
                IsOutside = r.IsOutside || r.WifiBssid == null,
                IsTravel = r.PunchType is 2 or 3,
                Overdue = r.CreatedAt < nowUtc.AddHours(-24),
            });
        }

        var corrections = await db.AttendanceCorrectionRequests.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.Status == CorrectionStatus.Pending && c.Deleted == null)
            .OrderByDescending(c => c.CreatedAt)
            .Take(1000)
            .ToListAsync();
        foreach (var c in corrections)
        {
            var e = byUser.GetValueOrDefault(c.EmployeeUserId) ?? byId.GetValueOrDefault(c.EmployeeUserId);
            var date = c.NewDate ?? c.OldDate ?? c.CreatedAt;
            var newT = c.NewTime.HasValue ? c.NewTime.Value.ToString(@"hh\:mm") : null;
            var oldT = c.OldTime.HasValue ? c.OldTime.Value.ToString(@"hh\:mm") : null;
            items.Add(new AttendanceApprovalItemDto
            {
                Kind = "correction",
                Id = c.Id,
                EmployeeName = e?.Name ?? c.EmployeeName ?? "",
                EmployeeCode = e?.Code ?? c.EmployeeCode,
                PhotoUrl = e?.Photo,
                Department = e?.Dept,
                BranchId = e?.BranchId,
                Time = c.NewTime.HasValue && c.NewDate.HasValue ? c.NewDate.Value.Date.Add(c.NewTime.Value) : date,
                CreatedAt = c.CreatedAt,
                Title = c.Action switch
                {
                    CorrectionAction.Add => $"Bổ sung chấm công {newT} {date:dd/MM}",
                    CorrectionAction.Edit => $"Sửa giờ {oldT} → {newT} {date:dd/MM}",
                    _ => $"Xóa lần chấm {oldT} {date:dd/MM}",
                },
                Subtitle = c.NewPunchType,
                Reason = c.Reason,
                CorrectionAction = (int)c.Action,
                Step = c.TotalApprovalLevels > 1 ? $"Cấp {c.CurrentApprovalStep + 1}/{c.TotalApprovalLevels}" : null,
                Overdue = c.CreatedAt < nowUtc.AddHours(-24),
            });
        }

        // Chỉ hiện yêu cầu của nhân viên thuộc chi nhánh đang xem (bộ chọn chi nhánh trên đầu app).
        var view = await BranchViewHelper.ViewBranchIdsAsync(HttpContext, db, storeId);
        if (view != null)
        {
            var hq = HttpContext.BranchContext()?.HeadquarterBranchId;
            items = items.Where(i => BranchViewHelper.InView(view, i.BranchId, hq)).ToList();
        }

        var counts = new
        {
            all = items.Count,
            mobile = items.Count(i => i.Kind == "mobile"),
            correction = items.Count(i => i.Kind == "correction"),
            outside = items.Count(i => i.Kind == "mobile" && i.IsOutside),
            trusted = items.Count(i => i.RiskLevel == MobilePunchRiskScorer.Trusted && !i.IsTravel),
            high = items.Count(i => i.RiskLevel == MobilePunchRiskScorer.High),
            overdue = items.Count(i => i.Overdue),
        };

        IEnumerable<AttendanceApprovalItemDto> q = items;
        if (kind is "mobile" or "correction") q = q.Where(i => i.Kind == kind);
        if (!string.IsNullOrWhiteSpace(risk)) q = q.Where(i => i.RiskLevel == risk);
        if (branchId.HasValue)
        {
            // Nhân viên chưa gắn chi nhánh = trụ sở (cùng quy ước BranchQueryHelper).
            var hq = await BranchQueryHelper.HeadquarterIdAsync(db, storeId);
            q = q.Where(i => (i.BranchId ?? hq) == branchId);
        }
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = VnSearch.FoldText(search);
            q = q.Where(i => VnSearch.Fold(i.EmployeeName).Contains(s) || VnSearch.Fold(i.EmployeeCode).Contains(s));
        }
        var list = q.OrderBy(i => i.RiskLevel == MobilePunchRiskScorer.High ? 0 : i.Overdue ? 1 : 2)
            .ThenByDescending(i => i.Time).ToList();

        // Thống kê 30 ngày: tỉ lệ tự duyệt / duyệt tay / từ chối của chấm ngoài vị trí
        var since = nowUtc.AddDays(-30);
        var stats = await db.MobileAttendanceRecords.AsNoTracking()
            .Where(r => r.StoreId == storeId && r.Deleted == null && r.IsOutside && r.CreatedAt >= since)
            .GroupBy(r => r.Status)
            .Select(g => new { status = g.Key, count = g.Count() })
            .ToListAsync();

        return Ok(AppResponse<object>.Success(new { items = list, counts, stats30 = stats }));
    }

    // ─── Yêu cầu sửa công: ngữ cảnh + duyệt kèm phạt ─────────────────

    [HttpGet("corrections/{id:guid}/context")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.View, "AttendanceApproval", "AttendanceCorrection")]
    public async Task<ActionResult<AppResponse<object>>> CorrectionContext(Guid id)
    {
        var storeId = RequiredStoreId;
        var c = await db.AttendanceCorrectionRequests.AsNoTracking()
            .Include(x => x.ApprovalRecords)
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId);
        if (c == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy yêu cầu"));
        var emp = await db.Employees.AsNoTracking()
            .FirstOrDefaultAsync(e => e.StoreId == storeId && (e.ApplicationUserId == c.EmployeeUserId || e.Id == c.EmployeeUserId));
        var day = (c.NewDate ?? c.OldDate ?? c.CreatedAt).Date;
        var logs = new List<object>();
        object? shift = null;
        var monthCount = 0;
        if (emp != null)
        {
            var pins = await db.DeviceUsers.AsNoTracking().Where(u => u.EmployeeId == emp.Id).Select(u => u.Id).ToListAsync();
            if (pins.Count > 0)
                logs.AddRange(await db.AttendanceLogs.AsNoTracking()
                    .Where(a => a.EmployeeId != null && pins.Contains(a.EmployeeId.Value) && a.AttendanceTime >= day && a.AttendanceTime < day.AddDays(1))
                    .OrderBy(a => a.AttendanceTime)
                    .Select(a => (object)new { a.AttendanceTime, a.Note, fromMobile = a.MobileAttendanceRecordId != null })
                    .ToListAsync());
            var ws = await db.WorkSchedules.AsNoTracking().Include(w => w.Shift)
                .Where(w => w.EmployeeUserId == emp.Id && w.Date >= day && w.Date < day.AddDays(1))
                .FirstOrDefaultAsync();
            if (ws != null)
                shift = new
                {
                    name = ws.Shift?.Name,
                    dayOff = ws.IsDayOff,
                    start = (ws.StartTime ?? ws.Shift?.StartTime)?.ToString(@"hh\:mm"),
                    end = (ws.EndTime ?? ws.Shift?.EndTime)?.ToString(@"hh\:mm"),
                };
        }
        var monthStart = new DateTime(day.Year, day.Month, 1);
        monthCount = await db.AttendanceCorrectionRequests.AsNoTracking()
            .CountAsync(x => x.StoreId == storeId && x.EmployeeUserId == c.EmployeeUserId && x.Deleted == null
                && x.CreatedAt >= monthStart && x.CreatedAt < monthStart.AddMonths(1));
        var penalty = await db.PenaltySettings.AsNoTracking().Where(p => p.StoreId == storeId).Select(p => (decimal?)p.ForgotCheckPenalty).FirstOrDefaultAsync();
        return Ok(AppResponse<object>.Success(new
        {
            request = new
            {
                id = c.Id, c.EmployeeName, c.EmployeeCode, action = (int)c.Action, c.OldDate, oldTime = c.OldTime?.ToString(@"hh\:mm"),
                c.NewDate, newTime = c.NewTime?.ToString(@"hh\:mm"), c.NewPunchType, c.OldDevice, c.Reason, status = (int)c.Status,
                c.TotalApprovalLevels, c.CurrentApprovalStep, c.CreatedAt,
                approvals = c.ApprovalRecords.OrderBy(a => a.StepOrder).Select(a => new { a.StepOrder, a.StepName, a.AssignedUserName, status = a.Status.ToString() }),
            },
            employee = emp == null ? null : new { id = emp.Id, name = (emp.LastName + " " + emp.FirstName).Trim(), emp.EmployeeCode, emp.Department, emp.PhotoUrl },
            shift,
            logs,
            requestsThisMonth = monthCount,
            forgotCheckPenalty = penalty ?? 0,
        }));
    }

    /// <summary>Duyệt yêu cầu bổ sung/sửa công và tạo phiếu phạt «quên chấm công» (đã duyệt, trừ lương) — một lần.</summary>
    [HttpPost("corrections/{id:guid}/approve-and-fine")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.Approve, "AttendanceApproval", "AttendanceCorrection")]
    public async Task<ActionResult<AppResponse<object>>> ApproveAndFine(Guid id, [FromBody] ApproveAndFineRequest request)
    {
        var storeId = RequiredStoreId;
        var c = await db.AttendanceCorrectionRequests.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId);
        if (c == null) return Ok(AppResponse<object>.Fail("Không tìm thấy yêu cầu"));
        var emp = await db.Employees.AsNoTracking()
            .FirstOrDefaultAsync(e => e.StoreId == storeId && (e.ApplicationUserId == c.EmployeeUserId || e.Id == c.EmployeeUserId));
        if (emp == null) return Ok(AppResponse<object>.Fail("Không xác định được hồ sơ nhân viên để lập phiếu phạt"));
        var amount = request.Amount ?? await db.PenaltySettings.AsNoTracking()
            .Where(p => p.StoreId == storeId).Select(p => (decimal?)p.ForgotCheckPenalty).FirstOrDefaultAsync() ?? 0;
        if (amount <= 0) return Ok(AppResponse<object>.Fail("Mức phạt «Quên chấm công» chưa cài đặt (0đ)"));

        var result = await mediator.Send(new ApproveAttendanceCorrectionCommand(storeId, id, CurrentUserId, true, request.Note));
        if (!result.IsSuccess) return Ok(AppResponse<object>.Fail(result.Message));

        var after = await db.AttendanceCorrectionRequests.AsNoTracking().Where(x => x.Id == id).Select(x => x.Status).FirstAsync();
        if (after != CorrectionStatus.Approved)
            return Ok(AppResponse<object>.Success(new { approved = true, fined = false, message = "Đã duyệt cấp này; yêu cầu còn chờ cấp duyệt tiếp — chưa lập phiếu phạt." }));

        var violationDate = (c.NewDate ?? c.OldDate ?? DateTime.Today).Date;
        var ticket = await CreateForgotCheckTicketAsync(storeId, emp, amount, violationDate,
            $"Quên chấm công — duyệt yêu cầu bổ sung chấm công ({c.EmployeeName})");
        return Ok(AppResponse<object>.Success(new { approved = true, fined = true, ticketCode = ticket.TicketCode, amount }));
    }

    private async Task<PenaltyTicket> CreateForgotCheckTicketAsync(Guid storeId, Employee emp, decimal amount, DateTime date, string description)
    {
        var prefix = $"PP-{date:yyyyMMdd}-";
        PenaltyTicket? ticket = null;
        for (var attempt = 0; attempt < 3; attempt++)
        {
            var count = await db.PenaltyTickets.IgnoreQueryFilters().CountAsync(pt => pt.TicketCode.StartsWith(prefix) && pt.StoreId == storeId);
            ticket = new PenaltyTicket
            {
                Id = Guid.NewGuid(),
                TicketCode = $"{prefix}{count + 1 + attempt:D4}",
                EmployeeId = emp.Id,
                Type = PenaltyTicketType.ForgotCheck,
                Status = PenaltyTicketStatus.Approved,
                Amount = amount,
                ViolationDate = date,
                PenaltyTier = 1,
                Description = description,
                CollectionMethod = null,
                ProcessedById = CurrentUserId,
                ProcessedDate = DateTime.UtcNow,
                StoreId = storeId,
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow,
            };
            db.PenaltyTickets.Add(ticket);
            try
            {
                await db.SaveChangesAsync();
                break;
            }
            catch (DbUpdateException ex) when (attempt < 2)
            {
                logger.LogWarning(ex, "Ticket code clash {Code}, retry", ticket.TicketCode);
                db.Entry(ticket).State = EntityState.Detached;
            }
        }
        try
        {
            if (emp.ApplicationUserId != null && emp.ApplicationUserId != CurrentUserId)
                await notifications.CreateAndSendAsync(emp.ApplicationUserId, NotificationType.Warning,
                    "Bạn có phiếu phạt mới",
                    $"Phiếu phạt {ticket!.TicketCode} — quên chấm công {date:dd/MM}: {amount:N0}đ (trừ lương).",
                    relatedEntityType: "PenaltyTicket", relatedEntityId: ticket.Id,
                    fromUserId: CurrentUserId, categoryCode: "penalty", storeId: storeId);
        }
        catch (Exception ex) { logger.LogWarning(ex, "Notify fine failed"); }
        return ticket!;
    }
}
