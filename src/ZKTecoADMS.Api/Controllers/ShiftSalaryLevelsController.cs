using Microsoft.AspNetCore.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Commands.ShiftSalaryLevels;
using ZKTecoADMS.Application.Queries.ShiftSalaryLevels;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.ShiftSalaryLevels;
using ZKTecoADMS.Application.DTOs.Commons;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/shift-salary-levels")]
public class ShiftSalaryLevelsController(IMediator mediator) : AuthenticatedControllerBase
{
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<PagedResult<ShiftSalaryLevelDto>>>> GetAll(
        [FromQuery] Guid? shiftTemplateId = null,
        [FromQuery] bool? isActive = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 100)
    {
        var query = new GetShiftSalaryLevelsQuery(RequiredStoreId, shiftTemplateId, isActive, page, pageSize);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpGet("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<ShiftSalaryLevelDto>>> GetById(Guid id)
    {
        var query = new GetShiftSalaryLevelByIdQuery(RequiredStoreId, id);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
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
    [Authorize(Policy = PolicyNames.AtLeastManager)]
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
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<bool>>> Delete(Guid id)
    {
        var command = new DeleteShiftSalaryLevelCommand(RequiredStoreId, id);
        var result = await mediator.Send(command);
        return Ok(result);
    }
}
