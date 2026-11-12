using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Bấm chip «Tổng quan công việc» → danh sách việc đã dùng để đếm (cùng điều kiện GET insights).</summary>
public partial class TasksController
{
    /// <summary>
    /// kind: open | overdue | dueToday | completed | onTime | pending (chờ nhận + chờ duyệt).
    /// Phạm vi / lọc giống hệt <see cref="GetInsights"/>.
    /// </summary>
    [HttpGet("insights/drill")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Task", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> DrillInsights(
        [FromQuery] string kind,
        [FromQuery] DateTime? from = null, [FromQuery] DateTime? to = null,
        [FromQuery] Guid? projectId = null, [FromQuery] bool onlyMine = false)
    {
        var now = DateTime.Now;
        var f = (from ?? now.Date.AddDays(-13)).Date;
        var t = (to ?? now).Date.AddDays(1);
        var query = _dbContext.WorkTasks.AsNoTracking().Where(x => x.StoreId == RequiredStoreId && x.IsActive);
        query = await TaskWorkflowHelper.ApplyViewerScopeAsync(query, _dbContext, RequiredStoreId, CurrentUserId, User);
        if (projectId.HasValue) query = query.Where(x => x.ProjectId == projectId);
        if (onlyMine)
        {
            var emp = await TaskWorkflowHelper.GetEmployeeForUserAsync(_dbContext, RequiredStoreId, CurrentUserId);
            if (emp == null) return Ok(AppResponse<object>.Success(Array.Empty<object>()));
            query = query.Where(x => x.AssigneeId == emp.Id || x.TaskAssignees!.Any(a => a.EmployeeId == emp.Id));
        }

        var openQuery = query.Where(x => x.Status != WorkTaskStatus.Completed && x.Status != WorkTaskStatus.Cancelled);
        query = (kind ?? "").ToLowerInvariant() switch
        {
            "open" => openQuery,
            "overdue" => openQuery.Where(x => x.DueDate < now),
            "duetoday" => openQuery.Where(x => x.DueDate >= now && x.DueDate < now.Date.AddDays(1)),
            "pending" => query.Where(x => x.Status == WorkTaskStatus.Assigned || x.Status == WorkTaskStatus.InReview),
            "completed" or "ontime" => query.Where(x =>
                x.Status == WorkTaskStatus.Completed && x.CompletedDate >= f && x.CompletedDate < t),
            _ => query.Where(x => false),
        };

        var rows = await query
            .OrderBy(x => x.DueDate == null).ThenBy(x => x.DueDate)
            .Take(1000)
            .Select(x => new
            {
                x.Id,
                x.TaskCode,
                x.Title,
                x.Status,
                x.DueDate,
                x.CompletedDate,
                x.CreatedAt,
                AssigneeName = x.Assignee != null ? x.Assignee.LastName + " " + x.Assignee.FirstName : null,
                ProjectName = x.Project != null ? x.Project.Name : null,
            })
            .ToListAsync();

        return Ok(AppResponse<object>.Success(rows.Select(x => new
        {
            id = x.Id,
            taskCode = x.TaskCode,
            title = x.Title,
            status = x.Status.ToString(),
            dueDate = x.DueDate,
            completedDate = x.CompletedDate,
            createdAt = x.CreatedAt,
            assigneeName = x.AssigneeName?.Trim(),
            projectName = x.ProjectName,
            onTime = x.CompletedDate != null && (x.DueDate == null || x.CompletedDate <= x.DueDate),
            cycleHours = x.CompletedDate != null ? Math.Round((x.CompletedDate.Value - x.CreatedAt).TotalHours, 1) : (double?)null,
        }).ToList()));
    }

    /// <summary>
    /// Bấm chip tab «Thống kê» (GET statistics) → danh sách việc.
    /// kind: all | status (kèm status = tên enum) | overdue | assignee (kèm assigneeId, chỉ quản lý).
    /// Lọc kỳ (CreatedAt) / chi nhánh / phạm vi người xem giống hệt <see cref="GetStatistics"/>.
    /// </summary>
    [HttpGet("statistics/drill")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Task", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> DrillStatistics(
        [FromQuery] string kind,
        [FromQuery] WorkTaskStatus? status = null,
        [FromQuery] Guid? assigneeId = null,
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null,
        [FromQuery] Guid? branchId = null,
        [FromQuery] bool includeChildBranches = true)
    {
        var storeId = RequiredStoreId;
        var now = DateTime.Now;
        var k = (kind ?? "").ToLowerInvariant();
        var query = _dbContext.WorkTasks.AsNoTracking().Where(t => t.StoreId == storeId && t.IsActive);

        if (k == "assignee")
        {
            // Thống kê theo nhân viên: không áp phạm vi người xem, chỉ quản lý thấy (giống GetStatistics).
            if (!TaskWorkflowHelper.IsManagerOrAdmin(User) || assigneeId == null)
                return Ok(AppResponse<object>.Success(Array.Empty<object>()));
            query = query.Where(t => t.AssigneeId == assigneeId);
        }
        else
        {
            query = await TaskWorkflowHelper.ApplyViewerScopeAsync(query, _dbContext, storeId, CurrentUserId, User);
        }

        var branchScope = await BranchQueryHelper.ResolveEmployeeScopeAsync(
            _dbContext, storeId, branchId, includeChildBranches);
        if (branchScope != null)
        {
            if (branchScope.IsEmpty) return Ok(AppResponse<object>.Success(Array.Empty<object>()));
            query = TaskWorkflowHelper.ApplyBranchFilter(query, branchScope);
        }
        if (fromDate.HasValue) query = query.Where(t => t.CreatedAt >= fromDate.Value);
        if (toDate.HasValue) query = query.Where(t => t.CreatedAt <= toDate.Value);

        query = k switch
        {
            "all" or "assignee" => query,
            "status" when status.HasValue => query.Where(t => t.Status == status.Value),
            "overdue" => query.Where(t =>
                t.DueDate < now && t.Status != WorkTaskStatus.Completed && t.Status != WorkTaskStatus.Cancelled),
            _ => query.Where(t => false),
        };

        var rows = await query
            .OrderByDescending(t => t.CreatedAt)
            .Take(1000)
            .Select(t => new
            {
                t.Id,
                t.TaskCode,
                t.Title,
                t.Status,
                t.Progress,
                t.DueDate,
                t.CompletedDate,
                t.CreatedAt,
                AssigneeName = t.Assignee != null ? t.Assignee.LastName + " " + t.Assignee.FirstName : null,
            })
            .ToListAsync();

        return Ok(AppResponse<object>.Success(rows.Select(t => new
        {
            id = t.Id,
            taskCode = t.TaskCode,
            title = t.Title,
            status = t.Status.ToString(),
            progress = t.Progress,
            dueDate = t.DueDate,
            completedDate = t.CompletedDate,
            createdAt = t.CreatedAt,
            assigneeName = t.AssigneeName?.Trim(),
            isOverdue = t.DueDate < now && t.Status != WorkTaskStatus.Completed && t.Status != WorkTaskStatus.Cancelled,
        }).ToList()));
    }
}
