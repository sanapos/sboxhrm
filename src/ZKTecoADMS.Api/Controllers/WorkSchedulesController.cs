using Microsoft.AspNetCore.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Commands.WorkSchedules;
using ZKTecoADMS.Application.Queries.WorkSchedules;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.WorkSchedules;
using ZKTecoADMS.Application.DTOs.Commons;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class WorkSchedulesController(IMediator mediator) : AuthenticatedControllerBase
{
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<PagedResult<WorkScheduleDto>>>> GetWorkSchedules(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 10,
        [FromQuery] Guid? employeeUserId = null,
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null,
        [FromQuery] Guid? shiftId = null,
        [FromQuery] bool? isDayOff = null)
    {
        var query = new GetWorkSchedulesQuery(RequiredStoreId, page, pageSize, employeeUserId, fromDate, toDate, shiftId, isDayOff);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpGet("my")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<PagedResult<WorkScheduleDto>>>> GetMyWorkSchedules(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 10,
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null)
    {
        var query = new GetMyWorkSchedulesQuery(RequiredStoreId, CurrentUserId, page, pageSize, fromDate, toDate);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpGet("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<WorkScheduleDto>>> GetWorkScheduleById(Guid id)
    {
        var query = new GetWorkScheduleByIdQuery(RequiredStoreId, id);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<WorkScheduleDto>>> CreateWorkSchedule([FromBody] CreateWorkScheduleDto request)
    {
        var command = new CreateWorkScheduleCommand(
            RequiredStoreId,
            request.EmployeeUserId,
            request.ShiftId,
            request.Date,
            request.StartTime,
            request.EndTime,
            request.IsDayOff,
            request.Note);
        
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpPost("bulk")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<List<WorkScheduleDto>>>> BulkCreateWorkSchedules([FromBody] BulkCreateWorkScheduleDto request)
    {
        var command = new BulkCreateWorkSchedulesCommand(
            RequiredStoreId,
            request.EmployeeUserIds,
            request.ShiftId,
            request.StartDate,
            request.EndDate,
            request.WorkDays);
        
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpPut("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<WorkScheduleDto>>> UpdateWorkSchedule(Guid id, [FromBody] UpdateWorkScheduleDto request)
    {
        var command = new UpdateWorkScheduleCommand(
            RequiredStoreId,
            id,
            request.ShiftId,
            request.StartTime,
            request.EndTime,
            request.IsDayOff,
            request.Note);
        
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteWorkSchedule(Guid id)
    {
        var command = new DeleteWorkScheduleCommand(RequiredStoreId, id);
        var result = await mediator.Send(command);
        return Ok(result);
    }

    // Schedule Registrations
    [HttpGet("registrations/my")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<PagedResult<ScheduleRegistrationDto>>>> GetMyScheduleRegistrations(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null)
    {
        var query = new GetMyScheduleRegistrationsQuery(RequiredStoreId, CurrentUserId, page, pageSize, fromDate, toDate);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpGet("registrations")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<PagedResult<ScheduleRegistrationDto>>>> GetScheduleRegistrations(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 10,
        [FromQuery] Guid? employeeUserId = null,
        [FromQuery] ScheduleRegistrationStatus? status = null,
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null)
    {
        var query = new GetScheduleRegistrationsQuery(RequiredStoreId, page, pageSize, employeeUserId, status, fromDate, toDate);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpPost("registrations")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<ScheduleRegistrationDto>>> CreateScheduleRegistration([FromBody] CreateScheduleRegistrationDto request)
    {
        // Use EmployeeUserId from request if provided (admin submitting on behalf of employee), otherwise use current user
        var employeeUserId = request.EmployeeUserId != Guid.Empty ? request.EmployeeUserId : CurrentUserId;
        var command = new CreateScheduleRegistrationCommand(
            RequiredStoreId,
            employeeUserId,
            request.Date,
            request.ShiftId,
            request.IsDayOff,
            request.Note);
        
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpPost("registrations/{id}/approve")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<ScheduleRegistrationDto>>> ApproveScheduleRegistration(
        Guid id, 
        [FromBody] ApproveScheduleRegistrationDto request)
    {
        var command = new ApproveScheduleRegistrationCommand(
            RequiredStoreId,
            id,
            CurrentUserId,
            request.IsApproved,
            request.RejectionReason);
        
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpDelete("registrations/{id}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteScheduleRegistration(Guid id)
    {
        var command = new DeleteScheduleRegistrationCommand(RequiredStoreId, id);
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpPost("registrations/{id}/undo-approval")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<bool>>> UndoScheduleRegistrationApproval(Guid id)
    {
        var command = new UndoScheduleRegistrationApprovalCommand(RequiredStoreId, id);
        var result = await mediator.Send(command);
        return Ok(result);
    }

    // ── Notifications ──
    [HttpPost("send-reminder")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<int>>> SendScheduleReminder([FromBody] SendScheduleReminderDto request)
    {
        var command = new SendScheduleReminderCommand(
            RequiredStoreId, CurrentUserId,
            request.FromDate, request.ToDate, request.Department);
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpPost("request-coverage")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<int>>> RequestShiftCoverage([FromBody] RequestShiftCoverageDto request)
    {
        var command = new RequestShiftCoverageCommand(
            RequiredStoreId, CurrentUserId,
            request.ShiftTemplateId, request.Date,
            request.Department, request.Message);
        var result = await mediator.Send(command);
        return Ok(result);
    }

    // ── Staffing Quotas ──
    [HttpGet("staffing-quotas")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<List<ShiftStaffingQuotaDto>>>> GetStaffingQuotas()
    {
        var query = new GetShiftStaffingQuotasQuery(RequiredStoreId);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpPost("staffing-quotas")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<ShiftStaffingQuotaDto>>> UpsertStaffingQuota([FromBody] UpsertShiftStaffingQuotaDto request)
    {
        var command = new UpsertShiftStaffingQuotaCommand(
            RequiredStoreId, request.ShiftTemplateId, request.Department,
            request.MinEmployees, request.MaxEmployees, request.WarningThreshold);
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpDelete("staffing-quotas/{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteStaffingQuota(Guid id)
    {
        var command = new DeleteShiftStaffingQuotaCommand(RequiredStoreId, id);
        var result = await mediator.Send(command);
        return Ok(result);
    }
}
