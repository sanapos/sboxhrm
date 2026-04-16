using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class PenaltyTicketsController(ZKTecoDbContext dbContext, ISystemNotificationService notificationService) : AuthenticatedControllerBase
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
    /// Lấy danh sách phiếu phạt (có phân trang, lọc)
    /// </summary>
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<PenaltyTicketListResponse>>> GetPenaltyTickets(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] Guid? employeeId = null,
        [FromQuery] PenaltyTicketStatus? status = null,
        [FromQuery] PenaltyTicketType? type = null,
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null)
    {
        var storeId = RequiredStoreId;
        var query = dbContext.PenaltyTickets
            .Include(pt => pt.Employee)
            .Include(pt => pt.ProcessedBy)
            .Include(pt => pt.CashTransaction)
            .Where(pt => pt.StoreId == storeId && pt.Deleted == null)
            .AsQueryable();

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
    /// Lấy chi tiết phiếu phạt
    /// </summary>
    [HttpGet("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<PenaltyTicketDto>>> GetPenaltyTicket(Guid id)
    {
        var storeId = RequiredStoreId;
        var ticket = await dbContext.PenaltyTickets
            .Include(pt => pt.Employee)
            .Include(pt => pt.ProcessedBy)
            .Include(pt => pt.CashTransaction)
            .FirstOrDefaultAsync(pt => pt.Id == id && pt.StoreId == storeId && pt.Deleted == null);

        if (ticket == null)
            return NotFound(AppResponse<PenaltyTicketDto>.Fail("Phiếu phạt không tồn tại"));

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
    /// Hủy phiếu phạt (chỉ khi đang Pending)
    /// </summary>
    [HttpPost("{id}/cancel")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<PenaltyTicketDto>>> CancelPenaltyTicket(Guid id, [FromBody] CancelPenaltyRequest request)
    {
        var storeId = RequiredStoreId;
        var ticket = await dbContext.PenaltyTickets
            .Include(pt => pt.Employee)
            .FirstOrDefaultAsync(pt => pt.Id == id && pt.StoreId == storeId && pt.Deleted == null);

        if (ticket == null)
            return NotFound(AppResponse<PenaltyTicketDto>.Fail("Phiếu phạt không tồn tại"));

        if (ticket.Status != PenaltyTicketStatus.Pending)
            return BadRequest(AppResponse<PenaltyTicketDto>.Fail("Chỉ có thể hủy phiếu phạt đang chờ duyệt"));

        ticket.Status = PenaltyTicketStatus.Cancelled;
        ticket.CancellationReason = request.Reason;
        ticket.ProcessedById = CurrentUserId;
        ticket.ProcessedDate = DateTime.Now;
        ticket.UpdatedAt = DateTime.Now;

        await dbContext.SaveChangesAsync();

        // Notify employee
        try
        {
            var uid = ticket.Employee?.ApplicationUserId;
            if (uid != null && uid != CurrentUserId)
                await notificationService.CreateAndSendAsync(uid, NotificationType.Warning,
                    "Phiếu phạt đã bị hủy",
                    $"Phiếu phạt {ticket.TicketCode} ({ticket.Amount:N0}đ) đã bị hủy.",
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
    /// Duyệt phiếu phạt thủ công → tạo phiếu thu ngay
    /// </summary>
    [HttpPost("{id}/approve")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<PenaltyTicketDto>>> ApprovePenaltyTicket(Guid id, [FromBody] ApprovePenaltyRequest? request)
    {
        var storeId = RequiredStoreId;
        var ticket = await dbContext.PenaltyTickets
            .Include(pt => pt.Employee)
            .FirstOrDefaultAsync(pt => pt.Id == id && pt.StoreId == storeId && pt.Deleted == null);

        if (ticket == null)
            return NotFound(AppResponse<PenaltyTicketDto>.Fail("Phiếu phạt không tồn tại"));

        if (ticket.Status != PenaltyTicketStatus.Pending)
            return BadRequest(AppResponse<PenaltyTicketDto>.Fail("Chỉ có thể duyệt phiếu phạt đang chờ duyệt"));

        ticket.Status = PenaltyTicketStatus.Approved;
        ticket.ProcessedById = CurrentUserId;
        ticket.ProcessedDate = DateTime.Now;
        ticket.UpdatedAt = DateTime.Now;

        // Tạo phiếu thu
        var cashTransaction = await CreateCashTransactionAsync(ticket);
        ticket.CashTransactionId = cashTransaction.Id;

        await dbContext.SaveChangesAsync();

        // Notify employee
        try
        {
            var uid = ticket.Employee?.ApplicationUserId;
            if (uid != null && uid != CurrentUserId)
                await notificationService.CreateAndSendAsync(uid, NotificationType.Info,
                    "Phiếu phạt đã được duyệt",
                    $"Phiếu phạt {ticket.TicketCode} ({ticket.Amount:N0}đ) đã được duyệt.",
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
    /// Thống kê phiếu phạt theo tháng
    /// </summary>
    [HttpGet("stats")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<PenaltyStatsSummary>>> GetPenaltyStats(
        [FromQuery] int? month = null,
        [FromQuery] int? year = null)
    {
        var storeId = RequiredStoreId;
        var now = DateTime.Now;
        var targetMonth = month ?? now.Month;
        var targetYear = year ?? now.Year;
        var monthStart = new DateTime(targetYear, targetMonth, 1);
        var monthEnd = monthStart.AddMonths(1);

        var query = dbContext.PenaltyTickets
            .Where(pt => pt.StoreId == storeId
                && pt.ViolationDate >= monthStart
                && pt.ViolationDate < monthEnd
                && pt.Deleted == null);

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
    /// Lấy danh sách phiếu phạt của nhân viên đang đăng nhập
    /// </summary>
    [HttpGet("my")]
    public async Task<ActionResult<AppResponse<PenaltyTicketListResponse>>> GetMyPenaltyTickets(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null)
    {
        var storeId = RequiredStoreId;
        var userId = CurrentUserId;

        // Tìm Employee từ ApplicationUserId
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
    /// Tạo phiếu phạt thủ công
    /// </summary>
    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<PenaltyTicketDto>>> CreatePenaltyTicket([FromBody] CreatePenaltyTicketRequest request)
    {
        var storeId = RequiredStoreId;

        var employee = await dbContext.Employees
            .FirstOrDefaultAsync(e => e.Id == request.EmployeeId && e.StoreId == storeId);
        if (employee == null)
            return NotFound(AppResponse<PenaltyTicketDto>.Fail("Nhân viên không tồn tại"));

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
            Description = request.Description ?? $"Phạt thủ công - {employee.LastName} {employee.FirstName}".Trim(),
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
                    "Bạn có phiếu phạt mới",
                    $"Phiếu phạt {ticket.TicketCode} - {ticket.Amount:N0}đ ({ticket.Type}).",
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
    /// Sửa phiếu phạt (chỉ khi Pending)
    /// </summary>
    [HttpPut("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<PenaltyTicketDto>>> UpdatePenaltyTicket(Guid id, [FromBody] UpdatePenaltyTicketRequest request)
    {
        var storeId = RequiredStoreId;
        var ticket = await dbContext.PenaltyTickets
            .Include(pt => pt.Employee)
            .FirstOrDefaultAsync(pt => pt.Id == id && pt.StoreId == storeId && pt.Deleted == null);

        if (ticket == null)
            return NotFound(AppResponse<PenaltyTicketDto>.Fail("Phiếu phạt không tồn tại"));

        if (ticket.Status != PenaltyTicketStatus.Pending)
            return BadRequest(AppResponse<PenaltyTicketDto>.Fail("Chỉ có thể sửa phiếu phạt đang chờ duyệt"));

        if (request.Type != null && Enum.TryParse<PenaltyTicketType>(request.Type, out var newType))
            ticket.Type = newType;
        if (request.Amount.HasValue)
            ticket.Amount = request.Amount.Value;
        if (request.Description != null)
            ticket.Description = request.Description;

        ticket.UpdatedAt = DateTime.Now;
        await dbContext.SaveChangesAsync();

        // Notify employee
        try
        {
            var uid = ticket.Employee?.ApplicationUserId;
            if (uid != null && uid != CurrentUserId)
                await notificationService.CreateAndSendAsync(uid, NotificationType.Info,
                    "Phiếu phạt đã được cập nhật",
                    $"Phiếu phạt {ticket.TicketCode} đã được cập nhật ({ticket.Amount:N0}đ).",
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
    /// Xóa phiếu phạt (soft delete, chỉ khi Pending)
    /// </summary>
    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<string>>> DeletePenaltyTicket(Guid id)
    {
        var storeId = RequiredStoreId;
        var ticket = await dbContext.PenaltyTickets
            .Include(pt => pt.Employee)
            .FirstOrDefaultAsync(pt => pt.Id == id && pt.StoreId == storeId && pt.Deleted == null);

        if (ticket == null)
            return NotFound(AppResponse<string>.Fail("Phiếu phạt không tồn tại"));

        if (ticket.Status != PenaltyTicketStatus.Pending)
            return BadRequest(AppResponse<string>.Fail("Chỉ có thể xóa phiếu phạt đang chờ duyệt"));

        var ticketCode = ticket.TicketCode;
        var employeeUserId = ticket.Employee?.ApplicationUserId;

        ticket.Deleted = DateTime.Now;
        ticket.UpdatedAt = DateTime.Now;
        await dbContext.SaveChangesAsync();

        // Notify employee
        try
        {
            if (employeeUserId != null && employeeUserId != CurrentUserId)
                await notificationService.CreateAndSendAsync(employeeUserId, NotificationType.Warning,
                    "Phiếu phạt đã bị xóa",
                    $"Phiếu phạt {ticketCode} đã bị xóa.",
                    relatedEntityType: "PenaltyTicket", relatedEntityId: id,
                    fromUserId: CurrentUserId, categoryCode: "penalty", storeId: RequiredStoreId);
        }
        catch { /* Notification failure should not affect main operation */ }

        return Ok(AppResponse<string>.Success("Đã xóa phiếu phạt"));
    }

    /// <summary>
    /// Hoàn duyệt phiếu phạt (Approved/AutoApproved → Pending, xóa phiếu thu liên quan)
    /// </summary>
    [HttpPost("{id}/unapprove")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<PenaltyTicketDto>>> UnapprovePenaltyTicket(Guid id)
    {
        var storeId = RequiredStoreId;
        var ticket = await dbContext.PenaltyTickets
            .Include(pt => pt.Employee)
            .Include(pt => pt.CashTransaction)
            .FirstOrDefaultAsync(pt => pt.Id == id && pt.StoreId == storeId && pt.Deleted == null);

        if (ticket == null)
            return NotFound(AppResponse<PenaltyTicketDto>.Fail("Phiếu phạt không tồn tại"));

        if (ticket.Status != PenaltyTicketStatus.Approved && ticket.Status != PenaltyTicketStatus.AutoApproved)
            return BadRequest(AppResponse<PenaltyTicketDto>.Fail("Chỉ có thể hoàn duyệt phiếu phạt đã duyệt"));

        // Xóa phiếu thu liên quan nếu có
        if (ticket.CashTransaction != null)
        {
            ticket.CashTransaction.Deleted = DateTime.Now;
            ticket.CashTransaction.UpdatedAt = DateTime.Now;
        }

        ticket.Status = PenaltyTicketStatus.Pending;
        ticket.CashTransactionId = null;
        ticket.ProcessedById = null;
        ticket.ProcessedDate = null;
        ticket.UpdatedAt = DateTime.Now;

        await dbContext.SaveChangesAsync();

        // Notify employee
        try
        {
            var uid = ticket.Employee?.ApplicationUserId;
            if (uid != null && uid != CurrentUserId)
                await notificationService.CreateAndSendAsync(uid, NotificationType.Info,
                    "Phiếu phạt đã hoàn duyệt",
                    $"Phiếu phạt {ticket.TicketCode} ({ticket.Amount:N0}đ) đã được hoàn duyệt về trạng thái chờ.",
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

    #region Private Methods

    private async Task<Domain.Entities.CashTransaction> CreateCashTransactionAsync(Domain.Entities.PenaltyTicket ticket)
    {
        // Tìm hoặc tạo danh mục
        var category = await dbContext.TransactionCategories
            .FirstOrDefaultAsync(c => c.Name == "Phạt nhân viên"
                && c.Type == CashTransactionType.Income
                && c.StoreId == ticket.StoreId);

        if (category == null)
        {
            category = new Domain.Entities.TransactionCategory
            {
                Id = Guid.NewGuid(),
                Name = "Phạt nhân viên",
                Description = "Thu phạt nhân viên vi phạm nội quy",
                Type = CashTransactionType.Income,
                Icon = "gavel",
                Color = "#F44336",
                IsSystem = true,
                StoreId = ticket.StoreId,
                IsActive = true,
                CreatedAt = DateTime.Now
            };
            dbContext.TransactionCategories.Add(category);
        }

        var dateStr = DateTime.Now.ToString("yyyyMMdd");
        var txPrefix = $"TC-{dateStr}-";
        var txCount = await dbContext.CashTransactions
            .CountAsync(ct => ct.TransactionCode.StartsWith(txPrefix) && ct.StoreId == ticket.StoreId);

        var employeeName = ticket.Employee != null
            ? $"{ticket.Employee.LastName} {ticket.Employee.FirstName}".Trim()
            : "N/A";

        var typeText = ticket.Type switch
        {
            PenaltyTicketType.Late => "đi trễ",
            PenaltyTicketType.EarlyLeave => "về sớm",
            PenaltyTicketType.ForgotCheck => "quên chấm công",
            PenaltyTicketType.UnauthorizedLeave => "nghỉ không phép",
            PenaltyTicketType.Violation => "vi phạm nội quy",
            _ => "vi phạm"
        };

        var cashTransaction = new Domain.Entities.CashTransaction
        {
            Id = Guid.NewGuid(),
            TransactionCode = $"{txPrefix}{(txCount + 1):D4}",
            Type = CashTransactionType.Income,
            CategoryId = category.Id,
            Amount = ticket.Amount,
            TransactionDate = DateTime.Now,
            Description = $"Thu phạt {typeText} - NV {employeeName} - Ngày {ticket.ViolationDate:dd/MM/yyyy} - {ticket.TicketCode}",
            PaymentMethod = PaymentMethodType.Cash,
            Status = CashTransactionStatus.Pending,
            IsPaid = false,
            StoreId = ticket.StoreId,
            CreatedByUserId = CurrentUserId,
            InternalNote = $"Tạo từ phiếu phạt {ticket.TicketCode}",
            CreatedAt = DateTime.Now,
            IsActive = true
        };

        dbContext.CashTransactions.Add(cashTransaction);
        return cashTransaction;
    }

    #endregion
}
