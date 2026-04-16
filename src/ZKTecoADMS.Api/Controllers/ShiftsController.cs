using Microsoft.AspNetCore.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Commands.Shifts.CreateShift;
using ZKTecoADMS.Application.Commands.Shifts.DeleteShift;
using ZKTecoADMS.Application.Commands.Shifts.ApproveShift;
using ZKTecoADMS.Application.Commands.Shifts.RejectShift;
using ZKTecoADMS.Application.Commands.Shifts.UpdateShift;
using ZKTecoADMS.Application.Queries.Shifts.GetShiftsByEmployee;
using ZKTecoADMS.Application.Queries.Shifts.GetPendingShifts;
using ZKTecoADMS.Application.Queries.Shifts.GetShiftsByManager;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Shifts;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class ShiftsController(IMediator mediator, IDataScopeService dataScopeService) : AuthenticatedControllerBase
{
    [HttpGet("my-shifts")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<List<ShiftDto>>>> GetMyShifts([FromQuery]ShiftStatus? status, [FromQuery]Guid? employeeUserId, [FromQuery]PaginationRequest request)
    {
        var query = new GetShiftsByEmployeeQuery(RequiredStoreId, request, employeeUserId ?? CurrentUserId, status);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpPost]
    [Authorize(Policy = PolicyNames.HourlyEmployeeOnly)]
    public async Task<ActionResult<AppResponse<ShiftDto>>> CreateShift([FromBody] CreateShiftRequest request)
    {
        var command = new CreateShiftCommand(
            RequiredStoreId,
            request.EmployeeUserId ?? CurrentUserId,
            request.WorkingDays,
            request.MaximumAllowedLateMinutes,
            request.MaximumAllowedEarlyLeaveMinutes,
            request.BreakTimeMinutes,
            request.Description,
            IsManager
        );
        
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteShift(Guid id)
    {
        var command = new DeleteShiftCommand(RequiredStoreId, id);
        var result = await mediator.Send(command);
        return Ok(result);
    }

    // Manager endpoints - can view and approve/reject shifts
    [HttpGet("pending")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<PagedResult<ShiftDto>>>> GetPendingShifts([FromQuery]PaginationRequest request)
    {
        List<Guid>? subordinateUserIds = null;
        if (!IsAdmin)
            subordinateUserIds = await dataScopeService.GetSubordinateUserIdsAsync(CurrentUserId, RequiredStoreId);
        var query = new GetPendingShiftsQuery(RequiredStoreId, CurrentUserId, request, subordinateUserIds);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpGet("managed")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<PagedResult<ShiftDto>>>> GetManagedShifts([FromQuery] PaginationRequest request)
    {
        List<Guid>? subordinateUserIds = null;
        if (!IsAdmin)
            subordinateUserIds = await dataScopeService.GetSubordinateUserIdsAsync(CurrentUserId, RequiredStoreId);
        var query = new GetShiftsByManagerQuery(RequiredStoreId, CurrentUserId, request, subordinateUserIds);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpPost("{id}/approve")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<ShiftDto>>> ApproveShift(Guid id)
    {
        var command = new ApproveShiftCommand(RequiredStoreId, id, CurrentUserId);
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpPost("{id}/reject")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<ShiftDto>>> RejectShift(Guid id, [FromBody] RejectShiftRequest request)
    {
        var command = new RejectShiftCommand(RequiredStoreId, id, CurrentUserId, request.RejectionReason);
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpPut("{id}/times")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<ShiftDto>>> UpdateShiftTimes(Guid id, [FromBody] UpdateShiftTimesRequest request)
    {
        var command = new UpdateShiftCommand(RequiredStoreId, id, CurrentUserId, request.CheckInTime, request.CheckOutTime);
        var result = await mediator.Send(command);
        return Ok(result);
    }
}
