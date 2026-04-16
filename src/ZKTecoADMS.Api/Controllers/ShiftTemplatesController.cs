using Microsoft.AspNetCore.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Commands.ShiftTemplates.CreateShiftTemplate;
using ZKTecoADMS.Application.Commands.ShiftTemplates.UpdateShiftTemplate;
using ZKTecoADMS.Application.Commands.ShiftTemplates.DeleteShiftTemplate;
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
            request.EarlyCheckInMinutes,
            request.LateGraceMinutes,
            request.EarlyLeaveGraceMinutes,
            request.OvertimeMinutesThreshold,
            request.ShiftType,
            request.Description,
            request.IsActive);   
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<List<ShiftTemplateDto>>>> GetShiftTemplates()
    {
        var query = new GetShiftTemplatesQuery(CurrentUserId, RequiredStoreId, IsManager, IsAdmin);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpPut("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
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
            request.EarlyCheckInMinutes,
            request.LateGraceMinutes,
            request.EarlyLeaveGraceMinutes,
            request.OvertimeMinutesThreshold,
            request.ShiftType,
            request.Description,
            request.IsActive);
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteShiftTemplate(Guid id)
    {
        var command = new DeleteShiftTemplateCommand(id);
        var result = await mediator.Send(command);
        return Ok(result);
    }
}
