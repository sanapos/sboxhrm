using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class PenaltyTicketsController(
    ZKTecoDbContext dbContext,
    ISystemNotificationService notificationService,
    IAttendanceService attendanceService) : AuthenticatedControllerBase
{
    #region DTOs

    public class PenaltyTicketDto
    {
        public Guid Id { get; set; }
        public string TicketCode { get; set; } = string.Empty;
        public Guid EmployeeId { get; set; }
        public string EmployeeName { get; set; } = string.Empty;
        public string? EmployeeCode { get; set; }
        public string Type { get; set; } = string.Empty;
        public string Status { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public DateTime ViolationDate { get; set; }
        public int? MinutesLateOrEarly { get; set; }
        public string? ShiftStartTime { get; set; }
        public string? ShiftEndTime { get; set; }
        public DateTime? ActualPunchTime { get; set; }
        public int PenaltyTier { get; set; }
        public int? RepeatCountInMonth { get; set; }
        public string? Description { get; set; }
        public string? CancellationReason { get; set; }
        public Guid? ProcessedById { get; set; }
        public string? ProcessedByName { get; set; }
        public DateTime? ProcessedDate { get; set; }
        public Guid? CashTransactionId { get; set; }
        public string? CashTransactionCode { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class PenaltyTicketListResponse
    {
        public List<PenaltyTicketDto> Items { get; set; } = [];
        public int TotalCount { get; set; }
        public int Page { get; set; }
        public int PageSize { get; set; }
        public decimal TotalPendingAmount { get; set; }
        public decimal TotalApprovedAmount { get; set; }
    }

    public class CancelPenaltyRequest
    {
        public string? Reason { get; set; }
    }

    public class ApprovePenaltyRequest
    {
        public string? Note { get; set; }
    }

    public class CreatePenaltyTicketRequest
    {
        public Guid EmployeeId { get; set; }
        public string Type { get; set; } = "Violation";
        public decimal Amount { get; set; }
        public DateTime ViolationDate { get; set; }
        public int? MinutesLateOrEarly { get; set; }
        public string? Description { get; set; }
    }

    public class UpdatePenaltyTicketRequest
    {
        public string? Type { get; set; }
        public decimal? Amount { get; set; }
        public string? Description { get; set; }
    }

    public class PenaltyStatsSummary
    {
        public int TotalPending { get; set; }
        public int TotalApproved { get; set; }
        public int TotalAutoApproved { get; set; }
        public int TotalCancelled { get; set; }
        public decimal PendingAmount { get; set; }
        public decimal ApprovedAmount { get; set; }
    }

    #endregion

    /// <summary>
    /// Láº¥y danh sÃ¡ch phiáº¿u pháº¡t (cÃ³ phÃ¢n trang, lá»c)
    /// </summary>
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("PenaltyTickets", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<PenaltyTicketListResponse>>> GetPenaltyTickets(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] Guid? employeeId = null,
        [FromQuery] PenaltyTicketStatus? status = null,
        [FromQuery] PenaltyTicketType? type = null,
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null,
        [FromQuery] Guid? branchId = null,
        [FromQuery] bool includeChildBranches = true)
    {
        var storeId = RequiredStoreId;
        var query = dbContext.PenaltyTickets
            .Include(pt => pt.Employee)
            .Include(pt => pt.ProcessedBy)
            .Include(pt => pt.CashTransaction)
            .Where(pt => pt.StoreId == storeId && pt.Deleted == null)
            .AsQueryable();

        var branchScope = await BranchQueryHelper.ResolveEmployeeScopeAsync(
            dbContext, storeId, branchId, includeChildBranches);
        if (branchScope != null)
        {
            if (branchScope.IsEmpty)
            {
                return Ok(AppResponse<PenaltyTicketListResponse>.Success(new PenaltyTicketListResponse
                {
                    Page = page,
                    PageSize = pageSize
                }));
            }
            query = query.Where(pt => branchScope.EmployeeIds.Contains(pt.EmployeeId));
        }

        if (employeeId.HasValue)
            query = query.Where(pt => pt.EmployeeId == employeeId.Value);
        if (status.HasValue)
            query = query.Where(pt => pt.Status == status.Value);
        if (type.HasValue)
            query = query.Where(pt => pt.Type == type.Value);
        if (fromDate.HasValue)
            query = query.Where(pt => pt.ViolationDate >= fromDate.Value.Date);
        if (toDate.HasValue)
            query = query.Where(pt => pt.ViolationDate <= toDate.Value.Date);

        var totalCount = await query.CountAsync();

        var totalPending = await query.Where(pt => pt.Status == PenaltyTicketStatus.Pending).SumAsync(pt => pt.Amount);
        var totalApproved = await query.Where(pt => pt.Status == PenaltyTicketStatus.Approved || pt.Status == PenaltyTicketStatus.AutoApproved).SumAsync(pt => pt.Amount);

        var items = await query
            .OrderByDescending(pt => pt.ViolationDate)
            .ThenByDescending(pt => pt.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(pt => new PenaltyTicketDto
            {
                Id = pt.Id,
                TicketCode = pt.TicketCode,
                EmployeeId = pt.EmployeeId,
                EmployeeName = pt.Employee != null ? (pt.Employee.LastName + " " + pt.Employee.FirstName).Trim() : "N/A",
                EmployeeCode = pt.Employee != null ? pt.Employee.EmployeeCode : null,
                Type = pt.Type.ToString(),
                Status = pt.Status.ToString(),
                Amount = pt.Amount,
                ViolationDate = pt.ViolationDate,
                MinutesLateOrEarly = pt.MinutesLateOrEarly,
                ShiftStartTime = pt.ShiftStartTime.HasValue ? pt.ShiftStartTime.Value.ToString(@"hh\:mm") : null,
                ShiftEndTime = pt.ShiftEndTime.HasValue ? pt.ShiftEndTime.Value.ToString(@"hh\:mm") : null,
                ActualPunchTime = pt.ActualPunchTime,
                PenaltyTier = pt.PenaltyTier,
                RepeatCountInMonth = pt.RepeatCountInMonth,
                Description = pt.Description,
                CancellationReason = pt.CancellationReason,
                ProcessedById = pt.ProcessedById,
                ProcessedByName = pt.ProcessedBy != null ? (pt.ProcessedBy.LastName + " " + pt.ProcessedBy.FirstName) : null,
                ProcessedDate = pt.ProcessedDate,
                CashTransactionId = pt.CashTransactionId,
                CashTransactionCode = pt.CashTransaction != null ? pt.CashTransaction.TransactionCode : null,
                CreatedAt = pt.CreatedAt
            })
            .ToListAsync();

        var response = new PenaltyTicketListResponse
        {
            Items = items,
            TotalCount = totalCount,
            Page = page,
            PageSize = pageSize,
            TotalPendingAmount = totalPending,
            TotalApprovedAmount = totalApproved
        };

        return Ok(AppResponse<PenaltyTicketListResponse>.Success(response));
    }

    /// <summary>
    /// Láº¥y chi tiáº¿t phiáº¿u pháº¡t
    /// </summary>
    [HttpGet("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("PenaltyTickets", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<PenaltyTicketDto>>> GetPenaltyTicket(Guid id)
    {
        var storeId = RequiredStoreId;
        var ticket = await dbContext.PenaltyTickets
            .Include(pt => pt.Employee)
            .Include(pt => pt.ProcessedBy)
            .Include(pt => pt.CashTransaction)
            .FirstOrDefaultAsync(pt => pt.Id == id && pt.StoreId == storeId && pt.Deleted == null);

        if (ticket == null)
            return NotFound(AppResponse<PenaltyTicketDto>.Fail("Phiáº¿u pháº¡t khÃ´ng tá»“n táº¡i"));

        var dto = new PenaltyTicketDto
        {
            Id = ticket.Id,
            TicketCode = ticket.TicketCode,
            EmployeeId = ticket.EmployeeId,
            EmployeeName = ticket.Employee != null ? $"{ticket.Employee.LastName} {ticket.Employee.FirstName}".Trim() : "N/A",
            EmployeeCode = ticket.Employee?.EmployeeCode,
            Type = ticket.Type.ToString(),
            Status = ticket.Status.ToString(),
            Amount = ticket.Amount,
            ViolationDate = ticket.ViolationDate,
            MinutesLateOrEarly = ticket.MinutesLateOrEarly,
            ShiftStartTime = ticket.ShiftStartTime?.ToString(@"hh\:mm"),
            ShiftEndTime = ticket.ShiftEndTime?.ToString(@"hh\:mm"),
            ActualPunchTime = ticket.ActualPunchTime,
            PenaltyTier = ticket.PenaltyTier,
            RepeatCountInMonth = ticket.RepeatCountInMonth,
            Description = ticket.Description,
            CancellationReason = ticket.CancellationReason,
            ProcessedById = ticket.ProcessedById,
            ProcessedByName = ticket.ProcessedBy != null ? $"{ticket.ProcessedBy.LastName} {ticket.ProcessedBy.FirstName}".Trim() : null,
            ProcessedDate = ticket.ProcessedDate,
            CashTransactionId = ticket.CashTransactionId,
            CashTransactionCode = ticket.CashTransaction?.TransactionCode,
            CreatedAt = ticket.CreatedAt
        };

        return Ok(AppResponse<PenaltyTicketDto>.Success(dto));
    }

    /// <summary>
    /// Há»§y phiáº¿u pháº¡t (Pending / Approved / AutoApproved). Nếu có phiếu thu liên kết → hủy luôn phiếu thu.
    /// </summary>
    [HttpPost("{id}/cancel")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("PenaltyTickets", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<PenaltyTicketDto>>> CancelPenaltyTicket(Guid id, [FromBody] CancelPenaltyRequest request)
    {
        var storeId = RequiredStoreId;
        var ticket = await dbContext.PenaltyTickets
            .Include(pt => pt.Employee)
            .Include(pt => pt.CashTransaction)
            .FirstOrDefaultAsync(pt => pt.Id == id && pt.StoreId == storeId && pt.Deleted == null);

        if (ticket == null)
            return NotFound(AppResponse<PenaltyTicketDto>.Fail("Phiáº¿u pháº¡t khÃ´ng tá»“n táº¡i"));

        if (ticket.Status == PenaltyTicketStatus.Cancelled)
            return BadRequest(AppResponse<PenaltyTicketDto>.Fail("Phiáº¿u pháº¡t Ä‘Ã£ bá»‹ há»§y"));

        if (ticket.Status != PenaltyTicketStatus.Pending
            && ticket.Status != PenaltyTicketStatus.Approved
            && ticket.Status != PenaltyTicketStatus.AutoApproved)
            return BadRequest(AppResponse<PenaltyTicketDto>.Fail("KhÃ´ng thá»ƒ há»§y phiáº¿u pháº¡t á»Ÿ tráº¡ng thÃ¡i hiá»‡n táº¡i"));

        ticket.Status = PenaltyTicketStatus.Cancelled;
        ticket.CancellationReason = request.Reason;
        ticket.ProcessedById = CurrentUserId;
        ticket.ProcessedDate = DateTime.Now;
        ticket.UpdatedAt = DateTime.Now;

        var linkedCash = ticket.CashTransaction
            ?? await PenaltyTicketFinanceHelper.ResolveLinkedCashTransactionAsync(dbContext, ticket);
        if (PenaltyTicketFinanceHelper.CancelLinkedCashTransaction(linkedCash, request.Reason))
            dbContext.Update(linkedCash!);

        await CancelLinkedAttendancePenaltyTransactionsAsync(ticket);

        dbContext.Update(ticket);
        await dbContext.SaveChangesAsync();

        // Notify employee
        try
        {
            var uid = ticket.Employee?.ApplicationUserId;
            if (uid != null && uid != CurrentUserId)
                await notificationService.CreateAndSendAsync(uid, NotificationType.Warning,
                    "Phiáº¿u pháº¡t Ä‘Ã£ bá»‹ há»§y",
                    $"Phiáº¿u pháº¡t {ticket.TicketCode} ({ticket.Amount:N0}Ä‘) Ä‘Ã£ bá»‹ há»§y.",
                    relatedEntityType: "PenaltyTicket", relatedEntityId: ticket.Id,
                    fromUserId: CurrentUserId, categoryCode: "penalty", storeId: RequiredStoreId);
        }
        catch { /* Notification failure should not affect main operation */ }

        return Ok(AppResponse<PenaltyTicketDto>.Success(new PenaltyTicketDto
        {
            Id = ticket.Id,
            TicketCode = ticket.TicketCode,
            Status = ticket.Status.ToString(),
            CancellationReason = ticket.CancellationReason
        }));
    }

    /// <summary>
    /// Duyá»‡t phiáº¿u pháº¡t thá»§ cÃ´ng â†’ táº¡o phiáº¿u thu ngay
    /// </summary>
    [HttpPost("{id}/approve")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("PenaltyTickets", ModulePermissionAction.Approve)]
    public async Task<ActionResult<AppResponse<PenaltyTicketDto>>> ApprovePenaltyTicket(Guid id, [FromBody] ApprovePenaltyRequest? request)
    {
        var storeId = RequiredStoreId;
        var ticket = await dbContext.PenaltyTickets
            .Include(pt => pt.Employee)
            .FirstOrDefaultAsync(pt => pt.Id == id && pt.StoreId == storeId && pt.Deleted == null);

        if (ticket == null)
            return NotFound(AppResponse<PenaltyTicketDto>.Fail("Phiáº¿u pháº¡t khÃ´ng tá»“n táº¡i"));

        if (ticket.Status != PenaltyTicketStatus.Pending)
            return BadRequest(AppResponse<PenaltyTicketDto>.Fail("Chá»‰ cÃ³ thá»ƒ duyá»‡t phiáº¿u pháº¡t Ä‘ang chá» duyá»‡t"));

        ticket.Status = PenaltyTicketStatus.Approved;
        ticket.ProcessedById = CurrentUserId;
        ticket.ProcessedDate = DateTime.Now;
        ticket.UpdatedAt = DateTime.Now;

        var cashTransaction = await PenaltyTicketFinanceHelper.CreateCashTransactionAsync(
            dbContext, ticket, CurrentUserId);
        ticket.CashTransactionId = cashTransaction.Id;

        dbContext.Update(ticket);
        await dbContext.SaveChangesAsync();

        // Notify employee
        try
        {
            var uid = ticket.Employee?.ApplicationUserId;
            if (uid != null && uid != CurrentUserId)
                await notificationService.CreateAndSendAsync(uid, NotificationType.Info,
                    "Phiáº¿u pháº¡t Ä‘Ã£ Ä‘Æ°á»£c duyá»‡t",
                    $"Phiáº¿u pháº¡t {ticket.TicketCode} ({ticket.Amount:N0}Ä‘) Ä‘Ã£ Ä‘Æ°á»£c duyá»‡t.",
                    relatedEntityType: "PenaltyTicket", relatedEntityId: ticket.Id,
                    fromUserId: CurrentUserId, categoryCode: "penalty", storeId: RequiredStoreId);
        }
        catch { /* Notification failure should not affect main operation */ }

        return Ok(AppResponse<PenaltyTicketDto>.Success(new PenaltyTicketDto
        {
            Id = ticket.Id,
            TicketCode = ticket.TicketCode,
            Status = ticket.Status.ToString(),
            CashTransactionId = cashTransaction.Id,
            CashTransactionCode = cashTransaction.TransactionCode
        }));
    }

    /// <summary>
    /// Thá»‘ng kÃª phiáº¿u pháº¡t theo thÃ¡ng hoáº·c theo khoáº£ng ngÃ y
    /// </summary>
    [HttpGet("stats")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("PenaltyTickets", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<PenaltyStatsSummary>>> GetPenaltyStats(
        [FromQuery] int? month = null,
        [FromQuery] int? year = null,
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null,
        [FromQuery] Guid? branchId = null,
        [FromQuery] bool includeChildBranches = true)
    {
        var storeId = RequiredStoreId;
        // Use VN-local "now" instead of DateTime.Now: Linux containers run in UTC, and at
        // 00:00â€“07:00 VN that would point at the wrong month/year.
        var now = DateTime.UtcNow.AddHours(7);

        // Base query â€” todos os filtros comuns
        var query = dbContext.PenaltyTickets
            .Where(pt => pt.StoreId == storeId && pt.Deleted == null)
            .AsQueryable();

        if (fromDate.HasValue || toDate.HasValue)
        {
            // Lá»c theo khoáº£ng ngÃ y tÆ°á»ng minh (fromDate/toDate) khi Ä‘Æ°á»£c cung cáº¥p.
            if (fromDate.HasValue)
                query = query.Where(pt => pt.ViolationDate >= fromDate.Value.Date);
            if (toDate.HasValue)
                query = query.Where(pt => pt.ViolationDate <= toDate.Value.Date);
        }
        else
        {
            // Fallback: lá»c theo thÃ¡ng/nÄƒm
            var targetMonth = month ?? now.Month;
            var targetYear = year ?? now.Year;
            var monthStart = new DateTime(targetYear, targetMonth, 1);
            var monthEnd = monthStart.AddMonths(1);
            query = query.Where(pt => pt.ViolationDate >= monthStart && pt.ViolationDate < monthEnd);
        }

        var branchScope = await BranchQueryHelper.ResolveEmployeeScopeAsync(
            dbContext, storeId, branchId, includeChildBranches);
        if (branchScope != null)
        {
            if (branchScope.IsEmpty)
                return Ok(AppResponse<PenaltyStatsSummary>.Success(new PenaltyStatsSummary()));
            query = query.Where(pt => branchScope.EmployeeIds.Contains(pt.EmployeeId));
        }

        var stats = new PenaltyStatsSummary
        {
            TotalPending = await query.CountAsync(pt => pt.Status == PenaltyTicketStatus.Pending),
            TotalApproved = await query.CountAsync(pt => pt.Status == PenaltyTicketStatus.Approved),
            TotalAutoApproved = await query.CountAsync(pt => pt.Status == PenaltyTicketStatus.AutoApproved),
            TotalCancelled = await query.CountAsync(pt => pt.Status == PenaltyTicketStatus.Cancelled),
            PendingAmount = await query.Where(pt => pt.Status == PenaltyTicketStatus.Pending).SumAsync(pt => pt.Amount),
            ApprovedAmount = await query.Where(pt => pt.Status == PenaltyTicketStatus.Approved || pt.Status == PenaltyTicketStatus.AutoApproved).SumAsync(pt => pt.Amount),
        };

        return Ok(AppResponse<PenaltyStatsSummary>.Success(stats));
    }

    /// <summary>
    /// Láº¥y danh sÃ¡ch phiáº¿u pháº¡t cá»§a nhÃ¢n viÃªn Ä‘ang Ä‘Äƒng nháº­p
    /// </summary>
    [HttpGet("my")]
    [RequireModulePermission("PenaltyTickets", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<PenaltyTicketListResponse>>> GetMyPenaltyTickets(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null)
    {
        var storeId = RequiredStoreId;
        var userId = CurrentUserId;

        // TÃ¬m Employee tá»« ApplicationUserId
        var employee = await dbContext.Employees
            .FirstOrDefaultAsync(e => e.ApplicationUserId == userId && e.StoreId == storeId);

        if (employee == null)
            return Ok(AppResponse<PenaltyTicketListResponse>.Success(new PenaltyTicketListResponse()));

        var query = dbContext.PenaltyTickets
            .Where(pt => pt.EmployeeId == employee.Id && pt.StoreId == storeId && pt.Deleted == null);

        if (fromDate.HasValue)
            query = query.Where(pt => pt.ViolationDate >= fromDate.Value.Date);
        if (toDate.HasValue)
            query = query.Where(pt => pt.ViolationDate <= toDate.Value.Date);

        var totalCount = await query.CountAsync();
        var items = await query
            .OrderByDescending(pt => pt.ViolationDate)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(pt => new PenaltyTicketDto
            {
                Id = pt.Id,
                TicketCode = pt.TicketCode,
                EmployeeId = pt.EmployeeId,
                Type = pt.Type.ToString(),
                Status = pt.Status.ToString(),
                Amount = pt.Amount,
                ViolationDate = pt.ViolationDate,
                MinutesLateOrEarly = pt.MinutesLateOrEarly,
                ShiftStartTime = pt.ShiftStartTime.HasValue ? pt.ShiftStartTime.Value.ToString(@"hh\:mm") : null,
                ShiftEndTime = pt.ShiftEndTime.HasValue ? pt.ShiftEndTime.Value.ToString(@"hh\:mm") : null,
                ActualPunchTime = pt.ActualPunchTime,
                PenaltyTier = pt.PenaltyTier,
                Description = pt.Description,
                CancellationReason = pt.CancellationReason,
                ProcessedDate = pt.ProcessedDate,
                CreatedAt = pt.CreatedAt
            })
            .ToListAsync();

        return Ok(AppResponse<PenaltyTicketListResponse>.Success(new PenaltyTicketListResponse
        {
            Items = items,
            TotalCount = totalCount,
            Page = page,
            PageSize = pageSize
        }));
    }

    /// <summary>
    /// Táº¡o phiáº¿u pháº¡t thá»§ cÃ´ng
    /// </summary>
    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("PenaltyTickets", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<PenaltyTicketDto>>> CreatePenaltyTicket([FromBody] CreatePenaltyTicketRequest request)
    {
        var storeId = RequiredStoreId;

        var employee = await dbContext.Employees
            .FirstOrDefaultAsync(e => e.Id == request.EmployeeId && e.StoreId == storeId);
        if (employee == null)
            return NotFound(AppResponse<PenaltyTicketDto>.Fail("NhÃ¢n viÃªn khÃ´ng tá»“n táº¡i"));

        if (!Enum.TryParse<PenaltyTicketType>(request.Type, out var ticketType))
            ticketType = PenaltyTicketType.Violation;

        var dateStr = request.ViolationDate.ToString("yyyyMMdd");
        var prefix = $"PP-{dateStr}-";
        var count = await dbContext.PenaltyTickets
            .CountAsync(pt => pt.TicketCode.StartsWith(prefix) && pt.StoreId == storeId);

        var ticket = new Domain.Entities.PenaltyTicket
        {
            Id = Guid.NewGuid(),
            TicketCode = $"{prefix}{(count + 1):D4}",
            EmployeeId = request.EmployeeId,
            Type = ticketType,
            Status = PenaltyTicketStatus.Pending,
            Amount = request.Amount,
            ViolationDate = request.ViolationDate.Date,
            MinutesLateOrEarly = request.MinutesLateOrEarly,
            PenaltyTier = 1,
            Description = request.Description ?? $"Pháº¡t thá»§ cÃ´ng - {employee.LastName} {employee.FirstName}".Trim(),
            StoreId = storeId,
            CreatedAt = DateTime.Now,
            UpdatedAt = DateTime.Now
        };

        dbContext.PenaltyTickets.Add(ticket);
        await dbContext.SaveChangesAsync();

        // Notify employee
        try
        {
            var uid = employee.ApplicationUserId;
            if (uid != null && uid != CurrentUserId)
                await notificationService.CreateAndSendAsync(uid, NotificationType.Warning,
                    "Báº¡n cÃ³ phiáº¿u pháº¡t má»›i",
                    $"Phiáº¿u pháº¡t {ticket.TicketCode} - {ticket.Amount:N0}Ä‘ ({ticket.Type}).",
                    relatedEntityType: "PenaltyTicket", relatedEntityId: ticket.Id,
                    fromUserId: CurrentUserId, categoryCode: "penalty", storeId: RequiredStoreId);
        }
        catch { /* Notification failure should not affect main operation */ }

        var dto = new PenaltyTicketDto
        {
            Id = ticket.Id,
            TicketCode = ticket.TicketCode,
            EmployeeId = ticket.EmployeeId,
            EmployeeName = $"{employee.LastName} {employee.FirstName}".Trim(),
            EmployeeCode = employee.EmployeeCode,
            Type = ticket.Type.ToString(),
            Status = ticket.Status.ToString(),
            Amount = ticket.Amount,
            ViolationDate = ticket.ViolationDate,
            MinutesLateOrEarly = ticket.MinutesLateOrEarly,
            Description = ticket.Description,
            PenaltyTier = ticket.PenaltyTier,
            CreatedAt = ticket.CreatedAt
        };

        return Ok(AppResponse<PenaltyTicketDto>.Success(dto));
    }

    /// <summary>
    /// Sá»­a phiáº¿u pháº¡t (chá»‰ khi Pending)
    /// </summary>
    [HttpPut("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("PenaltyTickets", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<PenaltyTicketDto>>> UpdatePenaltyTicket(Guid id, [FromBody] UpdatePenaltyTicketRequest request)
    {
        var storeId = RequiredStoreId;
        var ticket = await dbContext.PenaltyTickets
            .Include(pt => pt.Employee)
            .FirstOrDefaultAsync(pt => pt.Id == id && pt.StoreId == storeId && pt.Deleted == null);

        if (ticket == null)
            return NotFound(AppResponse<PenaltyTicketDto>.Fail("Phiáº¿u pháº¡t khÃ´ng tá»“n táº¡i"));

        if (ticket.Status != PenaltyTicketStatus.Pending)
            return BadRequest(AppResponse<PenaltyTicketDto>.Fail("Chá»‰ cÃ³ thá»ƒ sá»­a phiáº¿u pháº¡t Ä‘ang chá» duyá»‡t"));

        if (request.Type != null && Enum.TryParse<PenaltyTicketType>(request.Type, out var newType))
            ticket.Type = newType;
        if (request.Amount.HasValue)
            ticket.Amount = request.Amount.Value;
        if (request.Description != null)
            ticket.Description = request.Description;

        ticket.UpdatedAt = DateTime.Now;
        dbContext.Update(ticket);
        await dbContext.SaveChangesAsync();

        // Notify employee
        try
        {
            var uid = ticket.Employee?.ApplicationUserId;
            if (uid != null && uid != CurrentUserId)
                await notificationService.CreateAndSendAsync(uid, NotificationType.Info,
                    "Phiáº¿u pháº¡t Ä‘Ã£ Ä‘Æ°á»£c cáº­p nháº­t",
                    $"Phiáº¿u pháº¡t {ticket.TicketCode} Ä‘Ã£ Ä‘Æ°á»£c cáº­p nháº­t ({ticket.Amount:N0}Ä‘).",
                    relatedEntityType: "PenaltyTicket", relatedEntityId: ticket.Id,
                    fromUserId: CurrentUserId, categoryCode: "penalty", storeId: RequiredStoreId);
        }
        catch { /* Notification failure should not affect main operation */ }

        return Ok(AppResponse<PenaltyTicketDto>.Success(new PenaltyTicketDto
        {
            Id = ticket.Id,
            TicketCode = ticket.TicketCode,
            EmployeeId = ticket.EmployeeId,
            EmployeeName = ticket.Employee != null ? $"{ticket.Employee.LastName} {ticket.Employee.FirstName}".Trim() : "N/A",
            Type = ticket.Type.ToString(),
            Status = ticket.Status.ToString(),
            Amount = ticket.Amount,
            Description = ticket.Description,
            ViolationDate = ticket.ViolationDate,
            CreatedAt = ticket.CreatedAt
        }));
    }

    /// <summary>
    /// XÃ³a phiáº¿u pháº¡t (soft delete, chá»‰ khi Pending). Xóa mềm phiếu thu liên kết nếu có.
    /// </summary>
    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("PenaltyTickets", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<string>>> DeletePenaltyTicket(Guid id)
    {
        var storeId = RequiredStoreId;
        var ticket = await dbContext.PenaltyTickets
            .Include(pt => pt.Employee)
            .Include(pt => pt.CashTransaction)
            .FirstOrDefaultAsync(pt => pt.Id == id && pt.StoreId == storeId && pt.Deleted == null);

        if (ticket == null)
            return NotFound(AppResponse<string>.Fail("Phiáº¿u pháº¡t khÃ´ng tá»“n táº¡i"));

        if (ticket.Status != PenaltyTicketStatus.Pending)
            return BadRequest(AppResponse<string>.Fail("Chá»‰ cÃ³ thá»ƒ xÃ³a phiáº¿u pháº¡t Ä‘ang chá» duyá»‡t"));

        var ticketCode = ticket.TicketCode;
        var employeeUserId = ticket.Employee?.ApplicationUserId;

        var linkedCash = ticket.CashTransaction
            ?? await PenaltyTicketFinanceHelper.ResolveLinkedCashTransactionAsync(dbContext, ticket);
        if (PenaltyTicketFinanceHelper.SoftDeleteLinkedCashTransaction(linkedCash))
        {
            dbContext.Update(linkedCash!);
            ticket.CashTransactionId = null;
        }

        await CancelLinkedAttendancePenaltyTransactionsAsync(ticket);

        ticket.Deleted = DateTime.Now;
        ticket.UpdatedAt = DateTime.Now;
        dbContext.Update(ticket);
        await dbContext.SaveChangesAsync();

        // Notify employee
        try
        {
            if (employeeUserId != null && employeeUserId != CurrentUserId)
                await notificationService.CreateAndSendAsync(employeeUserId, NotificationType.Warning,
                    "Phiáº¿u pháº¡t Ä‘Ã£ bá»‹ xÃ³a",
                    $"Phiáº¿u pháº¡t {ticketCode} Ä‘Ã£ bá»‹ xÃ³a.",
                    relatedEntityType: "PenaltyTicket", relatedEntityId: id,
                    fromUserId: CurrentUserId, categoryCode: "penalty", storeId: RequiredStoreId);
        }
        catch { /* Notification failure should not affect main operation */ }

        return Ok(AppResponse<string>.Success("ÄÃ£ xÃ³a phiáº¿u pháº¡t"));
    }

    /// <summary>
    /// HoÃ n duyá»‡t phiáº¿u pháº¡t (Approved/AutoApproved â†’ Pending, xÃ³a phiáº¿u thu liÃªn quan)
    /// </summary>
    [HttpPost("{id}/unapprove")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("PenaltyTickets", ModulePermissionAction.Approve)]
    public async Task<ActionResult<AppResponse<PenaltyTicketDto>>> UnapprovePenaltyTicket(Guid id)
    {
        var storeId = RequiredStoreId;
        var ticket = await dbContext.PenaltyTickets
            .Include(pt => pt.Employee)
            .Include(pt => pt.CashTransaction)
            .FirstOrDefaultAsync(pt => pt.Id == id && pt.StoreId == storeId && pt.Deleted == null);

        if (ticket == null)
            return NotFound(AppResponse<PenaltyTicketDto>.Fail("Phiáº¿u pháº¡t khÃ´ng tá»“n táº¡i"));

        if (ticket.Status != PenaltyTicketStatus.Approved && ticket.Status != PenaltyTicketStatus.AutoApproved)
            return BadRequest(AppResponse<PenaltyTicketDto>.Fail("Chá»‰ cÃ³ thá»ƒ hoÃ n duyá»‡t phiáº¿u pháº¡t Ä‘Ã£ duyá»‡t"));

        var linkedCash = ticket.CashTransaction
            ?? await PenaltyTicketFinanceHelper.ResolveLinkedCashTransactionAsync(dbContext, ticket);
        if (PenaltyTicketFinanceHelper.SoftDeleteLinkedCashTransaction(linkedCash))
            dbContext.Update(linkedCash!);

        ticket.Status = PenaltyTicketStatus.Pending;
        ticket.CashTransactionId = null;
        ticket.ProcessedById = null;
        ticket.ProcessedDate = null;
        ticket.UpdatedAt = DateTime.Now;
        dbContext.Update(ticket);
        await dbContext.SaveChangesAsync();

        // Notify employee
        try
        {
            var uid = ticket.Employee?.ApplicationUserId;
            if (uid != null && uid != CurrentUserId)
                await notificationService.CreateAndSendAsync(uid, NotificationType.Info,
                    "Phiáº¿u pháº¡t Ä‘Ã£ hoÃ n duyá»‡t",
                    $"Phiáº¿u pháº¡t {ticket.TicketCode} ({ticket.Amount:N0}Ä‘) Ä‘Ã£ Ä‘Æ°á»£c hoÃ n duyá»‡t vá» tráº¡ng thÃ¡i chá».",
                    relatedEntityType: "PenaltyTicket", relatedEntityId: ticket.Id,
                    fromUserId: CurrentUserId, categoryCode: "penalty", storeId: RequiredStoreId);
        }
        catch { /* Notification failure should not affect main operation */ }

        return Ok(AppResponse<PenaltyTicketDto>.Success(new PenaltyTicketDto
        {
            Id = ticket.Id,
            TicketCode = ticket.TicketCode,
            Status = ticket.Status.ToString(),
            EmployeeName = ticket.Employee != null ? $"{ticket.Employee.LastName} {ticket.Employee.FirstName}".Trim() : "N/A"
        }));
    }

    /// <summary>
    /// Quét lại chấm công và tạo phiếu phạt đi trễ/về sớm/tái phạm còn thiếu trong khoảng ngày.
    /// </summary>
    [HttpPost("backfill-from-attendance")]
    [RequireModulePermission("PenaltyTickets", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> BackfillFromAttendance(
        [FromQuery] DateTime from,
        [FromQuery] DateTime to,
        CancellationToken cancellationToken = default)
    {
        var storeId = RequiredStoreId;
        if (to.Date < from.Date)
            return BadRequest(AppResponse<object>.Fail("Ngày kết thúc phải sau ngày bắt đầu"));

        var maxDays = 62;
        if ((to.Date - from.Date).TotalDays > maxDays)
            return BadRequest(AppResponse<object>.Fail($"Khoảng ngày tối đa {maxDays} ngày"));

        var processed = await attendanceService.BackfillPenaltyTicketsAsync(
            storeId, from.Date, to.Date, cancellationToken);

        return Ok(AppResponse<object>.Success(new
        {
            processedPunches = processed,
            from = from.Date.ToString("yyyy-MM-dd"),
            to = to.Date.ToString("yyyy-MM-dd"),
            message = $"Đã quét {processed} lần chấm công và tạo phiếu phạt còn thiếu (nếu có).",
        }));
    }

    #region Private Methods

    /// <summary>
    /// Hủy PaymentTransaction phạt tự động từ chấm công (tạo song song với PenaltyTicket).
    /// </summary>
    private async Task CancelLinkedAttendancePenaltyTransactionsAsync(Domain.Entities.PenaltyTicket ticket)
    {
        var prefix = ticket.Type switch
        {
            PenaltyTicketType.Late => "Đi trễ",
            PenaltyTicketType.EarlyLeave => "Về sớm",
            _ => null
        };
        if (prefix == null) return;

        var pending = await dbContext.PaymentTransactions
            .Where(pt => pt.EmployeeId == ticket.EmployeeId
                && pt.TransactionDate.Date == ticket.ViolationDate.Date
                && pt.Type == "Penalty"
                && pt.Status == "Pending"
                && pt.Note != null
                && pt.Note.Contains("Tự động tạo từ chấm công")
                && pt.Description != null
                && pt.Description.StartsWith(prefix))
            .ToListAsync();

        foreach (var pt in pending)
        {
            pt.Status = "Cancelled";
            pt.UpdatedAt = DateTime.UtcNow;
        }
    }

    #endregion
}

