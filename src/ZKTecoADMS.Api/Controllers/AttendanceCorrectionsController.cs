using Microsoft.AspNetCore.Authorization;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Commands.AttendanceCorrections;
using ZKTecoADMS.Application.Queries.AttendanceCorrections;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.AttendanceCorrections;
using ZKTecoADMS.Application.DTOs.Commons;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AttendanceCorrectionsController(IMediator mediator) : AuthenticatedControllerBase
{
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.View, "AttendanceApproval", "AttendanceCorrection")]
    public async Task<ActionResult<AppResponse<PagedResult<AttendanceCorrectionRequestDto>>>> GetAttendanceCorrections(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 10,
        [FromQuery] Guid? employeeUserId = null,
        [FromQuery] CorrectionStatus? status = null,
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null,
        [FromQuery] bool filterByWorkDate = false,
        [FromQuery] Guid? pendingForApproverId = null,
        [FromQuery] CorrectionAction? action = null)
    {
        var query = new GetAttendanceCorrectionsQuery(
            RequiredStoreId, page, pageSize, employeeUserId, status, fromDate, toDate,
            filterByWorkDate, pendingForApproverId, action);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpGet("my")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("AttendanceCorrection", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<PagedResult<AttendanceCorrectionRequestDto>>>> GetMyAttendanceCorrections(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 10,
        [FromQuery] CorrectionStatus? status = null)
    {
        var query = new GetMyAttendanceCorrectionsQuery(RequiredStoreId, CurrentUserId, page, pageSize, status);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpGet("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("AttendanceCorrection", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<AttendanceCorrectionRequestDto>>> GetAttendanceCorrectionById(Guid id)
    {
        var query = new GetAttendanceCorrectionByIdQuery(RequiredStoreId, id);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("AttendanceCorrection", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<AttendanceCorrectionRequestDto>>> CreateAttendanceCorrection([FromBody] CreateAttendanceCorrectionDto request)
    {
        var command = new CreateAttendanceCorrectionCommand(
            RequiredStoreId,
            CurrentUserId,
            request.EmployeeUserId,
            request.EmployeeName,
            request.EmployeeCode,
            request.Pin,
            request.AttendanceId,
            request.Action,
            request.OldDate,
            request.OldTime,
            request.NewDate,
            request.NewTime,
            request.NewPunchType,
            request.Reason);
        
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpPost("{id}/approve")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.Approve, "AttendanceApproval", "AttendanceCorrection")]
    public async Task<ActionResult<AppResponse<AttendanceCorrectionRequestDto>>> ApproveAttendanceCorrection(
        Guid id, 
        [FromBody] ApproveAttendanceCorrectionDto request)
    {
        var command = new ApproveAttendanceCorrectionCommand(
            RequiredStoreId,
            id,
            CurrentUserId,
            request.IsApproved,
            request.ApproverNote);
        
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("AttendanceCorrection", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteAttendanceCorrection(Guid id)
    {
        var command = new DeleteAttendanceCorrectionCommand(RequiredStoreId, id);
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpPost("{id}/undo-approve")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.Approve, "AttendanceApproval", "AttendanceCorrection")]
    public async Task<ActionResult<AppResponse<AttendanceCorrectionRequestDto>>> UndoApproveAttendanceCorrection(Guid id)
    {
        var command = new UndoApproveAttendanceCorrectionCommand(RequiredStoreId, id, CurrentUserId);
        var result = await mediator.Send(command);
        return Ok(result);
    }
}
