using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Commands.ShiftSalaryLevels;
using ZKTecoADMS.Application.Queries.ShiftSalaryLevels;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.ShiftSalaryLevels;
using ZKTecoADMS.Application.DTOs.Commons;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/shift-salary-levels")]
public class ShiftSalaryLevelsController(IMediator mediator, ZKTecoDbContext db) : AuthenticatedControllerBase
{
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireAnyModulePermission(ModulePermissionAction.View, "ShiftSalaryLevel", "ShiftSetup", "AttendanceSummary", "AttendanceByShift", "Payroll")]
    public async Task<ActionResult<AppResponse<PagedResult<ShiftSalaryLevelDto>>>> GetAll(
        [FromQuery] Guid? shiftTemplateId = null,
        [FromQuery] bool? isActive = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 100)
    {
        var query = new GetShiftSalaryLevelsQuery(RequiredStoreId, shiftTemplateId, isActive, page, pageSize);
        var result = await mediator.Send(query);
        if (!SeesAllLevels && result.IsSuccess && result.Data is { } paged)
        {
            var own = await OwnEmployeeIdAsync();
            var items = paged.Items.Where(l => AppliesTo(l, own)).ToList();
            result.Data = new PagedResult<ShiftSalaryLevelDto>(items, items.Count, paged.PageNumber, paged.PageSize);
        }
        return Ok(result);
    }

    [HttpGet("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireAnyModulePermission(ModulePermissionAction.View, "ShiftSalaryLevel", "ShiftSetup", "AttendanceSummary", "AttendanceByShift", "Payroll")]
    public async Task<ActionResult<AppResponse<ShiftSalaryLevelDto>>> GetById(Guid id)
    {
        var query = new GetShiftSalaryLevelByIdQuery(RequiredStoreId, id);
        var result = await mediator.Send(query);
        if (!SeesAllLevels && result.IsSuccess && result.Data is { } level && !AppliesTo(level, await OwnEmployeeIdAsync()))
            return Ok(AppResponse<ShiftSalaryLevelDto>.Fail("Không tìm thấy bậc lương"));
        return Ok(result);
    }

    /// <summary>Quản lý / kế toán xem mọi bậc lương; nhân viên chỉ thấy bậc áp cho mình (để tự tính công),
    /// không thấy mức lương của người khác.</summary>
    private bool SeesAllLevels => IsManager || IsAccountant;

    private Task<Guid?> OwnEmployeeIdAsync() =>
        db.Employees.AsNoTracking()
            .Where(e => e.ApplicationUserId == CurrentUserId && e.StoreId == RequiredStoreId)
            .Select(e => (Guid?)e.Id)
            .FirstOrDefaultAsync();

    /// <summary>EmployeeIds rỗng = áp cho mọi nhân viên; ngược lại là mảng JSON Id nhân viên.</summary>
    internal static bool AppliesTo(ShiftSalaryLevelDto level, Guid? employeeId)
    {
        if (string.IsNullOrWhiteSpace(level.EmployeeIds)) return true;
        List<string>? ids;
        try { ids = JsonSerializer.Deserialize<List<string>>(level.EmployeeIds); }
        catch (JsonException) { return false; }
        if (ids is null || ids.Count == 0) return true;
        return employeeId is Guid me
            && ids.Any(x => Guid.TryParse(x, out var g) && g == me);
    }

    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("ShiftSalaryLevel", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<ShiftSalaryLevelDto>>> Create([FromBody] CreateShiftSalaryLevelDto request)
    {
        var command = new CreateShiftSalaryLevelCommand(
            RequiredStoreId,
            request.ShiftTemplateId,
            request.LevelName,
            request.SortOrder,
            request.RateType,
            request.FixedRate,
            request.HourlyRate,
            request.Multiplier,
            request.ShiftAllowance,
            request.IsNightShift,
            request.EmployeeIds,
            request.Description);
        
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpPut("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("ShiftSalaryLevel", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<ShiftSalaryLevelDto>>> Update(Guid id, [FromBody] UpdateShiftSalaryLevelDto request)
    {
        var command = new UpdateShiftSalaryLevelCommand(
            RequiredStoreId,
            id,
            request.LevelName,
            request.SortOrder,
            request.RateType,
            request.FixedRate,
            request.HourlyRate,
            request.Multiplier,
            request.ShiftAllowance,
            request.IsNightShift,
            request.EmployeeIds,
            request.Description,
            request.IsActive);
        
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("ShiftSalaryLevel", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> Delete(Guid id)
    {
        var command = new DeleteShiftSalaryLevelCommand(RequiredStoreId, id);
        var result = await mediator.Send(command);
        return Ok(result);
    }
}

