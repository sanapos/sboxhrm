using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Application.Services;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Bấm ô số liệu báo cáo kiến nghị → danh sách phiếu đã dùng để tính (cùng điều kiện GET stats).</summary>
public partial class FeedbackController
{
    /// <summary>
    /// kind: total | open | overdue | onTime (phiếu đã giải quyết, kèm đúng / trễ hạn) |
    /// firstResponse (phiếu đã phản hồi, kèm số giờ) | resolve (phiếu đã giải quyết, kèm số giờ) | rating (phiếu có đánh giá).
    /// Không trả người gửi (phiếu có thể ẩn danh).
    /// </summary>
    [HttpGet("stats/drill")]
    [RequireModulePermission("Feedback", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> DrillStats(
        [FromQuery] string kind, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
    {
        var storeId = RequiredStoreId;
        var v = await ViewerAsync();
        if (!v.Handler) return StatusCode(403, AppResponse<object>.Fail("Chỉ người xử lý được xem báo cáo"));

        var now = DateTime.UtcNow;
        var to = (toDate ?? now).Date.AddDays(1);
        var from = (fromDate ?? now.Date.AddMonths(-5).AddDays(1 - now.Day)).Date;
        var list = await Scoped(storeId, v).AsNoTracking().Where(f => f.CreatedAt >= from && f.CreatedAt < to).ToListAsync();

        list = (kind ?? "").ToLowerInvariant() switch
        {
            "total" => list,
            "open" => list.Where(f => FeedbackRules.IsOpen(f.Status)).ToList(),
            "overdue" => list.Where(f => FeedbackRules.IsOverdue(f.Status, f.DueAt, now)).ToList(),
            "ontime" or "resolve" => list.Where(f => f.ResolvedAt.HasValue).ToList(),
            "firstresponse" => list.Where(f => f.FirstResponseAt.HasValue).ToList(),
            "rating" => list.Where(f => f.Rating.HasValue).ToList(),
            _ => list.Take(0).ToList(),
        };
        var emps = await EmployeesAsync(list.Select(f => f.AssigneeEmployeeId));

        return Ok(AppResponse<object>.Success(list
            .OrderByDescending(f => f.CreatedAt)
            .Select(f => new
            {
                id = f.Id,
                code = f.Code,
                title = f.Title,
                status = f.Status,
                statusName = FeedbackRules.StatusName(f.Status),
                priorityName = FeedbackRules.PriorityName(f.Priority),
                categoryName = FeedbackRules.CategoryName(f.Category),
                createdAt = f.CreatedAt,
                dueAt = f.DueAt,
                resolvedAt = f.ResolvedAt,
                overdue = FeedbackRules.IsOverdue(f.Status, f.DueAt, now),
                onTime = f.ResolvedAt.HasValue && (!f.DueAt.HasValue || f.ResolvedAt <= f.DueAt),
                firstResponseHours = f.FirstResponseAt.HasValue
                    ? Math.Round((f.FirstResponseAt.Value - f.CreatedAt).TotalHours, 1) : (double?)null,
                resolveHours = f.ResolvedAt.HasValue
                    ? Math.Round((f.ResolvedAt.Value - f.CreatedAt).TotalHours, 1) : (double?)null,
                rating = f.Rating,
                assignee = f.AssigneeEmployeeId.HasValue ? emps.GetValueOrDefault(f.AssigneeEmployeeId.Value)?.Name : null,
            })
            .ToList()));
    }
}
