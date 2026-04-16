using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class OvertimesController(
    ZKTecoDbContext dbContext,
    ILogger<OvertimesController> logger,
    ISystemNotificationService notificationService
) : AuthenticatedControllerBase
{
    #region Employee Endpoints

    /// <summary>
    /// Lấy danh sách đơn tăng ca của nhân viên hiện tại
    /// </summary>
    [HttpGet("my-overtimes")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<List<OvertimeDto>>>> GetMyOvertimes(
        [FromQuery] int? month = null,
        [FromQuery] int? year = null)
    {
        try
        {
            var storeId = RequiredStoreId;
            var userId = CurrentUserId;

            var query = dbContext.Overtimes
                .Include(o => o.EmployeeUser)
                .Include(o => o.Manager)
                .Where(o => o.StoreId == storeId && o.EmployeeUserId == userId);

            if (month.HasValue && year.HasValue)
            {
                query = query.Where(o => o.Date.Month == month.Value && o.Date.Year == year.Value);
            }
            else
            {
                // Default: last 3 months
                var startDate = DateTime.Today.AddMonths(-3);
                query = query.Where(o => o.Date >= startDate);
            }

            var overtimes = await query
                .OrderByDescending(o => o.Date)
                .Select(o => MapToDto(o))
                .ToListAsync();

            return Ok(AppResponse<List<OvertimeDto>>.Success(overtimes));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error getting my overtimes");
            return StatusCode(500, AppResponse<List<OvertimeDto>>.Fail("Error getting overtimes"));
        }
    }

    /// <summary>
    /// Tạo đơn đăng ký tăng ca
    /// </summary>
    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<OvertimeDto>>> CreateOvertime([FromBody] CreateOvertimeRequest request)
    {
        try
        {
            var storeId = RequiredStoreId;
            var userId = CurrentUserId;
            var managerId = request.EmployeeUserId.HasValue ? userId : ManagerId ?? userId;
            var employeeUserId = request.EmployeeUserId ?? userId;

            // Calculate planned hours
            var plannedHours = (decimal)(request.EndTime - request.StartTime).TotalHours;
            if (plannedHours <= 0)
            {
                return BadRequest(AppResponse<OvertimeDto>.Fail("Thời gian kết thúc phải sau thời gian bắt đầu"));
            }

            // Determine multiplier based on type
            var multiplier = request.Type switch
            {
                OvertimeType.Weekday => 1.5m,
                OvertimeType.Weekend => 2.0m,
                OvertimeType.Holiday => 3.0m,
                OvertimeType.Night => 1.3m,
                _ => 1.5m
            };

            var overtime = new Overtime
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                EmployeeUserId = employeeUserId,
                ManagerId = managerId,
                Type = request.Type,
                Date = request.Date,
                StartTime = request.StartTime,
                EndTime = request.EndTime,
                PlannedHours = plannedHours,
                Multiplier = multiplier,
                Reason = request.Reason,
                WorkContent = request.WorkContent,
                Status = OvertimeStatus.Pending,
                CreatedAt = DateTime.UtcNow,
                CreatedBy = userId.ToString()
            };

            dbContext.Overtimes.Add(overtime);
            await dbContext.SaveChangesAsync();

            // Reload with includes
            var result = await dbContext.Overtimes
                .Include(o => o.EmployeeUser)
                .Include(o => o.Manager)
                .FirstOrDefaultAsync(o => o.Id == overtime.Id);

            try
            {
                // If managerId is the employee themselves (ManagerId was null/fallback), notify all store managers
                if (managerId == employeeUserId)
                {
                    var storeManagers = await dbContext.Users
                        .Where(u => u.StoreId == storeId && u.Id != employeeUserId)
                        .Join(dbContext.UserRoles, u => u.Id, ur => ur.UserId, (u, ur) => new { u, ur })
                        .Join(dbContext.Roles, x => x.ur.RoleId, r => r.Id, (x, r) => new { x.u, Role = r.Name })
                        .Where(x => x.Role == nameof(Roles.Manager) || x.Role == nameof(Roles.Admin))
                        .Select(x => x.u.Id)
                        .Distinct()
                        .ToListAsync();
                    if (storeManagers.Count > 0)
                    {
                        await notificationService.CreateAndSendToUsersAsync(
                            storeManagers, NotificationType.ApprovalRequired,
                            "Đơn tăng ca mới",
                            $"Có đơn tăng ca mới ngày {request.Date:dd/MM/yyyy} ({request.StartTime:hh\\:mm} - {request.EndTime:hh\\:mm}) cần phê duyệt",
                            relatedEntityId: overtime.Id, relatedEntityType: "Overtime",
                            fromUserId: employeeUserId, categoryCode: "overtime", storeId: RequiredStoreId);
                    }
                }
                else
                {
                    await notificationService.CreateAndSendAsync(
                        managerId, NotificationType.ApprovalRequired,
                        "Đơn tăng ca mới",
                        $"Có đơn tăng ca mới ngày {request.Date:dd/MM/yyyy} ({request.StartTime:hh\\:mm} - {request.EndTime:hh\\:mm}) cần phê duyệt",
                        relatedEntityId: overtime.Id, relatedEntityType: "Overtime",
                        fromUserId: employeeUserId, categoryCode: "overtime", storeId: RequiredStoreId);
                }
            }
            catch { /* Notification failure should not affect main operation */ }

            return Ok(AppResponse<OvertimeDto>.Success(MapToDto(result!)));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error creating overtime");
            return StatusCode(500, AppResponse<OvertimeDto>.Fail("Error creating overtime request"));
        }
    }

    /// <summary>
    /// Cập nhật đơn tăng ca (chỉ khi còn Pending)
    /// </summary>
    [HttpPut("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<OvertimeDto>>> UpdateOvertime(
        Guid id,
        [FromBody] UpdateOvertimeRequest request)
    {
        try
        {
            var storeId = RequiredStoreId;
            var userId = CurrentUserId;

            var overtime = await dbContext.Overtimes
                .AsTracking()
                .Include(o => o.EmployeeUser)
                .Include(o => o.Manager)
                .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId);

            if (overtime == null)
            {
                return NotFound(AppResponse<OvertimeDto>.Fail("Overtime not found"));
            }

            // Only owner or manager can update
            if (overtime.EmployeeUserId != userId && !IsManager)
            {
                return Forbid();
            }

            // Can only update pending requests
            if (overtime.Status != OvertimeStatus.Pending && !IsManager)
            {
                return BadRequest(AppResponse<OvertimeDto>.Fail("Cannot update non-pending request"));
            }

            // Update fields
            if (request.Date.HasValue) overtime.Date = request.Date.Value;
            if (request.StartTime.HasValue) overtime.StartTime = request.StartTime.Value;
            if (request.EndTime.HasValue) overtime.EndTime = request.EndTime.Value;
            if (request.Type.HasValue)
            {
                overtime.Type = request.Type.Value;
                overtime.Multiplier = request.Type.Value switch
                {
                    OvertimeType.Weekday => 1.5m,
                    OvertimeType.Weekend => 2.0m,
                    OvertimeType.Holiday => 3.0m,
                    OvertimeType.Night => 1.3m,
                    _ => 1.5m
                };
            }
            if (!string.IsNullOrEmpty(request.Reason)) overtime.Reason = request.Reason;
            if (request.WorkContent != null) overtime.WorkContent = request.WorkContent;
            if (!string.IsNullOrEmpty(request.Note)) overtime.Note = request.Note;

            // Recalculate planned hours
            overtime.PlannedHours = (decimal)(overtime.EndTime - overtime.StartTime).TotalHours;

            overtime.UpdatedAt = DateTime.UtcNow;
            overtime.UpdatedBy = userId.ToString();

            await dbContext.SaveChangesAsync();

            return Ok(AppResponse<OvertimeDto>.Success(MapToDto(overtime)));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error updating overtime");
            return StatusCode(500, AppResponse<OvertimeDto>.Fail("Error updating overtime"));
        }
    }

    /// <summary>
    /// Hủy đơn tăng ca
    /// </summary>
    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<bool>>> CancelOvertime(Guid id)
    {
        try
        {
            var storeId = RequiredStoreId;
            var userId = CurrentUserId;

            var overtime = await dbContext.Overtimes
                .AsTracking()
                .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId);

            if (overtime == null)
            {
                return NotFound(AppResponse<bool>.Fail("Overtime not found"));
            }

            // Only owner can cancel, and only if pending
            if (overtime.EmployeeUserId != userId)
            {
                return Forbid();
            }

            if (overtime.Status != OvertimeStatus.Pending)
            {
                return BadRequest(AppResponse<bool>.Fail("Cannot cancel non-pending request"));
            }

            overtime.Status = OvertimeStatus.Cancelled;
            overtime.UpdatedAt = DateTime.UtcNow;
            overtime.UpdatedBy = userId.ToString();

            await dbContext.SaveChangesAsync();

            return Ok(AppResponse<bool>.Success(true));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error cancelling overtime");
            return StatusCode(500, AppResponse<bool>.Fail("Error cancelling overtime"));
        }
    }

    #endregion

    #region Manager Endpoints

    /// <summary>
    /// Lấy danh sách đơn tăng ca chờ duyệt
    /// </summary>
    [HttpGet("pending")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<List<OvertimeDto>>>> GetPendingOvertimes()
    {
        try
        {
            var storeId = RequiredStoreId;
            var userId = CurrentUserId;

            var query = dbContext.Overtimes
                .Include(o => o.EmployeeUser)
                .Include(o => o.Manager)
                .Where(o => o.StoreId == storeId && o.Status == OvertimeStatus.Pending);

            // If not manager/admin, only see own requests assigned to them
            if (!IsManager)
            {
                query = query.Where(o => o.ManagerId == userId);
            }

            var overtimes = await query
                .OrderBy(o => o.Date)
                .Select(o => MapToDto(o))
                .ToListAsync();

            return Ok(AppResponse<List<OvertimeDto>>.Success(overtimes));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error getting pending overtimes");
            return StatusCode(500, AppResponse<List<OvertimeDto>>.Fail("Error getting pending overtimes"));
        }
    }

    /// <summary>
    /// Lấy tất cả đơn tăng ca
    /// </summary>
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<PagedResult<OvertimeDto>>>> GetAllOvertimes(
        [FromQuery] PaginationRequest request,
        [FromQuery] int? month = null,
        [FromQuery] int? year = null,
        [FromQuery] OvertimeStatus? status = null)
    {
        try
        {
            var storeId = RequiredStoreId;
            var userId = CurrentUserId;

            var query = dbContext.Overtimes
                .Include(o => o.EmployeeUser)
                .Include(o => o.Manager)
                .Where(o => o.StoreId == storeId);

            // If not manager/admin, only see own requests or assigned requests
            if (!IsManager)
            {
                query = query.Where(o => o.EmployeeUserId == userId || o.ManagerId == userId);
            }

            if (month.HasValue && year.HasValue)
            {
                query = query.Where(o => o.Date.Month == month.Value && o.Date.Year == year.Value);
            }

            if (status.HasValue)
            {
                query = query.Where(o => o.Status == status.Value);
            }

            var totalCount = await query.CountAsync();

            var overtimes = await query
                .OrderByDescending(o => o.Date)
                .Skip((request.PageNumber - 1) * request.PageSize)
                .Take(request.PageSize)
                .Select(o => MapToDto(o))
                .ToListAsync();

            var result = new PagedResult<OvertimeDto>
            {
                Items = overtimes,
                TotalCount = totalCount,
                PageNumber = request.PageNumber,
                PageSize = request.PageSize
            };

            return Ok(AppResponse<PagedResult<OvertimeDto>>.Success(result));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error getting all overtimes");
            return StatusCode(500, AppResponse<PagedResult<OvertimeDto>>.Fail("Error getting overtimes"));
        }
    }

    /// <summary>
    /// Duyệt đơn tăng ca
    /// </summary>
    [HttpPost("{id}/approve")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<bool>>> ApproveOvertime(Guid id)
    {
        try
        {
            var storeId = RequiredStoreId;
            var userId = CurrentUserId;

            var overtime = await dbContext.Overtimes
                .AsTracking()
                .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId);

            if (overtime == null)
            {
                return NotFound(AppResponse<bool>.Fail("Overtime not found"));
            }

            if (overtime.Status != OvertimeStatus.Pending)
            {
                return BadRequest(AppResponse<bool>.Fail("Can only approve pending requests"));
            }

            overtime.Status = OvertimeStatus.Approved;
            overtime.ApprovedAt = DateTime.UtcNow;
            overtime.UpdatedAt = DateTime.UtcNow;
            overtime.UpdatedBy = userId.ToString();

            await dbContext.SaveChangesAsync();

            try
            {
                await notificationService.CreateAndSendAsync(
                    overtime.EmployeeUserId, NotificationType.Success,
                    "Đơn tăng ca đã duyệt",
                    $"Đơn tăng ca ngày {overtime.Date:dd/MM/yyyy} đã được phê duyệt",
                    relatedEntityId: overtime.Id, relatedEntityType: "Overtime",
                    fromUserId: userId, categoryCode: "approval", storeId: RequiredStoreId);
            }
            catch { /* Notification failure should not affect main operation */ }

            return Ok(AppResponse<bool>.Success(true));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error approving overtime");
            return StatusCode(500, AppResponse<bool>.Fail("Error approving overtime"));
        }
    }

    /// <summary>
    /// Từ chối đơn tăng ca
    /// </summary>
    [HttpPost("{id}/reject")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<bool>>> RejectOvertime(
        Guid id,
        [FromBody] RejectOvertimeRequest request)
    {
        try
        {
            var storeId = RequiredStoreId;
            var userId = CurrentUserId;

            var overtime = await dbContext.Overtimes
                .AsTracking()
                .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId);

            if (overtime == null)
            {
                return NotFound(AppResponse<bool>.Fail("Overtime not found"));
            }

            if (overtime.Status != OvertimeStatus.Pending)
            {
                return BadRequest(AppResponse<bool>.Fail("Can only reject pending requests"));
            }

            overtime.Status = OvertimeStatus.Rejected;
            overtime.RejectionReason = request.RejectionReason;
            overtime.UpdatedAt = DateTime.UtcNow;
            overtime.UpdatedBy = userId.ToString();

            await dbContext.SaveChangesAsync();

            try
            {
                await notificationService.CreateAndSendAsync(
                    overtime.EmployeeUserId, NotificationType.Warning,
                    "Đơn tăng ca bị từ chối",
                    $"Đơn tăng ca ngày {overtime.Date:dd/MM/yyyy} đã bị từ chối. Lý do: {request.RejectionReason}",
                    relatedEntityId: overtime.Id, relatedEntityType: "Overtime",
                    fromUserId: userId, categoryCode: "approval", storeId: RequiredStoreId);
            }
            catch { /* Notification failure should not affect main operation */ }

            return Ok(AppResponse<bool>.Success(true));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error rejecting overtime");
            return StatusCode(500, AppResponse<bool>.Fail("Error rejecting overtime"));
        }
    }

    /// <summary>
    /// Cập nhật số giờ tăng ca thực tế
    /// </summary>
    [HttpPost("{id}/complete")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<bool>>> CompleteOvertime(
        Guid id,
        [FromBody] CompleteOvertimeRequest request)
    {
        try
        {
            var storeId = RequiredStoreId;
            var userId = CurrentUserId;

            var overtime = await dbContext.Overtimes
                .AsTracking()
                .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId);

            if (overtime == null)
            {
                return NotFound(AppResponse<bool>.Fail("Overtime not found"));
            }

            if (overtime.Status != OvertimeStatus.Approved)
            {
                return BadRequest(AppResponse<bool>.Fail("Can only complete approved overtime"));
            }

            overtime.Status = OvertimeStatus.Completed;
            overtime.ActualHours = request.ActualHours;
            overtime.Note = request.Note;
            overtime.UpdatedAt = DateTime.UtcNow;
            overtime.UpdatedBy = userId.ToString();

            await dbContext.SaveChangesAsync();

            try
            {
                await notificationService.CreateAndSendAsync(
                    overtime.EmployeeUserId, NotificationType.Info,
                    "Đơn tăng ca hoàn thành",
                    $"Đơn tăng ca ngày {overtime.Date:dd/MM/yyyy} đã hoàn thành. Giờ thực tế: {request.ActualHours}h",
                    relatedEntityId: overtime.Id, relatedEntityType: "Overtime",
                    fromUserId: userId, categoryCode: "overtime", storeId: RequiredStoreId);
            }
            catch { /* Notification failure should not affect main operation */ }

            return Ok(AppResponse<bool>.Success(true));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error completing overtime");
            return StatusCode(500, AppResponse<bool>.Fail("Error completing overtime"));
        }
    }

    #endregion

    #region Statistics

    /// <summary>
    /// Thống kê tăng ca theo tháng
    /// </summary>
    [HttpGet("statistics")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<OvertimeStatisticsDto>>> GetOvertimeStatistics(
        [FromQuery] int? month = null,
        [FromQuery] int? year = null)
    {
        try
        {
            var storeId = RequiredStoreId;
            var userId = CurrentUserId;
            var targetMonth = month ?? DateTime.Now.Month;
            var targetYear = year ?? DateTime.Now.Year;

            var query = dbContext.Overtimes
                .Where(o => o.StoreId == storeId
                    && o.Date.Month == targetMonth
                    && o.Date.Year == targetYear);

            // If not manager/admin, only own statistics
            if (!IsManager)
            {
                query = query.Where(o => o.EmployeeUserId == userId);
            }

            // Server-side aggregation: avoid loading all records into memory
            var statusCounts = await query
                .GroupBy(o => o.Status)
                .Select(g => new { Status = g.Key, Count = g.Count() })
                .ToListAsync();

            var totalPlannedHours = await query
                .Where(o => o.Status == OvertimeStatus.Approved || o.Status == OvertimeStatus.Completed)
                .SumAsync(o => o.PlannedHours);

            var totalActualHours = await query
                .Where(o => o.Status == OvertimeStatus.Completed && o.ActualHours.HasValue)
                .SumAsync(o => o.ActualHours!.Value);

            var stats = new OvertimeStatisticsDto
            {
                Month = targetMonth,
                Year = targetYear,
                TotalRequests = statusCounts.Sum(x => x.Count),
                PendingCount = statusCounts.FirstOrDefault(x => x.Status == OvertimeStatus.Pending)?.Count ?? 0,
                ApprovedCount = statusCounts.FirstOrDefault(x => x.Status == OvertimeStatus.Approved)?.Count ?? 0,
                RejectedCount = statusCounts.FirstOrDefault(x => x.Status == OvertimeStatus.Rejected)?.Count ?? 0,
                CompletedCount = statusCounts.FirstOrDefault(x => x.Status == OvertimeStatus.Completed)?.Count ?? 0,
                TotalPlannedHours = totalPlannedHours,
                TotalActualHours = totalActualHours
            };

            return Ok(AppResponse<OvertimeStatisticsDto>.Success(stats));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error getting overtime statistics");
            return StatusCode(500, AppResponse<OvertimeStatisticsDto>.Fail("Error getting statistics"));
        }
    }

    #endregion

    #region Helpers

    private static OvertimeDto MapToDto(Overtime o) => new()
    {
        Id = o.Id,
        EmployeeUserId = o.EmployeeUserId,
        EmployeeName = o.EmployeeUser != null ? $"{o.EmployeeUser.LastName} {o.EmployeeUser.FirstName}".Trim() : "N/A",
        ManagerId = o.ManagerId,
        ManagerName = o.Manager != null ? $"{o.Manager.LastName} {o.Manager.FirstName}".Trim() : "N/A",
        Type = o.Type,
        TypeName = GetTypeName(o.Type),
        Date = o.Date,
        StartTime = o.StartTime,
        EndTime = o.EndTime,
        PlannedHours = o.PlannedHours,
        ActualHours = o.ActualHours,
        Multiplier = o.Multiplier,
        Reason = o.Reason,
        WorkContent = o.WorkContent,
        Status = o.Status,
        StatusName = GetStatusName(o.Status),
        RejectionReason = o.RejectionReason,
        ApprovedAt = o.ApprovedAt,
        Note = o.Note,
        CreatedAt = o.CreatedAt,
        UpdatedAt = o.UpdatedAt
    };

    private static string GetTypeName(OvertimeType type) => type switch
    {
        OvertimeType.Weekday => "Tăng ca ngày thường",
        OvertimeType.Weekend => "Tăng ca cuối tuần",
        OvertimeType.Holiday => "Tăng ca ngày lễ",
        OvertimeType.Night => "Tăng ca ban đêm",
        _ => "Không xác định"
    };

    private static string GetStatusName(OvertimeStatus status) => status switch
    {
        OvertimeStatus.Pending => "Chờ duyệt",
        OvertimeStatus.Approved => "Đã duyệt",
        OvertimeStatus.Rejected => "Từ chối",
        OvertimeStatus.Cancelled => "Đã hủy",
        OvertimeStatus.Completed => "Hoàn thành",
        _ => "Không xác định"
    };

    #endregion
}

#region DTOs

public class OvertimeDto
{
    public Guid Id { get; set; }
    public Guid EmployeeUserId { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public Guid ManagerId { get; set; }
    public string ManagerName { get; set; } = string.Empty;
    public OvertimeType Type { get; set; }
    public string TypeName { get; set; } = string.Empty;
    public DateTime Date { get; set; }
    public TimeSpan StartTime { get; set; }
    public TimeSpan EndTime { get; set; }
    public decimal PlannedHours { get; set; }
    public decimal? ActualHours { get; set; }
    public decimal Multiplier { get; set; }
    public string Reason { get; set; } = string.Empty;
    public string? WorkContent { get; set; }
    public OvertimeStatus Status { get; set; }
    public string StatusName { get; set; } = string.Empty;
    public string? RejectionReason { get; set; }
    public DateTime? ApprovedAt { get; set; }
    public string? Note { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
}

public class CreateOvertimeRequest
{
    public Guid? EmployeeUserId { get; set; }
    public OvertimeType Type { get; set; }
    public DateTime Date { get; set; }
    public TimeSpan StartTime { get; set; }
    public TimeSpan EndTime { get; set; }
    public string Reason { get; set; } = string.Empty;
    public string? WorkContent { get; set; }
}

public class UpdateOvertimeRequest
{
    public DateTime? Date { get; set; }
    public TimeSpan? StartTime { get; set; }
    public TimeSpan? EndTime { get; set; }
    public OvertimeType? Type { get; set; }
    public string? Reason { get; set; }
    public string? WorkContent { get; set; }
    public string? Note { get; set; }
}

public class RejectOvertimeRequest
{
    public string RejectionReason { get; set; } = string.Empty;
}

public class CompleteOvertimeRequest
{
    public decimal ActualHours { get; set; }
    public string? Note { get; set; }
}

public class OvertimeStatisticsDto
{
    public int Month { get; set; }
    public int Year { get; set; }
    public int TotalRequests { get; set; }
    public int PendingCount { get; set; }
    public int ApprovedCount { get; set; }
    public int RejectedCount { get; set; }
    public int CompletedCount { get; set; }
    public decimal TotalPlannedHours { get; set; }
    public decimal TotalActualHours { get; set; }
}

#endregion
