using Microsoft.AspNetCore.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Commands.AdvanceRequests;
using ZKTecoADMS.Application.Queries.AdvanceRequests;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.AdvanceRequests;
using ZKTecoADMS.Application.DTOs.Commons;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AdvanceRequestsController(IMediator mediator) : AuthenticatedControllerBase
{
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<PagedResult<AdvanceRequestDto>>>> GetAdvanceRequests(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 10,
        [FromQuery] Guid? employeeUserId = null,
        [FromQuery] AdvanceRequestStatus? status = null,
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null)
    {
        var query = new GetAdvanceRequestsQuery(RequiredStoreId, page, pageSize, employeeUserId, status, fromDate, toDate);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpGet("my")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<PagedResult<AdvanceRequestDto>>>> GetMyAdvanceRequests(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 10,
        [FromQuery] AdvanceRequestStatus? status = null)
    {
        var query = new GetMyAdvanceRequestsQuery(RequiredStoreId, CurrentUserId, page, pageSize, status);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpGet("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<AdvanceRequestDto>>> GetAdvanceRequestById(Guid id)
    {
        var query = new GetAdvanceRequestByIdQuery(RequiredStoreId, id);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<AdvanceRequestDto>>> CreateAdvanceRequest([FromBody] CreateAdvanceRequestDto request)
    {
        var employeeUserId = request.EmployeeUserId ?? CurrentUserId;
        var command = new CreateAdvanceRequestCommand(
            RequiredStoreId,
            employeeUserId,
            request.Amount,
            request.Reason,
            request.Note,
            request.ForMonth,
            request.ForYear,
            request.EmployeeId);
        
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpPost("{id}/approve")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<AdvanceRequestDto>>> ApproveAdvanceRequest(
        Guid id, 
        [FromBody] ApproveAdvanceRequestDto request)
    {
        var command = new ApproveAdvanceRequestCommand(
            RequiredStoreId,
            id,
            CurrentUserId,
            request.IsApproved,
            request.RejectionReason);
        
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteAdvanceRequest(Guid id)
    {
        var command = new DeleteAdvanceRequestCommand(RequiredStoreId, id);
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpPost("{id}/undo-approve")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<AdvanceRequestDto>>> UndoApproveAdvanceRequest(Guid id)
    {
        var command = new UndoApproveAdvanceRequestCommand(
            RequiredStoreId,
            id,
            CurrentUserId);
        
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpPost("{id}/cancel")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<bool>>> CancelAdvanceRequest(Guid id)
    {
        var command = new CancelAdvanceRequestCommand(
            RequiredStoreId,
            id,
            CurrentUserId,
            User.IsInRole("Manager") || User.IsInRole("Admin"));
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpPost("{id}/pay")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<AdvanceRequestDto>>> PayAdvanceRequest(Guid id, [FromBody] PayAdvanceRequestDto? request = null)
    {
        var command = new PayAdvanceRequestCommand(
            RequiredStoreId,
            id,
            CurrentUserId,
            request?.PaymentMethod);
        
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpPost("bulk-approve")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<BulkResultDto>>> BulkApprove([FromBody] BulkApproveDto request)
    {
        int success = 0, failed = 0;
        foreach (var id in request.Ids)
        {
            try
            {
                var command = new ApproveAdvanceRequestCommand(RequiredStoreId, id, CurrentUserId, true, null);
                var result = await mediator.Send(command);
                if (result.IsSuccess) success++; else failed++;
            }
            catch { failed++; }
        }
        return Ok(AppResponse<BulkResultDto>.Success(new BulkResultDto(success, failed)));
    }

    [HttpPost("bulk-reject")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<BulkResultDto>>> BulkReject([FromBody] BulkRejectDto request)
    {
        int success = 0, failed = 0;
        foreach (var id in request.Ids)
        {
            try
            {
                var command = new ApproveAdvanceRequestCommand(RequiredStoreId, id, CurrentUserId, false, request.Reason);
                var result = await mediator.Send(command);
                if (result.IsSuccess) success++; else failed++;
            }
            catch { failed++; }
        }
        return Ok(AppResponse<BulkResultDto>.Success(new BulkResultDto(success, failed)));
    }

    [HttpPost("bulk-pay")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<BulkResultDto>>> BulkPay([FromBody] BulkPayDto request)
    {
        int success = 0, failed = 0;
        foreach (var id in request.Ids)
        {
            try
            {
                var command = new PayAdvanceRequestCommand(RequiredStoreId, id, CurrentUserId, request.PaymentMethod);
                var result = await mediator.Send(command);
                if (result.IsSuccess) success++; else failed++;
            }
            catch { failed++; }
        }
        return Ok(AppResponse<BulkResultDto>.Success(new BulkResultDto(success, failed)));
    }
}
