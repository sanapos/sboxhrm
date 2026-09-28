using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// «Dấu đã sửa» cho bảng tổng hợp chấm công: mỗi giờ chấm được thêm / sửa tay (yêu cầu điều chỉnh đã duyệt)
/// kèm giờ gốc, lý do, người duyệt, thời điểm — hiện chấm nhỏ trên ô giờ, rê chuột xem chi tiết.
/// </summary>
[ApiController]
[Route("api/attendance-edit-marks")]
[Authorize(Policy = PolicyNames.AtLeastEmployee)]
public class AttendanceEditMarksController(ZKTecoDbContext db) : AuthenticatedControllerBase
{
    [HttpGet]
    [RequireAnyModulePermission(ModulePermissionAction.View, "Attendance", "AttendanceSummary", "AttendanceByShift", "AttendanceCorrection")]
    public async Task<IActionResult> Get([FromQuery] DateTime fromDate, [FromQuery] DateTime toDate, CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var from = fromDate.Date.AddDays(-1);
        var to = toDate.Date.AddDays(2);

        var q = db.AttendanceCorrectionRequests.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.Status == CorrectionStatus.Approved && c.AttendanceId != null
                        && c.Action != CorrectionAction.Delete
                        && ((c.NewDate >= from && c.NewDate < to) || (c.OldDate >= from && c.OldDate < to)));
        // Nhân viên thường chỉ xem dấu sửa của chính mình
        if (!IsManager && !IsAccountant) q = q.Where(c => c.EmployeeUserId == CurrentUserId);

        var rows = await q
            .OrderByDescending(c => c.ApprovedDate ?? c.CreatedAt)
            .Select(c => new
            {
                c.AttendanceId,
                c.Action,
                c.OldDate,
                c.OldTime,
                c.NewDate,
                c.NewTime,
                c.Reason,
                c.ApproverNote,
                c.ApprovedDate,
                c.CreatedAt,
                ApprovedBy = c.ApprovedBy == null ? null : (c.ApprovedBy.LastName + " " + c.ApprovedBy.FirstName).Trim(),
                RequestedBy = (c.EmployeeUser.LastName + " " + c.EmployeeUser.FirstName).Trim(),
            })
            .Take(5000)
            .ToListAsync(ct);

        // Mỗi bản ghi chấm công chỉ lấy lần sửa gần nhất
        var result = rows
            .GroupBy(r => r.AttendanceId!.Value)
            .Select(g =>
            {
                var r = g.First();
                return new
                {
                    attendanceId = g.Key,
                    action = r.Action == CorrectionAction.Add ? "add" : "edit",
                    originalTime = r.Action == CorrectionAction.Add || r.OldTime == null ? null : r.OldTime.Value.ToString(@"hh\:mm"),
                    originalDate = r.Action == CorrectionAction.Add ? null : r.OldDate?.ToString("yyyy-MM-dd"),
                    newTime = r.NewTime?.ToString(@"hh\:mm"),
                    reason = r.Reason,
                    approverNote = r.ApproverNote,
                    by = r.ApprovedBy ?? r.RequestedBy,
                    at = r.ApprovedDate ?? r.CreatedAt,
                    times = g.Count(),
                };
            });
        return Ok(AppResponse<object>.Success(result));
    }
}
