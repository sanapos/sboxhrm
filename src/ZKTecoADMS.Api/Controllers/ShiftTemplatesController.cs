using Microsoft.AspNetCore.Authorization;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Commands.ShiftTemplates.CreateShiftTemplate;
using ZKTecoADMS.Application.Commands.ShiftTemplates.UpdateShiftTemplate;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Helpers;
using ZKTecoADMS.Application.Queries.ShiftTemplates.GetShiftTemplates;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Shifts;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/shifts/templates")]
public class ShiftTemplatesController(IMediator mediator) : AuthenticatedControllerBase
{
    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.Create, "ShiftTemplate", "ShiftSetup")]
    public async Task<ActionResult<AppResponse<ShiftTemplateDto>>> CreateShiftTemplate([FromBody] CreateShiftTemplateRequest request)
    {
        var command = new CreateShiftTemplateCommand(
            CurrentUserId,
            RequiredStoreId,
            request.Name,
            request.Code,
            request.StartTime,
            request.EndTime,
            request.MaximumAllowedLateMinutes,
            request.MaximumAllowedEarlyLeaveMinutes,
            request.BreakTimeMinutes,
            request.LunchBreakStartTime,
            request.LunchBreakEndTime,
            request.EarlyCheckInMinutes,
            request.LateGraceMinutes,
            request.EarlyLeaveGraceMinutes,
            request.OvertimeMinutesThreshold,
            request.EarlyOvertimeMinutesThreshold,
            request.ShiftType,
            request.Description,
            request.IsActive);   
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireAnyModulePermission(ModulePermissionAction.View, "ShiftTemplate", "ShiftSetup", "AttendanceSummary", "AttendanceByShift", "Attendance")]
    public async Task<ActionResult<AppResponse<List<ShiftTemplateDto>>>> GetShiftTemplates()
    {
        var query = new GetShiftTemplatesQuery(CurrentUserId, RequiredStoreId, IsManager, IsAdmin);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpPut("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("ShiftTemplate", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<ShiftTemplateDto>>> UpdateShiftTemplate(Guid id, [FromBody] UpdateShiftTemplateRequest request)
    {
        var command = new UpdateShiftTemplateCommand(
            id,
            request.Name,
            request.Code,
            request.StartTime,
            request.EndTime,
            request.MaximumAllowedLateMinutes,
            request.MaximumAllowedEarlyLeaveMinutes,
            request.BreakTimeMinutes,
            request.LunchBreakStartTime,
            request.LunchBreakEndTime,
            request.EarlyCheckInMinutes,
            request.LateGraceMinutes,
            request.EarlyLeaveGraceMinutes,
            request.OvertimeMinutesThreshold,
            request.EarlyOvertimeMinutesThreshold,
            request.ShiftType,
            request.Description,
            request.IsActive);
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.Delete, "ShiftTemplate", "ShiftSetup")]
    public async Task<ActionResult<AppResponse<bool>>> DeleteShiftTemplate(Guid id, [FromServices] ZKTecoDbContext db)
    {
        // Chỉ xóa ca chưa phát sinh dữ liệu; gỡ ca khỏi thiết lập lương (mức lương ca, phụ cấp theo ca).
        var (ok, error, _) = await ShiftTemplateUsageHelper.DeleteAsync(db, RequiredStoreId, id);
        return Ok(ok ? AppResponse<bool>.Success(true) : AppResponse<bool>.Error(error ?? "Không xóa được ca"));
    }

    // ─── Ca mẫu v2: mức sử dụng, nhân bản, ngừng dùng ────────────────

    static object UsageDto(ShiftTemplateUsage u) => new
    {
        shiftId = u.ShiftId,
        schedules = u.Schedules,
        upcomingSchedules = u.UpcomingSchedules,
        registrations = u.Registrations,
        leaves = u.Leaves,
        swaps = u.Swaps,
        penalties = u.Penalties,
        meals = u.Meals,
        employees = u.Employees,
        lastUsedDate = u.LastUsedDate,
        salaryLevels = u.SalaryLevels,
        allowances = u.Allowances,
        staffingQuotas = u.StaffingQuotas,
        mealSessions = u.MealSessions,
        hasData = u.HasData,
        canDelete = !u.HasData,
        dataSummary = ShiftTemplateUsageHelper.Describe(u),
    };

    /// <summary>Mức sử dụng của mọi ca: số lịch, nhân viên, cấu hình lương đang gắn.</summary>
    [HttpGet("usage")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.View, "ShiftTemplate", "ShiftSetup")]
    public async Task<ActionResult<AppResponse<object>>> Usage([FromServices] ZKTecoDbContext db)
    {
        var map = await ShiftTemplateUsageHelper.ComputeAsync(db, RequiredStoreId);
        return Ok(AppResponse<object>.Success(map.Values.Select(UsageDto).ToList()));
    }

    [HttpGet("{id:guid}/usage")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.View, "ShiftTemplate", "ShiftSetup")]
    public async Task<ActionResult<AppResponse<object>>> UsageOne(Guid id, [FromServices] ZKTecoDbContext db)
    {
        var map = await ShiftTemplateUsageHelper.ComputeAsync(db, RequiredStoreId, id);
        return map.TryGetValue(id, out var u)
            ? Ok(AppResponse<object>.Success(UsageDto(u)))
            : Ok(AppResponse<object>.Error("Không tìm thấy ca"));
    }

    /// <summary>Nhân bản ca (giữ mọi thông số chấm công, không chép lương ca).</summary>
    [HttpPost("{id:guid}/duplicate")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.Create, "ShiftTemplate", "ShiftSetup")]
    public async Task<ActionResult<AppResponse<object>>> Duplicate(Guid id, [FromServices] ZKTecoDbContext db)
    {
        var storeId = RequiredStoreId;
        var src = await db.ShiftTemplates.AsNoTracking().FirstOrDefaultAsync(t => t.Id == id && t.StoreId == storeId);
        if (src == null) return Ok(AppResponse<object>.Error("Không tìm thấy ca"));
        var names = await db.ShiftTemplates.AsNoTracking().Where(t => t.StoreId == storeId).Select(t => t.Name).ToListAsync();
        var copy = new ShiftTemplate
        {
            Id = Guid.NewGuid(),
            ManagerId = CurrentUserId,
            StoreId = storeId,
            Name = ShiftTemplateUsageHelper.CopyName(src.Name, names),
            Code = string.IsNullOrWhiteSpace(src.Code) ? null : (src.Code.Length > 40 ? src.Code[..40] : src.Code) + "-2",
            StartTime = src.StartTime,
            EndTime = src.EndTime,
            MaximumAllowedLateMinutes = src.MaximumAllowedLateMinutes,
            MaximumAllowedEarlyLeaveMinutes = src.MaximumAllowedEarlyLeaveMinutes,
            BreakTimeMinutes = src.BreakTimeMinutes,
            LunchBreakStartTime = src.LunchBreakStartTime,
            LunchBreakEndTime = src.LunchBreakEndTime,
            EarlyCheckInMinutes = src.EarlyCheckInMinutes,
            LateGraceMinutes = src.LateGraceMinutes,
            EarlyLeaveGraceMinutes = src.EarlyLeaveGraceMinutes,
            OvertimeMinutesThreshold = src.OvertimeMinutesThreshold,
            EarlyOvertimeMinutesThreshold = src.EarlyOvertimeMinutesThreshold,
            ShiftType = src.ShiftType,
            Description = src.Description,
            IsActive = true,
        };
        db.ShiftTemplates.Add(copy);
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { id = copy.Id, name = copy.Name }));
    }

    public sealed class ShiftActiveRequest
    {
        public bool IsActive { get; set; }
    }

    /// <summary>Ngừng dùng / dùng lại ca: ẩn khỏi xếp ca mới, giữ nguyên lịch và lương đã có.</summary>
    [HttpPatch("{id:guid}/active")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.Edit, "ShiftTemplate", "ShiftSetup")]
    public async Task<ActionResult<AppResponse<bool>>> SetActive(Guid id, [FromBody] ShiftActiveRequest req, [FromServices] ZKTecoDbContext db)
    {
        var storeId = RequiredStoreId;
        var tpl = await db.ShiftTemplates.AsTracking().FirstOrDefaultAsync(t => t.Id == id && t.StoreId == storeId);
        if (tpl == null) return Ok(AppResponse<bool>.Error("Không tìm thấy ca"));
        tpl.IsActive = req.IsActive;
        tpl.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();
        return Ok(AppResponse<bool>.Success(true));
    }
}

