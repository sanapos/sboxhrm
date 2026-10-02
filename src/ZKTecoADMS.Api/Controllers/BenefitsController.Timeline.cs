using Mapster;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Benefits;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Lịch sử hồ sơ lương theo ngày hiệu lực — bảng lương tính từng đoạn theo hồ sơ của đoạn đó.</summary>
public partial class BenefitsController
{
    public sealed record SalarySegmentDto(
        Guid Id,
        Guid BenefitId,
        BenefitDto? Benefit,
        DateTime EffectiveDate,
        DateTime? EndDate,
        DateTime From,
        DateTime To);

    public sealed record EmployeeTimelineDto(Guid EmployeeId, List<SalarySegmentDto> Segments);

    bool LowRank => AccountRolePolicy.RankOf(CurrentUserRole) < AccountRolePolicy.RankOf(nameof(Roles.DepartmentHead));

    static SalarySegmentDto ToDto(BenefitTimeline.Segment s) => new(
        s.Version.Id, s.Version.BenefitId, s.Version.Benefit?.Adapt<BenefitDto>(),
        s.Version.EffectiveDate, s.Version.EndDate, s.From, s.To);

    /// <summary>
    /// Các đoạn hồ sơ lương của nhân viên trong kỳ [from, to].
    /// Dưới cấp Trưởng phòng chỉ nhận đoạn của chính mình.
    /// </summary>
    [HttpGet("timeline")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<List<EmployeeTimelineDto>>>> GetTimeline(
        [FromQuery] DateTime from, [FromQuery] DateTime to, [FromQuery] Guid? employeeId,
        [FromServices] ZKTecoDbContext db, [FromServices] Application.Interfaces.IModulePermissionService perms,
        CancellationToken ct)
    {
        if (to < from) (from, to) = (to, from);
        if ((to - from).TotalDays > 400)
            return BadRequest(AppResponse<List<EmployeeTimelineDto>>.Fail("Kỳ tối đa 400 ngày."));

        Guid? only = employeeId;
        if (LowRank)
        {
            if (!EmployeeId.HasValue) return Ok(AppResponse<List<EmployeeTimelineDto>>.Success([]));
            only = EmployeeId.Value;
        }
        else
        {
            var ok = false;
            foreach (var m in new[] { "SalarySettings", "Benefit", "BonusPenalty", "Payroll" })
            {
                if (await perms.HasPermissionAsync(CurrentUserId, CurrentUserRole, CurrentStoreId, m, ModulePermissionAction.View, ct))
                {
                    ok = true;
                    break;
                }
            }
            if (!ok) return StatusCode(StatusCodes.Status403Forbidden, AppResponse<List<EmployeeTimelineDto>>.Fail("Không có quyền xem lương."));
        }

        var end = to.Date.AddDays(1);
        // Nhân viên của cửa hàng (bộ lọc cửa hàng nằm trên Employees).
        var q = db.EmployeeBenefits.AsNoTracking()
            .Include(eb => eb.Benefit)
            .Where(eb => db.Employees.Any(e => e.Id == eb.EmployeeId))
            .Where(eb => eb.EffectiveDate < end);
        if (only.HasValue) q = q.Where(eb => eb.EmployeeId == only.Value);
        var rows = await q.ToListAsync(ct);

        var result = rows.GroupBy(r => r.EmployeeId)
            .Select(g => new EmployeeTimelineDto(g.Key, BenefitTimeline.Segments(g, from, to).Select(ToDto).ToList()))
            .Where(t => t.Segments.Count > 0)
            .ToList();
        return Ok(AppResponse<List<EmployeeTimelineDto>>.Success(result));
    }

    /// <summary>Lịch sử thay đổi lương của một nhân viên (mới nhất trước), kèm thay đổi sắp áp dụng.</summary>
    [HttpGet("employees/{employeeId}/history")]
    [Authorize(Policy = PolicyNames.ManagerOrAccountant)]
    [RequireAnyModulePermission(ModulePermissionAction.View, "SalarySettings", "Benefit", "Payroll")]
    public async Task<ActionResult<AppResponse<List<SalarySegmentDto>>>> GetHistory(
        Guid employeeId, [FromServices] ZKTecoDbContext db, CancellationToken ct)
    {
        if (!await db.Employees.AnyAsync(e => e.Id == employeeId, ct))
            return NotFound(AppResponse<List<SalarySegmentDto>>.Fail("Không tìm thấy nhân viên"));
        var rows = await db.EmployeeBenefits.AsNoTracking().Include(eb => eb.Benefit)
            .Where(eb => eb.EmployeeId == employeeId)
            .ToListAsync(ct);
        var segs = BenefitTimeline.Segments(rows, DateTime.MinValue.AddYears(1), DateTime.MaxValue.AddYears(-1))
            .Select(ToDto)
            .OrderByDescending(s => s.From)
            .ToList();
        return Ok(AppResponse<List<SalarySegmentDto>>.Success(segs));
    }

    /// <summary>Hủy thay đổi lương chưa tới ngày áp dụng — bản trước đó chạy tiếp.</summary>
    [HttpDelete("versions/{id}")]
    [Authorize(Policy = PolicyNames.ManagerOrAccountant)]
    [RequireAnyModulePermission(ModulePermissionAction.Edit, "SalarySettings", "Benefit")]
    public async Task<ActionResult<AppResponse<bool>>> CancelUpcoming(
        Guid id, [FromServices] ZKTecoDbContext db, CancellationToken ct)
    {
        var v = await db.EmployeeBenefits.AsTracking()
            .FirstOrDefaultAsync(eb => eb.Id == id && db.Employees.Any(e => e.Id == eb.EmployeeId), ct);
        if (v == null) return NotFound(AppResponse<bool>.Fail("Không tìm thấy thay đổi lương"));
        if (v.EffectiveDate.Date <= BenefitTimeline.VnToday())
            return BadRequest(AppResponse<bool>.Fail("Thay đổi đã có hiệu lực — không hủy được. Hãy tạo thay đổi mới."));

        var prev = await db.EmployeeBenefits.AsTracking()
            .Where(eb => eb.EmployeeId == v.EmployeeId && eb.Id != v.Id && eb.EffectiveDate < v.EffectiveDate)
            .OrderByDescending(eb => eb.EffectiveDate)
            .FirstOrDefaultAsync(ct);
        var later = await db.EmployeeBenefits.AnyAsync(eb => eb.EmployeeId == v.EmployeeId && eb.Id != v.Id && eb.EffectiveDate > v.EffectiveDate, ct);
        if (prev != null)
        {
            // Bản trước nối liền tới bản kế tiếp (hoặc chạy tiếp nếu không còn bản sau).
            prev.EndDate = later ? v.EndDate : null;
            prev.IsActive = true;
        }
        db.EmployeeBenefits.Remove(v);
        await db.SaveChangesAsync(ct);
        return Ok(AppResponse<bool>.Success(true));
    }
}
