using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

// ─── DTOs ─────────────────────────────────────────────────────────────

/// <summary>Một khoản tiền của nhân viên (ứng lương, thưởng, phạt, công tác, phiếu quỹ) — dạng thống nhất.</summary>
public class HrFinItemDto
{
    /// <summary>advance / bonus / penalty / ticket / trip_advance / trip_settlement / cash</summary>
    public string Kind { get; set; } = "";
    public Guid Id { get; set; }
    public string? Code { get; set; }
    public Guid? EmployeeId { get; set; }
    public string EmployeeName { get; set; } = "";
    public string? EmployeeCode { get; set; }
    public string? PhotoUrl { get; set; }
    public string? Department { get; set; }
    public string Title { get; set; } = "";
    public string? Subtitle { get; set; }
    public decimal Amount { get; set; }
    /// <summary>in = công ty chi cho nhân viên; out = nhân viên nộp / bị trừ</summary>
    public string Direction { get; set; } = "in";
    public string Status { get; set; } = "";
    public DateTime Date { get; set; }
    /// <summary>approve / pay / resolve / null</summary>
    public string? Action { get; set; }
    public string? Settlement { get; set; }
    public List<string> Evidence { get; set; } = [];
    public int DisputeStatus { get; set; }
    public string? DisputeReason { get; set; }
    public string? DisputeResponse { get; set; }
    public Guid? CaseId { get; set; }
    public int? ForMonth { get; set; }
    public int? ForYear { get; set; }
    public int? InstallmentCount { get; set; }
}

public class HrFinSettingsDto
{
    public decimal? AdvanceLimitPercent { get; set; }
    public decimal? AdvanceLimitAmount { get; set; }
    public int? AdvanceMaxRequestsPerPeriod { get; set; }
    public int AdvanceMaxInstallments { get; set; } = 3;
    public string BonusDefaultSettlement { get; set; } = "salary";
    public string PenaltyDefaultSettlement { get; set; } = "salary";
    public int DisputeWindowDays { get; set; } = 7;
}

public class HrFinCreateRewardDto
{
    public Guid EmployeeId { get; set; }
    /// <summary>Bonus / Penalty</summary>
    public string Type { get; set; } = "Bonus";
    public decimal Amount { get; set; }
    public string? Description { get; set; }
    public string? Note { get; set; }
    public DateTime? Date { get; set; }
    public int? ForMonth { get; set; }
    public int? ForYear { get; set; }
    /// <summary>salary / cash (null = theo cài đặt)</summary>
    public string? Settlement { get; set; }
    public List<string>? EvidenceUrls { get; set; }
    public bool ApproveNow { get; set; }
}

public class HrFinDisputeDto
{
    public string Kind { get; set; } = "";
    public Guid Id { get; set; }
    public string Reason { get; set; } = "";
}

public class HrFinResolveDto
{
    public bool Accept { get; set; }
    public string? Response { get; set; }
}

public class HrFinEvidenceDto
{
    public List<string> Urls { get; set; } = [];
}

public class HrFinPayrollAdjDto
{
    public Guid EmployeeId { get; set; }
    public Guid? EmployeeUserId { get; set; }
    public string EmployeeName { get; set; } = "";
    public string? EmployeeCode { get; set; }
    public decimal Bonus { get; set; }
    public decimal Penalty { get; set; }
    public decimal TicketPenalty { get; set; }
    public decimal Advance { get; set; }
    public List<HrFinItemDto> Items { get; set; } = [];
}

/// <summary>
/// Tài chính nhân sự v2 — một cửa cho thu chi / ứng lương / thưởng / phạt / công tác phí:
/// tổng quan, hộp duyệt thống nhất, sổ tiền theo nhân viên, "Tiền của tôi", khiếu nại,
/// và nguồn cộng/trừ lương dùng chung cho bảng lương.
/// Thao tác duyệt/chi vẫn đi qua các API gốc (advancerequests, transactions, penaltytickets, business-trip).
/// </summary>
[ApiController]
[Route("api/hr-finance")]
public class HrFinanceController(
    ZKTecoDbContext db,
    IFileStorageService storage,
    ISystemNotificationService notifications,
    IModulePermissionService modulePermissionService,
    ILogger<HrFinanceController> logger) : AuthenticatedControllerBase
{
    private const long MaxFileBytes = 15 * 1024 * 1024;

    private sealed record Emp(Guid Id, Guid? UserId, string Name, string Code, string? Dept, string? Photo);

    private async Task<List<Emp>> EmployeesAsync()
    {
        var storeId = RequiredStoreId;
        return await db.Employees.AsNoTracking()
            .Where(e => e.StoreId == storeId)
            .Select(e => new Emp(e.Id, e.ApplicationUserId, (e.LastName + " " + e.FirstName).Trim(),
                e.EmployeeCode, e.Department, e.PhotoUrl))
            .ToListAsync();
    }

    private static (DateTime from, DateTime to) MonthRange(int? year, int? month)
    {
        var now = DateTime.Now;
        var y = year ?? now.Year;
        var m = month is >= 1 and <= 12 ? month.Value : now.Month;
        var from = new DateTime(y, m, 1);
        return (from, from.AddMonths(1));
    }

    private static List<string> ParseUrls(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return [];
        try { return JsonSerializer.Deserialize<List<string>>(json) ?? []; }
        catch { return []; }
    }

    private static string? ToJson(List<string>? urls)
    {
        var clean = urls?.Where(u => !string.IsNullOrWhiteSpace(u)).Select(u => u.Trim()).Distinct().Take(20).ToList();
        return clean == null || clean.Count == 0 ? null : JsonSerializer.Serialize(clean);
    }

    private static HrFinItemDto Fill(HrFinItemDto dto, Emp? e)
    {
        if (e == null) return dto;
        dto.EmployeeId = e.Id;
        dto.EmployeeName = e.Name;
        dto.EmployeeCode = e.Code;
        dto.PhotoUrl = e.Photo;
        dto.Department = e.Dept;
        return dto;
    }

    private static string TicketTypeText(PenaltyTicketType t) => t switch
    {
        PenaltyTicketType.Late => "Đi trễ",
        PenaltyTicketType.EarlyLeave => "Về sớm",
        PenaltyTicketType.ForgotCheck => "Quên chấm công",
        PenaltyTicketType.UnauthorizedLeave => "Nghỉ không phép",
        PenaltyTicketType.Violation => "Vi phạm nội quy",
        PenaltyTicketType.Repeat => "Tái phạm",
        _ => "Vi phạm",
    };

    private static bool IsApprovedTx(string status)
        => status.Equals("Completed", StringComparison.OrdinalIgnoreCase)
           || status.Equals("Approved", StringComparison.OrdinalIgnoreCase);

    /// <summary>Thưởng/phạt đã chi tiền mặt thì bảng lương bỏ qua (giữ quy tắc cũ của bảng lương).</summary>
    private static bool CountsInPayroll(PaymentTransaction t)
        => string.IsNullOrEmpty(t.PaymentMethod)
           || t.PaymentMethod.Equals(PaymentFinanceHelper.SalaryDisbursementMethod, StringComparison.OrdinalIgnoreCase);

    private HrFinItemDto TxItem(PaymentTransaction t, Emp? e)
    {
        var isBonus = t.Type == "Bonus";
        return Fill(new HrFinItemDto
        {
            Kind = isBonus ? "bonus" : "penalty",
            Id = t.Id,
            Title = string.IsNullOrWhiteSpace(t.Description) ? (isBonus ? "Thưởng" : "Phạt") : t.Description!,
            Subtitle = t.Note,
            Amount = Math.Abs(t.Amount),
            Direction = isBonus ? "in" : "out",
            Status = t.Status,
            Date = t.TransactionDate,
            Settlement = t.Settlement ?? (string.IsNullOrEmpty(t.PaymentMethod) ? null
                : CountsInPayroll(t) ? "salary" : "cash"),
            Evidence = ParseUrls(t.EvidenceUrls),
            DisputeStatus = t.DisputeStatus,
            DisputeReason = t.DisputeReason,
            DisputeResponse = t.DisputeResponse,
            ForMonth = t.ForMonth,
            ForYear = t.ForYear,
        }, e);
    }

    private static HrFinItemDto TicketItem(PenaltyTicket t, Emp? e) => Fill(new HrFinItemDto
    {
        Kind = "ticket",
        Id = t.Id,
        Code = t.TicketCode,
        Title = TicketTypeText(t.Type) + (t.MinutesLateOrEarly is > 0 ? $" {t.MinutesLateOrEarly} phút" : ""),
        Subtitle = t.Description,
        Amount = Math.Abs(t.Amount),
        Direction = "out",
        Status = t.Status.ToString(),
        Date = t.ViolationDate,
        Settlement = t.CollectionMethod == "Cash" ? "cash" : "salary",
        Evidence = ParseUrls(t.EvidenceUrls),
        DisputeStatus = t.DisputeStatus,
        DisputeReason = t.DisputeReason,
        DisputeResponse = t.DisputeResponse,
    }, e);

    private static HrFinItemDto AdvanceItem(AdvanceRequest a, Emp? e) => Fill(new HrFinItemDto
    {
        Kind = "advance",
        Id = a.Id,
        Title = "Ứng lương" + (string.IsNullOrWhiteSpace(a.Reason) ? "" : $" — {a.Reason}"),
        Subtitle = a.ForMonth.HasValue ? $"Trừ lương kỳ {a.ForMonth:D2}/{a.ForYear}"
            + (a.InstallmentCount > 1 ? $", góp {a.InstallmentCount} kỳ" : "") : null,
        Amount = a.ApprovedAmount ?? a.Amount,
        Direction = "in",
        Status = a.Status == AdvanceRequestStatus.Approved && a.IsPaid ? "Paid" : a.Status.ToString(),
        Date = a.PaidDate ?? a.RequestDate,
        ForMonth = a.ForMonth,
        ForYear = a.ForYear,
        InstallmentCount = Math.Max(1, a.InstallmentCount),
    }, e);

    private Emp? Find(Dictionary<Guid, Emp> byId, Dictionary<Guid, Emp> byUser, Guid? employeeId, Guid? userId)
    {
        if (employeeId.HasValue && byId.TryGetValue(employeeId.Value, out var e)) return e;
        if (userId.HasValue && byUser.TryGetValue(userId.Value, out var u)) return u;
        if (userId.HasValue && byId.TryGetValue(userId.Value, out var legacy)) return legacy;
        return null;
    }

    private sealed class Lookup
    {
        public required List<Emp> All { get; init; }
        public required Dictionary<Guid, Emp> ById { get; init; }
        public required Dictionary<Guid, Emp> ByUser { get; init; }
        public List<Guid> Ids => All.Select(x => x.Id).ToList();
        public List<Guid> UserIds => All.Where(x => x.UserId.HasValue).Select(x => x.UserId!.Value).ToList();
    }

    private async Task<Lookup> LookupAsync()
    {
        var all = await EmployeesAsync();
        return new Lookup
        {
            All = all,
            ById = all.ToDictionary(x => x.Id),
            ByUser = all.Where(x => x.UserId.HasValue).GroupBy(x => x.UserId!.Value).ToDictionary(g => g.Key, g => g.First()),
        };
    }

    private IQueryable<PaymentTransaction> RewardQuery(Lookup lk, Guid? onlyEmployee = null)
    {
        var ids = onlyEmployee.HasValue ? [onlyEmployee.Value] : lk.Ids;
        var uids = onlyEmployee.HasValue
            ? lk.ById.TryGetValue(onlyEmployee.Value, out var e) && e.UserId.HasValue ? [e.UserId.Value] : new List<Guid>()
            : lk.UserIds;
        return db.PaymentTransactions.AsNoTracking()
            .Where(t => (t.Type == "Bonus" || t.Type == "Penalty")
                && ((t.EmployeeId != null && ids.Contains(t.EmployeeId.Value))
                    || (t.EmployeeId == null && t.EmployeeUserId != null && uids.Contains(t.EmployeeUserId.Value))));
    }

    // ─── Cài đặt ─────────────────────────────────────────────────────

    [HttpGet("settings")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<HrFinSettingsDto>>> GetSettings()
    {
        var s = await HrFinanceSettingsHelper.GetAsync(db, RequiredStoreId);
        return Ok(AppResponse<HrFinSettingsDto>.Success(ToDto(s)));
    }

    private static HrFinSettingsDto ToDto(HrFinanceSettings s) => new()
    {
        AdvanceLimitPercent = s.AdvanceLimitPercent,
        AdvanceLimitAmount = s.AdvanceLimitAmount,
        AdvanceMaxRequestsPerPeriod = s.AdvanceMaxRequestsPerPeriod,
        AdvanceMaxInstallments = s.AdvanceMaxInstallments,
        BonusDefaultSettlement = s.BonusDefaultSettlement,
        PenaltyDefaultSettlement = s.PenaltyDefaultSettlement,
        DisputeWindowDays = s.DisputeWindowDays,
    };

    [HttpPut("settings")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.Edit, "AdvanceRequests", "BonusPenalty", "PenaltyTickets", "CashTransaction")]
    public async Task<ActionResult<AppResponse<HrFinSettingsDto>>> SaveSettings([FromBody] HrFinSettingsDto dto)
    {
        if (dto.AdvanceLimitPercent is < 0 or > 100)
            return Ok(AppResponse<HrFinSettingsDto>.Fail("Hạn mức % phải trong khoảng 0–100"));
        if (dto.AdvanceLimitAmount is < 0)
            return Ok(AppResponse<HrFinSettingsDto>.Fail("Hạn mức tiền không hợp lệ"));
        var storeId = RequiredStoreId;
        var s = await db.HrFinanceSettings.AsTracking().FirstOrDefaultAsync(x => x.StoreId == storeId);
        if (s == null)
        {
            s = new HrFinanceSettings { Id = Guid.NewGuid(), StoreId = storeId, CreatedAt = DateTime.UtcNow, IsActive = true };
            db.HrFinanceSettings.Add(s);
        }
        s.AdvanceLimitPercent = dto.AdvanceLimitPercent is > 0 ? dto.AdvanceLimitPercent : null;
        s.AdvanceLimitAmount = dto.AdvanceLimitAmount is > 0 ? dto.AdvanceLimitAmount : null;
        s.AdvanceMaxRequestsPerPeriod = dto.AdvanceMaxRequestsPerPeriod is > 0 ? dto.AdvanceMaxRequestsPerPeriod : null;
        s.AdvanceMaxInstallments = Math.Clamp(dto.AdvanceMaxInstallments, 1, 12);
        s.BonusDefaultSettlement = dto.BonusDefaultSettlement == "cash" ? "cash" : "salary";
        s.PenaltyDefaultSettlement = dto.PenaltyDefaultSettlement == "cash" ? "cash" : "salary";
        s.DisputeWindowDays = Math.Clamp(dto.DisputeWindowDays, 0, 60);
        s.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();
        return Ok(AppResponse<HrFinSettingsDto>.Success(ToDto(s)));
    }

    // ─── Tổng quan ───────────────────────────────────────────────────

    [HttpGet("summary")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireAnyModulePermission(ModulePermissionAction.View, "AdvanceRequests", "BonusPenalty", "PenaltyTickets", "CashTransaction", "Transaction")]
    public async Task<ActionResult<AppResponse<object>>> Summary([FromQuery] int? year, [FromQuery] int? month)
    {
        var (from, to) = MonthRange(year, month);
        var storeId = RequiredStoreId;
        var lk = await LookupAsync();

        var advances = await db.AdvanceRequests.AsNoTracking()
            .Where(a => a.StoreId == storeId && a.Status == AdvanceRequestStatus.Approved && a.IsPaid)
            .ToListAsync();
        var advancePaid = advances.Where(a => a.PaidDate >= from && a.PaidDate < to).Sum(a => a.ApprovedAmount ?? a.Amount);
        var advanceToDeduct = advances.Sum(a => a.InstallmentCount <= 0
            ? (a.PaidDate >= from && a.PaidDate < to ? a.ApprovedAmount ?? a.Amount : 0)
            : HrFinanceSettingsHelper.AdvanceDeductionForPeriod(a, from.Year, from.Month));

        var rewards = await RewardQuery(lk)
            .Where(t => t.TransactionDate >= from && t.TransactionDate < to && (t.Status == "Completed" || t.Status == "Approved"))
            .ToListAsync();
        var bonus = rewards.Where(t => t.Type == "Bonus").Sum(t => Math.Abs(t.Amount));
        var penalty = rewards.Where(t => t.Type == "Penalty").Sum(t => Math.Abs(t.Amount));

        var tickets = await db.PenaltyTickets.AsNoTracking()
            .Where(t => t.StoreId == storeId && t.ViolationDate >= from && t.ViolationDate < to
                && (t.Status == PenaltyTicketStatus.Approved || t.Status == PenaltyTicketStatus.AutoApproved))
            .Select(t => new { t.EmployeeId, t.Amount })
            .ToListAsync();
        var ticketTotal = tickets.Sum(t => Math.Abs(t.Amount));

        var tripAdvancePaid = await db.BusinessTripAdvanceClaims.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.IsPaid && c.PaidDate >= from && c.PaidDate < to)
            .SumAsync(c => (decimal?)c.Amount) ?? 0;
        var tripSettled = await db.BusinessTripSettlementClaims.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.Status == AdvanceRequestStatus.Approved
                && c.ApprovedDate >= from && c.ApprovedDate < to)
            .SumAsync(c => (decimal?)c.TotalAmount) ?? 0;

        var cash = await db.CashTransactions.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.IsActive && c.Status == CashTransactionStatus.Completed
                && c.TransactionDate >= from && c.TransactionDate < to)
            .Select(c => new { c.Type, c.Amount, c.TransactionDate })
            .ToListAsync();
        var cashIn = cash.Where(c => c.Type == CashTransactionType.Income).Sum(c => c.Amount);
        var cashOut = cash.Where(c => c.Type == CashTransactionType.Expense).Sum(c => c.Amount);
        var days = Enumerable.Range(0, (to - from).Days).Select(i => from.AddDays(i)).ToList();
        var daily = days.Select(d => new
        {
            date = d,
            cashIn = cash.Where(c => c.Type == CashTransactionType.Income && c.TransactionDate.Date == d).Sum(c => c.Amount),
            cashOut = cash.Where(c => c.Type == CashTransactionType.Expense && c.TransactionDate.Date == d).Sum(c => c.Amount),
        }).ToList();

        var inbox = await BuildInboxAsync(lk);

        var perEmp = new Dictionary<Guid, (decimal bonus, decimal penalty)>();
        foreach (var t in rewards)
        {
            var e = Find(lk.ById, lk.ByUser, t.EmployeeId, t.EmployeeUserId);
            if (e == null) continue;
            var cur = perEmp.GetValueOrDefault(e.Id);
            perEmp[e.Id] = t.Type == "Bonus" ? (cur.bonus + Math.Abs(t.Amount), cur.penalty) : (cur.bonus, cur.penalty + Math.Abs(t.Amount));
        }
        foreach (var t in tickets)
        {
            var cur = perEmp.GetValueOrDefault(t.EmployeeId);
            perEmp[t.EmployeeId] = (cur.bonus, cur.penalty + Math.Abs(t.Amount));
        }
        var topEmployees = perEmp
            .Where(kv => lk.ById.ContainsKey(kv.Key))
            .Select(kv => new { employeeId = kv.Key, name = lk.ById[kv.Key].Name, bonus = kv.Value.bonus, penalty = kv.Value.penalty })
            .OrderByDescending(x => x.bonus + x.penalty).Take(10).ToList();

        return Ok(AppResponse<object>.Success(new
        {
            year = from.Year,
            month = from.Month,
            advancePaid,
            advanceToDeduct,
            bonus,
            penalty = penalty + ticketTotal,
            manualPenalty = penalty,
            ticketPenalty = ticketTotal,
            tripAdvancePaid,
            tripSettled,
            cashIn,
            cashOut,
            inboxCount = inbox.Count,
            disputeCount = inbox.Count(i => i.Action == "resolve"),
            awaitingPayCount = inbox.Count(i => i.Action == "pay"),
            awaitingPayAmount = inbox.Where(i => i.Action == "pay").Sum(i => i.Amount),
            breakdown = new[]
            {
                new { label = "Ứng lương", amount = advancePaid },
                new { label = "Thưởng", amount = bonus },
                new { label = "Ứng công tác", amount = tripAdvancePaid },
                new { label = "Quyết toán công tác", amount = tripSettled },
            },
            daily,
            topEmployees,
        }));
    }

    // ─── Hộp duyệt thống nhất ─────────────────────────────────────────

    [HttpGet("inbox")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireAnyModulePermission(ModulePermissionAction.View, "AdvanceRequests", "BonusPenalty", "PenaltyTickets", "CashTransaction", "Transaction")]
    public async Task<ActionResult<AppResponse<List<HrFinItemDto>>>> Inbox()
    {
        var lk = await LookupAsync();
        return Ok(AppResponse<List<HrFinItemDto>>.Success(await BuildInboxAsync(lk)));
    }

    private async Task<List<HrFinItemDto>> BuildInboxAsync(Lookup lk)
    {
        var storeId = RequiredStoreId;
        var items = new List<HrFinItemDto>();

        var advances = await db.AdvanceRequests.AsNoTracking()
            .Where(a => a.StoreId == storeId
                && (a.Status == AdvanceRequestStatus.Pending || (a.Status == AdvanceRequestStatus.Approved && !a.IsPaid)))
            .OrderByDescending(a => a.RequestDate).Take(300).ToListAsync();
        foreach (var a in advances)
        {
            var it = AdvanceItem(a, Find(lk.ById, lk.ByUser, a.EmployeeId, a.EmployeeUserId));
            it.Action = a.Status == AdvanceRequestStatus.Pending ? "approve" : "pay";
            items.Add(it);
        }

        var rewards = await RewardQuery(lk)
            .Where(t => t.Status == "Pending" || t.DisputeStatus == 1)
            .OrderByDescending(t => t.TransactionDate).Take(300).ToListAsync();
        foreach (var t in rewards)
        {
            var it = TxItem(t, Find(lk.ById, lk.ByUser, t.EmployeeId, t.EmployeeUserId));
            it.Action = t.DisputeStatus == 1 ? "resolve" : "approve";
            items.Add(it);
        }

        var tickets = await db.PenaltyTickets.AsNoTracking()
            .Where(t => t.StoreId == storeId && (t.Status == PenaltyTicketStatus.Pending
                || (t.DisputeStatus == 1 && t.Status != PenaltyTicketStatus.Cancelled)))
            .OrderByDescending(t => t.ViolationDate).Take(300).ToListAsync();
        foreach (var t in tickets)
        {
            var it = TicketItem(t, lk.ById.GetValueOrDefault(t.EmployeeId));
            it.Action = t.DisputeStatus == 1 ? "resolve" : "approve";
            items.Add(it);
        }

        var tripAdv = await (from c in db.BusinessTripAdvanceClaims.AsNoTracking()
                             join k in db.BusinessTripCases.AsNoTracking() on c.CaseId equals k.Id
                             where c.StoreId == storeId
                                   && (c.Status == AdvanceRequestStatus.Pending || (c.Status == AdvanceRequestStatus.Approved && !c.IsPaid))
                             select new { c, k.CaseCode, k.Title, k.EmployeeId, k.EmployeeUserId })
            .Take(200).ToListAsync();
        foreach (var x in tripAdv)
        {
            items.Add(Fill(new HrFinItemDto
            {
                Kind = "trip_advance",
                Id = x.c.Id,
                Code = x.CaseCode,
                CaseId = x.c.CaseId,
                Title = "Ứng công tác — " + x.Title,
                Subtitle = x.c.Reason,
                Amount = x.c.Amount,
                Direction = "in",
                Status = x.c.Status.ToString(),
                Date = x.c.RequestDate,
                Action = x.c.Status == AdvanceRequestStatus.Pending ? "approve" : "pay",
            }, Find(lk.ById, lk.ByUser, x.EmployeeId, x.EmployeeUserId)));
        }

        var tripSet = await (from c in db.BusinessTripSettlementClaims.AsNoTracking()
                             join k in db.BusinessTripCases.AsNoTracking() on c.CaseId equals k.Id
                             where c.StoreId == storeId
                                   && (c.Status == AdvanceRequestStatus.Pending
                                       || (c.Status == AdvanceRequestStatus.Approved
                                           && c.SettlementType == BusinessTripSettlementType.PayExtra && !c.IsExtraPaid))
                             select new { c, k.CaseCode, k.Title, k.EmployeeId, k.EmployeeUserId })
            .Take(200).ToListAsync();
        foreach (var x in tripSet)
        {
            var pending = x.c.Status == AdvanceRequestStatus.Pending;
            items.Add(Fill(new HrFinItemDto
            {
                Kind = "trip_settlement",
                Id = x.c.Id,
                Code = x.CaseCode,
                CaseId = x.c.CaseId,
                Title = "Quyết toán công tác — " + x.Title,
                Subtitle = $"Tổng chi {x.c.TotalAmount:N0}đ, đã ứng {x.c.AdvanceAmount:N0}đ",
                Amount = pending ? x.c.TotalAmount : Math.Abs(x.c.BalanceAmount),
                Direction = "in",
                Status = x.c.Status.ToString(),
                Date = x.c.SubmittedAt ?? x.c.CreatedAt,
                Action = pending ? "approve" : "pay",
            }, Find(lk.ById, lk.ByUser, x.EmployeeId, x.EmployeeUserId)));
        }

        // Phiếu quỹ chờ chi/thu chưa có chứng từ gốc hiển thị ở trên (thưởng/phạt tiền mặt, phiếu thủ công…)
        var coveredSources = new[] { PaymentFinanceHelper.SourceAdvance, PaymentFinanceHelper.SourceTripAdvance, PaymentFinanceHelper.SourceTripSettlement };
        var cash = await db.CashTransactions.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.IsActive
                && (c.Status == CashTransactionStatus.Pending || c.Status == CashTransactionStatus.WaitingPayment)
                && (c.SourceType == null || !coveredSources.Contains(c.SourceType))
                && (c.InternalNote == null || !(c.InternalNote.Contains("ứng lương #") || c.InternalNote.Contains("công tác")))
                && c.EmployeeId != null)
            .OrderByDescending(c => c.TransactionDate).Take(200).ToListAsync();
        foreach (var c in cash)
        {
            items.Add(Fill(new HrFinItemDto
            {
                Kind = "cash",
                Id = c.Id,
                Code = c.TransactionCode,
                Title = c.Description ?? c.TransactionCode,
                Subtitle = c.ContactName,
                Amount = c.Amount,
                Direction = c.Type == CashTransactionType.Expense ? "in" : "out",
                Status = c.Status.ToString(),
                Date = c.TransactionDate,
                Action = "pay",
                Evidence = ParseAttachmentUrls(c.Attachments, c.ReceiptImageUrl),
            }, c.EmployeeId.HasValue ? lk.ById.GetValueOrDefault(c.EmployeeId.Value) : null));
        }

        return items.OrderBy(i => i.Action == "resolve" ? 0 : i.Action == "approve" ? 1 : 2)
            .ThenByDescending(i => i.Date).ToList();
    }

    private static List<string> ParseAttachmentUrls(string? json, string? receipt)
    {
        var list = new List<string>();
        if (!string.IsNullOrWhiteSpace(json))
        {
            try
            {
                using var doc = JsonDocument.Parse(json);
                foreach (var el in doc.RootElement.EnumerateArray())
                {
                    if (el.ValueKind == JsonValueKind.String) list.Add(el.GetString()!);
                    else if (el.TryGetProperty("url", out var u) && u.ValueKind == JsonValueKind.String) list.Add(u.GetString()!);
                }
            }
            catch { /* ignore */ }
        }
        if (!string.IsNullOrWhiteSpace(receipt) && !list.Contains(receipt)) list.Add(receipt);
        return list;
    }

    // ─── Ứng lương ────────────────────────────────────────────────────

    /// <summary>Ứng lương trong tháng (theo ngày xin hoặc kỳ trừ) + mọi yêu cầu còn chờ duyệt / chờ chi.</summary>
    [HttpGet("advances")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireAnyModulePermission(ModulePermissionAction.View, "AdvanceRequests", "AdvanceReport")]
    public async Task<ActionResult<AppResponse<List<HrFinItemDto>>>> Advances([FromQuery] int? year, [FromQuery] int? month)
    {
        var (from, to) = MonthRange(year, month);
        var storeId = RequiredStoreId;
        var lk = await LookupAsync();
        var list = await db.AdvanceRequests.AsNoTracking()
            .Where(a => a.StoreId == storeId
                && ((a.RequestDate >= from && a.RequestDate < to)
                    || (a.ForYear == from.Year && a.ForMonth == from.Month)
                    || (a.PaidDate >= from && a.PaidDate < to)
                    || a.Status == AdvanceRequestStatus.Pending
                    || (a.Status == AdvanceRequestStatus.Approved && !a.IsPaid)))
            .OrderByDescending(a => a.RequestDate).Take(1000).ToListAsync();
        var items = list.Select(a =>
        {
            var it = AdvanceItem(a, Find(lk.ById, lk.ByUser, a.EmployeeId, a.EmployeeUserId));
            it.Date = a.RequestDate;
            it.Action = a.Status == AdvanceRequestStatus.Pending ? "approve"
                : a.Status == AdvanceRequestStatus.Approved && !a.IsPaid ? "pay" : null;
            if (a.ApprovedAmount.HasValue && a.ApprovedAmount != a.Amount)
                it.Subtitle = $"Xin {a.Amount:N0}đ · duyệt {a.ApprovedAmount:N0}đ" + (it.Subtitle == null ? "" : $" · {it.Subtitle}");
            return it;
        }).ToList();
        return Ok(AppResponse<List<HrFinItemDto>>.Success(items));
    }

    // ─── Danh sách thưởng/phạt thống nhất ─────────────────────────────

    [HttpGet("rewards")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireAnyModulePermission(ModulePermissionAction.View, "BonusPenalty", "PenaltyTickets", "Transaction")]
    public async Task<ActionResult<AppResponse<List<HrFinItemDto>>>> Rewards(
        [FromQuery] int? year, [FromQuery] int? month, [FromQuery] string? kind, [FromQuery] Guid? employeeId)
    {
        var (from, to) = MonthRange(year, month);
        var lk = await LookupAsync();
        var storeId = RequiredStoreId;
        var items = new List<HrFinItemDto>();
        if (kind is null or "" or "bonus" or "penalty")
        {
            var q = RewardQuery(lk, employeeId).Where(t => t.TransactionDate >= from && t.TransactionDate < to);
            if (kind == "bonus") q = q.Where(t => t.Type == "Bonus");
            if (kind == "penalty") q = q.Where(t => t.Type == "Penalty");
            foreach (var t in await q.ToListAsync())
                items.Add(TxItem(t, Find(lk.ById, lk.ByUser, t.EmployeeId, t.EmployeeUserId)));
        }
        if (kind is null or "" or "penalty" or "ticket")
        {
            var q = db.PenaltyTickets.AsNoTracking()
                .Where(t => t.StoreId == storeId && t.ViolationDate >= from && t.ViolationDate < to);
            if (employeeId.HasValue) q = q.Where(t => t.EmployeeId == employeeId.Value);
            foreach (var t in await q.ToListAsync())
                items.Add(TicketItem(t, lk.ById.GetValueOrDefault(t.EmployeeId)));
        }
        return Ok(AppResponse<List<HrFinItemDto>>.Success(items.OrderByDescending(i => i.Date).ToList()));
    }

    /// <summary>Tạo nhanh phiếu thưởng / phạt (có bằng chứng, chọn trừ lương hay tiền mặt, có thể duyệt luôn).</summary>
    [HttpPost("rewards")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.Create, "BonusPenalty", "Transaction")]
    public async Task<ActionResult<AppResponse<HrFinItemDto>>> CreateReward([FromBody] HrFinCreateRewardDto dto)
    {
        if (dto.Amount <= 0) return Ok(AppResponse<HrFinItemDto>.Fail("Số tiền phải lớn hơn 0"));
        var type = dto.Type.Equals("Penalty", StringComparison.OrdinalIgnoreCase) ? "Penalty" : "Bonus";
        var storeId = RequiredStoreId;
        var emp = await db.Employees.AsNoTracking().FirstOrDefaultAsync(e => e.Id == dto.EmployeeId && e.StoreId == storeId);
        if (emp == null) return Ok(AppResponse<HrFinItemDto>.Fail("Không tìm thấy nhân viên"));

        var date = dto.Date ?? DateTime.Now;
        var tx = new PaymentTransaction
        {
            Id = Guid.NewGuid(),
            EmployeeId = emp.Id,
            EmployeeUserId = emp.ApplicationUserId,
            Type = type,
            Amount = Math.Abs(dto.Amount),
            Description = string.IsNullOrWhiteSpace(dto.Description) ? (type == "Bonus" ? "Thưởng" : "Phạt") : dto.Description.Trim(),
            Note = dto.Note,
            TransactionDate = date,
            ForMonth = dto.ForMonth ?? date.Month,
            ForYear = dto.ForYear ?? date.Year,
            Status = "Pending",
            PerformedById = CurrentUserId,
            Source = "manual",
            Settlement = dto.Settlement is "cash" or "salary" ? dto.Settlement : null,
            EvidenceUrls = ToJson(dto.EvidenceUrls),
            CreatedAt = DateTime.UtcNow,
            IsActive = true,
        };
        db.PaymentTransactions.Add(tx);
        await db.SaveChangesAsync();

        if (dto.ApproveNow)
        {
            var tracked = await db.PaymentTransactions.AsTracking().FirstAsync(t => t.Id == tx.Id);
            tracked.Status = "Completed";
            await db.SaveChangesAsync();
            var cashTx = await PaymentFinanceHelper.ApplyBonusPenaltyDisbursementOnApproveAsync(
                db, tracked, storeId, CurrentUserId, tracked.Settlement);
            if (cashTx != null)
            {
                try
                {
                    await CashTransactionNotificationHelper.NotifyOnCreatedAsync(
                        db, modulePermissionService, notifications, cashTx, CurrentUserId, storeId);
                }
                catch (Exception ex) { logger.LogWarning(ex, "HrFinance: notify cash failed"); }
            }
            tx = tracked;
        }

        try
        {
            if (emp.ApplicationUserId.HasValue && emp.ApplicationUserId != CurrentUserId)
                await notifications.CreateAndSendAsync(emp.ApplicationUserId, type == "Bonus" ? NotificationType.Success : NotificationType.Warning,
                    type == "Bonus" ? "Bạn có phiếu thưởng mới" : "Bạn có phiếu phạt mới",
                    $"{tx.Description}: {tx.Amount:N0}đ" + (tx.Status == "Completed" ? " (đã duyệt)" : " (chờ duyệt)"),
                    relatedEntityType: "PaymentTransaction", relatedEntityId: tx.Id,
                    fromUserId: CurrentUserId, categoryCode: "payroll", storeId: storeId);
        }
        catch (Exception ex) { logger.LogWarning(ex, "HrFinance: notify reward failed"); }

        var lk = await LookupAsync();
        return Ok(AppResponse<HrFinItemDto>.Success(TxItem(tx, lk.ById.GetValueOrDefault(emp.Id))));
    }

    [HttpPut("evidence/{kind}/{id:guid}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.Edit, "BonusPenalty", "PenaltyTickets", "Transaction", "CashTransaction")]
    public async Task<ActionResult<AppResponse<bool>>> SetEvidence(string kind, Guid id, [FromBody] HrFinEvidenceDto dto)
    {
        var json = ToJson(dto.Urls);
        var storeId = RequiredStoreId;
        switch (kind)
        {
            case "bonus" or "penalty":
                var tx = await db.PaymentTransactions.AsTracking().FirstOrDefaultAsync(t => t.Id == id);
                if (tx == null) return Ok(AppResponse<bool>.Fail("Không tìm thấy phiếu"));
                tx.EvidenceUrls = json;
                break;
            case "ticket":
                var t2 = await db.PenaltyTickets.AsTracking().FirstOrDefaultAsync(t => t.Id == id && t.StoreId == storeId);
                if (t2 == null) return Ok(AppResponse<bool>.Fail("Không tìm thấy phiếu phạt"));
                t2.EvidenceUrls = json;
                break;
            case "cash":
                var c = await db.CashTransactions.AsTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId);
                if (c == null) return Ok(AppResponse<bool>.Fail("Không tìm thấy phiếu quỹ"));
                c.Attachments = json;
                break;
            default:
                return Ok(AppResponse<bool>.Fail("Loại chứng từ không hỗ trợ"));
        }
        await db.SaveChangesAsync();
        return Ok(AppResponse<bool>.Success(true));
    }

    [HttpPost("upload")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequestSizeLimit(MaxFileBytes * 6)]
    public async Task<ActionResult<AppResponse<List<string>>>> Upload([FromForm] List<IFormFile> files)
    {
        var urls = new List<string>();
        var code = await db.Stores.AsNoTracking().Where(s => s.Id == RequiredStoreId).Select(s => s.Code).FirstOrDefaultAsync();
        var folder = string.IsNullOrEmpty(code) ? "uploads/hr-finance" : $"stores/{code}/uploads/hr-finance";
        foreach (var f in files.Take(5))
        {
            if (f.Length == 0 || f.Length > MaxFileBytes) continue;
            var name = Path.GetFileName(f.FileName);
            var ext = Path.GetExtension(name).ToLowerInvariant();
            var kind = CommDocumentReader.KindOf(name);
            if (kind != "image" && ext != ".pdf") continue;
            if (!CommDocumentReader.MimeByExt.ContainsKey(ext)) continue;
            using var ms = new MemoryStream();
            await f.CopyToAsync(ms);
            var data = ms.ToArray();
            if (!CommDocumentReader.MagicMatches(data, name)) continue;
            string stored;
            if (kind == "image" && ext != ".gif")
            {
                var (optimized, uploadName, _) = await ImageOptimizeHelper.OptimizeAsync(new MemoryStream(data), name,
                    ImageOptimizeHelper.PhotoMaxEdge, ImageOptimizeHelper.PhotoJpegQuality);
                await using (optimized) stored = await storage.UploadAsync(optimized, uploadName, folder);
            }
            else stored = await storage.UploadAsync(new MemoryStream(data), name, folder);
            urls.Add(storage.GetFileUrl(stored));
        }
        return Ok(urls.Count == 0
            ? AppResponse<List<string>>.Fail("Chỉ nhận ảnh hoặc PDF, tối đa 15 MB mỗi tệp")
            : AppResponse<List<string>>.Success(urls));
    }

    // ─── Sổ tiền theo nhân viên ───────────────────────────────────────

    [HttpGet("ledger")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireAnyModulePermission(ModulePermissionAction.View, "AdvanceRequests", "BonusPenalty", "PenaltyTickets", "CashTransaction", "Transaction")]
    public async Task<ActionResult<AppResponse<object>>> Ledger([FromQuery] Guid employeeId, [FromQuery] DateTime? from, [FromQuery] DateTime? to)
    {
        var lk = await LookupAsync();
        if (!lk.ById.ContainsKey(employeeId)) return Ok(AppResponse<object>.Fail("Không tìm thấy nhân viên"));
        return Ok(AppResponse<object>.Success(await BuildLedgerAsync(lk, employeeId,
            from ?? DateTime.Now.Date.AddMonths(-3), to ?? DateTime.Now.Date.AddDays(1))));
    }

    private async Task<object> BuildLedgerAsync(Lookup lk, Guid employeeId, DateTime from, DateTime to)
    {
        var emp = lk.ById[employeeId];
        var storeId = RequiredStoreId;
        var items = new List<HrFinItemDto>();

        var allAdvances = await db.AdvanceRequests.AsNoTracking()
            .Where(a => a.StoreId == storeId && (a.EmployeeId == employeeId || (a.EmployeeId == null && a.EmployeeUserId == emp.UserId)))
            .ToListAsync();
        items.AddRange(allAdvances
            .Where(a => (a.PaidDate ?? a.RequestDate) >= from && (a.PaidDate ?? a.RequestDate) < to)
            .Select(a => AdvanceItem(a, emp)));

        foreach (var t in await RewardQuery(lk, employeeId).Where(t => t.TransactionDate >= from && t.TransactionDate < to).ToListAsync())
            items.Add(TxItem(t, emp));
        foreach (var t in await db.PenaltyTickets.AsNoTracking()
                     .Where(t => t.StoreId == storeId && t.EmployeeId == employeeId && t.ViolationDate >= from && t.ViolationDate < to)
                     .ToListAsync())
            items.Add(TicketItem(t, emp));

        var cases = await db.BusinessTripCases.AsNoTracking()
            .Where(k => k.StoreId == storeId && (k.EmployeeId == employeeId || (k.EmployeeId == null && k.EmployeeUserId == emp.UserId)))
            .Select(k => new { k.Id, k.CaseCode, k.Title })
            .ToListAsync();
        var caseIds = cases.Select(c => c.Id).ToList();
        foreach (var c in await db.BusinessTripAdvanceClaims.AsNoTracking()
                     .Where(c => caseIds.Contains(c.CaseId) && c.RequestDate >= from && c.RequestDate < to).ToListAsync())
        {
            var k = cases.First(x => x.Id == c.CaseId);
            items.Add(Fill(new HrFinItemDto
            {
                Kind = "trip_advance", Id = c.Id, Code = k.CaseCode, CaseId = k.Id,
                Title = "Ứng công tác — " + k.Title, Amount = c.Amount, Direction = "in",
                Status = c.IsPaid ? "Paid" : c.Status.ToString(), Date = c.PaidDate ?? c.RequestDate,
            }, emp));
        }
        foreach (var c in await db.BusinessTripSettlementClaims.AsNoTracking()
                     .Where(c => caseIds.Contains(c.CaseId) && (c.SubmittedAt ?? c.CreatedAt) >= from && (c.SubmittedAt ?? c.CreatedAt) < to).ToListAsync())
        {
            var k = cases.First(x => x.Id == c.CaseId);
            items.Add(Fill(new HrFinItemDto
            {
                Kind = "trip_settlement", Id = c.Id, Code = k.CaseCode, CaseId = k.Id,
                Title = "Quyết toán công tác — " + k.Title,
                Subtitle = $"Tổng chi {c.TotalAmount:N0}đ, đã ứng {c.AdvanceAmount:N0}đ",
                Amount = c.TotalAmount, Direction = "in",
                Status = c.Status.ToString(), Date = c.ApprovedDate ?? c.SubmittedAt ?? c.CreatedAt,
            }, emp));
        }

        // Dư nợ ứng lương còn phải trừ ở các kỳ sau tháng hiện tại
        var now = DateTime.Now;
        decimal outstanding = 0;
        foreach (var a in allAdvances.Where(a => a.Status == AdvanceRequestStatus.Approved && a.IsPaid && a.InstallmentCount > 0))
        {
            var n = Math.Max(1, a.InstallmentCount);
            var y = a.ForYear ?? now.Year;
            var m = a.ForMonth ?? now.Month;
            for (var i = 0; i < n; i++)
            {
                var d = new DateTime(y, m, 1).AddMonths(i);
                if (d.Year * 12 + d.Month >= now.Year * 12 + now.Month)
                    outstanding += HrFinanceSettingsHelper.AdvanceDeductionForPeriod(a, d.Year, d.Month);
            }
        }

        bool Ok(HrFinItemDto i) => i.Status is "Completed" or "Approved" or "AutoApproved" or "Paid";
        var list = items.OrderByDescending(i => i.Date).ToList();
        return new
        {
            employee = new { id = emp.Id, name = emp.Name, code = emp.Code, department = emp.Dept, photoUrl = emp.Photo },
            from,
            to,
            received = list.Where(i => Ok(i) && i.Direction == "in" && i.Kind != "trip_settlement").Sum(i => i.Amount),
            deducted = list.Where(i => Ok(i) && i.Direction == "out").Sum(i => i.Amount),
            bonus = list.Where(i => Ok(i) && i.Kind == "bonus").Sum(i => i.Amount),
            penalty = list.Where(i => Ok(i) && i.Kind is "penalty" or "ticket").Sum(i => i.Amount),
            advance = list.Where(i => i.Kind == "advance" && i.Status == "Paid").Sum(i => i.Amount),
            advanceOutstanding = outstanding,
            items = list,
        };
    }

    // ─── Tiền của tôi ─────────────────────────────────────────────────

    [HttpGet("me")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<object>>> Me([FromQuery] int? year, [FromQuery] int? month)
    {
        var lk = await LookupAsync();
        var me = lk.ByUser.GetValueOrDefault(CurrentUserId);
        if (me == null) return Ok(AppResponse<object>.Fail("Tài khoản chưa gắn hồ sơ nhân viên"));
        var (from, to) = MonthRange(year, month);
        var settings = await HrFinanceSettingsHelper.GetAsync(db, RequiredStoreId);
        var monthly = await HrFinanceSettingsHelper.EstimateMonthlySalaryAsync(db, me.Id, to.AddDays(-1));
        var limit = HrFinanceSettingsHelper.AdvanceLimit(settings, monthly);
        var active = await db.AdvanceRequests.AsNoTracking()
            .Where(a => a.EmployeeId == me.Id && (a.Status == AdvanceRequestStatus.Pending || a.Status == AdvanceRequestStatus.Approved))
            .ToListAsync();
        var used = active.Sum(a => HrFinanceSettingsHelper.AdvanceDeductionForPeriod(a, from.Year, from.Month));
        var ledger = await BuildLedgerAsync(lk, me.Id, from, to);
        return Ok(AppResponse<object>.Success(new
        {
            year = from.Year,
            month = from.Month,
            advanceLimit = new
            {
                monthlySalary = monthly,
                limit,
                used,
                remaining = limit.HasValue ? Math.Max(0, limit.Value - used) : (decimal?)null,
                maxInstallments = settings.AdvanceMaxInstallments,
                limitPercent = settings.AdvanceLimitPercent,
            },
            disputeWindowDays = settings.DisputeWindowDays,
            ledger,
        }));
    }

    [HttpPost("me/dispute")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<bool>>> Dispute([FromBody] HrFinDisputeDto dto)
    {
        if (string.IsNullOrWhiteSpace(dto.Reason) || dto.Reason.Trim().Length < 5)
            return Ok(AppResponse<bool>.Fail("Vui lòng nêu lý do khiếu nại (ít nhất 5 ký tự)"));
        var lk = await LookupAsync();
        var me = lk.ByUser.GetValueOrDefault(CurrentUserId);
        if (me == null) return Ok(AppResponse<bool>.Fail("Tài khoản chưa gắn hồ sơ nhân viên"));
        var settings = await HrFinanceSettingsHelper.GetAsync(db, RequiredStoreId);
        var deadline = DateTime.Now.AddDays(-Math.Max(0, settings.DisputeWindowDays));
        Guid? notifyUser;
        string label;

        if (dto.Kind == "ticket")
        {
            var t = await db.PenaltyTickets.AsTracking().FirstOrDefaultAsync(x => x.Id == dto.Id && x.EmployeeId == me.Id);
            if (t == null) return Ok(AppResponse<bool>.Fail("Không tìm thấy phiếu phạt của bạn"));
            if (t.Status == PenaltyTicketStatus.Cancelled) return Ok(AppResponse<bool>.Fail("Phiếu đã hủy"));
            if (t.DisputeStatus != 0) return Ok(AppResponse<bool>.Fail("Phiếu này đã được khiếu nại"));
            if (settings.DisputeWindowDays > 0 && t.ViolationDate < deadline.Date)
                return Ok(AppResponse<bool>.Fail($"Đã quá hạn khiếu nại ({settings.DisputeWindowDays} ngày)"));
            t.DisputeStatus = 1; t.DisputeReason = dto.Reason.Trim(); t.DisputedAt = DateTime.UtcNow;
            notifyUser = t.ProcessedById;
            label = $"phiếu phạt {t.TicketCode} ({t.Amount:N0}đ)";
        }
        else if (dto.Kind == "penalty")
        {
            var t = await db.PaymentTransactions.AsTracking().FirstOrDefaultAsync(x => x.Id == dto.Id && x.Type == "Penalty"
                && (x.EmployeeId == me.Id || (x.EmployeeId == null && x.EmployeeUserId == CurrentUserId)));
            if (t == null) return Ok(AppResponse<bool>.Fail("Không tìm thấy phiếu phạt của bạn"));
            if (t.Status == "Cancelled") return Ok(AppResponse<bool>.Fail("Phiếu đã hủy"));
            if (t.DisputeStatus != 0) return Ok(AppResponse<bool>.Fail("Phiếu này đã được khiếu nại"));
            if (settings.DisputeWindowDays > 0 && t.TransactionDate < deadline.Date)
                return Ok(AppResponse<bool>.Fail($"Đã quá hạn khiếu nại ({settings.DisputeWindowDays} ngày)"));
            t.DisputeStatus = 1; t.DisputeReason = dto.Reason.Trim(); t.DisputedAt = DateTime.UtcNow;
            notifyUser = t.PerformedById;
            label = $"phiếu phạt \"{t.Description}\" ({Math.Abs(t.Amount):N0}đ)";
        }
        else return Ok(AppResponse<bool>.Fail("Chỉ khiếu nại được phiếu phạt"));

        await db.SaveChangesAsync();
        try
        {
            if (notifyUser.HasValue && notifyUser != CurrentUserId)
                await notifications.CreateAndSendAsync(notifyUser, NotificationType.Warning,
                    "Nhân viên khiếu nại phiếu phạt",
                    $"{me.Name} khiếu nại {label}: {dto.Reason.Trim()}",
                    relatedEntityType: "HrFinanceDispute", relatedEntityId: dto.Id,
                    fromUserId: CurrentUserId, categoryCode: "penalty", storeId: RequiredStoreId);
        }
        catch (Exception ex) { logger.LogWarning(ex, "HrFinance: notify dispute failed"); }
        return Ok(AppResponse<bool>.Success(true));
    }

    [HttpPost("disputes/{kind}/{id:guid}/resolve")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.Approve, "BonusPenalty", "PenaltyTickets", "Transaction")]
    public async Task<ActionResult<AppResponse<bool>>> Resolve(string kind, Guid id, [FromBody] HrFinResolveDto dto)
    {
        var storeId = RequiredStoreId;
        Guid? employeeUser;
        string label;
        if (kind == "ticket")
        {
            var t = await db.PenaltyTickets.AsTracking().Include(x => x.Employee)
                .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId);
            if (t == null || t.DisputeStatus != 1) return Ok(AppResponse<bool>.Fail("Không có khiếu nại đang chờ"));
            t.DisputeStatus = dto.Accept ? 2 : 3;
            t.DisputeResponse = dto.Response?.Trim();
            if (dto.Accept)
            {
                t.Status = PenaltyTicketStatus.Cancelled;
                t.CancellationReason = "Chấp nhận khiếu nại" + (string.IsNullOrWhiteSpace(dto.Response) ? "" : $": {dto.Response!.Trim()}");
                t.ProcessedById = CurrentUserId;
                t.ProcessedDate = DateTime.UtcNow;
                var cash = await PenaltyTicketFinanceHelper.ResolveLinkedCashTransactionAsync(db, t);
                if (cash != null && !cash.IsPaid)
                {
                    db.Attach(cash);
                    PenaltyTicketFinanceHelper.CancelLinkedCashTransaction(cash, "Hủy do chấp nhận khiếu nại");
                    db.Update(cash);
                }
            }
            employeeUser = t.Employee?.ApplicationUserId;
            label = $"phiếu phạt {t.TicketCode}";
        }
        else if (kind == "penalty")
        {
            var t = await db.PaymentTransactions.AsTracking().FirstOrDefaultAsync(x => x.Id == id);
            if (t == null || t.DisputeStatus != 1) return Ok(AppResponse<bool>.Fail("Không có khiếu nại đang chờ"));
            t.DisputeStatus = dto.Accept ? 2 : 3;
            t.DisputeResponse = dto.Response?.Trim();
            if (dto.Accept)
            {
                var linked = await PaymentFinanceHelper.ResolveLinkedAsync(db, storeId, PaymentFinanceHelper.BonusPenaltyNote(t.Id));
                PaymentFinanceHelper.ClearSalaryDisbursementOnUnapprove(t, linked);
                t.Status = "Cancelled";
                if (linked != null && !linked.IsPaid)
                {
                    PaymentFinanceHelper.CancelLinkedCashTransaction(linked, "Hủy do chấp nhận khiếu nại");
                    if (db.Entry(linked).State == EntityState.Detached) db.Update(linked);
                }
            }
            employeeUser = t.EmployeeUserId;
            label = $"phiếu phạt \"{t.Description}\"";
        }
        else return Ok(AppResponse<bool>.Fail("Loại phiếu không hỗ trợ"));

        await db.SaveChangesAsync();
        try
        {
            if (employeeUser.HasValue)
                await notifications.CreateAndSendAsync(employeeUser, dto.Accept ? NotificationType.Success : NotificationType.Info,
                    dto.Accept ? "Khiếu nại được chấp nhận" : "Khiếu nại không được chấp nhận",
                    $"Khiếu nại {label}: " + (dto.Accept ? "phiếu đã được hủy." : "giữ nguyên phiếu.")
                    + (string.IsNullOrWhiteSpace(dto.Response) ? "" : $" Phản hồi: {dto.Response!.Trim()}"),
                    relatedEntityType: "HrFinanceDispute", relatedEntityId: id,
                    fromUserId: CurrentUserId, categoryCode: "penalty", storeId: storeId);
        }
        catch (Exception ex) { logger.LogWarning(ex, "HrFinance: notify resolve failed"); }
        return Ok(AppResponse<bool>.Success(true));
    }

    // ─── Nguồn cộng/trừ cho bảng lương ────────────────────────────────

    /// <summary>
    /// Các khoản cộng/trừ lương của kỳ [from, to]: thưởng/phạt (trừ khoản đã chi/thu tiền mặt),
    /// phiếu phạt trừ lương đã duyệt, ứng lương đã chi (theo kỳ trừ ForMonth, hỗ trợ trả góp).
    /// Kỳ lương = tháng của ngày cuối kỳ.
    /// </summary>
    [HttpGet("payroll-adjustments")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireAnyModulePermission(ModulePermissionAction.View, "Payroll", "PayrollSummary", "AdvanceRequests", "BonusPenalty", "Transaction")]
    public async Task<ActionResult<AppResponse<List<HrFinPayrollAdjDto>>>> PayrollAdjustments(
        [FromQuery] DateTime from, [FromQuery] DateTime to)
    {
        var lk = await LookupAsync();
        return Ok(AppResponse<List<HrFinPayrollAdjDto>>.Success(await ComputePayrollAdjustmentsAsync(db, RequiredStoreId, lk.All
            .Select(e => (e.Id, e.UserId, e.Name, e.Code)).ToList(), from, to)));
    }

    public static async Task<List<HrFinPayrollAdjDto>> ComputePayrollAdjustmentsAsync(
        ZKTecoDbContext db, Guid storeId, List<(Guid Id, Guid? UserId, string Name, string Code)> employees,
        DateTime from, DateTime to)
    {
        var fromD = from.Date;
        var toEnd = to.Date.AddDays(1).AddTicks(-1);
        var salaryYear = to.Year;
        var salaryMonth = to.Month;
        var byId = employees.ToDictionary(e => e.Id, e => new HrFinPayrollAdjDto
        {
            EmployeeId = e.Id, EmployeeUserId = e.UserId, EmployeeName = e.Name, EmployeeCode = e.Code,
        });
        var byUser = employees.Where(e => e.UserId.HasValue).GroupBy(e => e.UserId!.Value)
            .ToDictionary(g => g.Key, g => g.First().Id);
        HrFinPayrollAdjDto? Row(Guid? empId, Guid? userId)
        {
            if (empId.HasValue && byId.TryGetValue(empId.Value, out var r)) return r;
            if (userId.HasValue && byUser.TryGetValue(userId.Value, out var id)) return byId[id];
            if (userId.HasValue && byId.TryGetValue(userId.Value, out var legacy)) return legacy;
            return null;
        }

        var ids = byId.Keys.ToList();
        var uids = byUser.Keys.ToList();
        var txs = await db.PaymentTransactions.AsNoTracking()
            .Where(t => (t.Type == "Bonus" || t.Type == "Penalty")
                && (t.Status == "Completed" || t.Status == "Approved")
                && t.TransactionDate >= fromD && t.TransactionDate <= toEnd
                && ((t.EmployeeId != null && ids.Contains(t.EmployeeId.Value))
                    || (t.EmployeeUserId != null && (uids.Contains(t.EmployeeUserId.Value) || ids.Contains(t.EmployeeUserId.Value)))))
            .ToListAsync();
        foreach (var t in txs)
        {
            if (!CountsInPayroll(t)) continue;
            var r = Row(t.EmployeeId, t.EmployeeUserId);
            if (r == null) continue;
            var amt = Math.Abs(t.Amount);
            if (t.Type == "Bonus") r.Bonus += amt; else r.Penalty += amt;
            r.Items.Add(new HrFinItemDto
            {
                Kind = t.Type == "Bonus" ? "bonus" : "penalty", Id = t.Id, Title = t.Description ?? t.Type,
                Amount = amt, Direction = t.Type == "Bonus" ? "in" : "out", Status = t.Status, Date = t.TransactionDate,
            });
        }

        var tickets = await db.PenaltyTickets.AsNoTracking()
            .Where(t => t.StoreId == storeId
                && (t.Status == PenaltyTicketStatus.Approved || t.Status == PenaltyTicketStatus.AutoApproved)
                && (t.CollectionMethod == null || t.CollectionMethod != "Cash")
                && t.ViolationDate >= fromD && t.ViolationDate <= toEnd)
            .ToListAsync();
        foreach (var t in tickets)
        {
            if (!byId.TryGetValue(t.EmployeeId, out var r)) continue;
            var amt = Math.Abs(t.Amount);
            r.TicketPenalty += amt;
            r.Items.Add(new HrFinItemDto
            {
                Kind = "ticket", Id = t.Id, Code = t.TicketCode, Title = TicketTypeText(t.Type),
                Amount = amt, Direction = "out", Status = t.Status.ToString(), Date = t.ViolationDate,
            });
        }

        var advances = await db.AdvanceRequests.AsNoTracking()
            .Where(a => a.StoreId == storeId && a.Status == AdvanceRequestStatus.Approved && a.IsPaid)
            .ToListAsync();
        foreach (var a in advances)
        {
            var r = Row(a.EmployeeId, a.EmployeeUserId);
            if (r == null) continue;
            decimal amt;
            if (a.InstallmentCount <= 0 || a.ForMonth is null or < 1 or > 12 || a.ForYear == null)
                amt = a.PaidDate >= fromD && a.PaidDate <= toEnd ? a.ApprovedAmount ?? a.Amount : 0; // quy tắc cũ
            else
                amt = HrFinanceSettingsHelper.AdvanceDeductionForPeriod(a, salaryYear, salaryMonth);
            if (amt <= 0) continue;
            r.Advance += amt;
            r.Items.Add(new HrFinItemDto
            {
                Kind = "advance", Id = a.Id, Title = "Trừ ứng lương" + (a.InstallmentCount > 1 ? $" (góp {a.InstallmentCount} kỳ)" : ""),
                Amount = amt, Direction = "out", Status = "Paid", Date = a.PaidDate ?? a.RequestDate,
                ForMonth = a.ForMonth, ForYear = a.ForYear, InstallmentCount = Math.Max(1, a.InstallmentCount),
            });
        }

        return byId.Values.Where(r => r.Items.Count > 0).OrderBy(r => r.EmployeeName).ToList();
    }
}
