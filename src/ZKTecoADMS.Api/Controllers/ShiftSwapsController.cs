using Microsoft.AspNetCore.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Commands.ShiftSwaps.CreateShiftSwap;
using ZKTecoADMS.Application.Commands.ShiftSwaps.RespondToSwap;
using ZKTecoADMS.Application.Commands.ShiftSwaps.ApproveSwap;
using ZKTecoADMS.Application.Commands.ShiftSwaps.CancelSwap;
using ZKTecoADMS.Application.Queries.ShiftSwaps.GetShiftSwaps;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.ShiftSwaps;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class ShiftSwapsController(IMediator mediator) : AuthenticatedControllerBase
{
    /// <summary>
    /// Lấy danh sách yêu cầu đổi ca
    /// </summary>
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<PagedResult<ShiftSwapRequestDto>>>> GetShiftSwaps(
        [FromQuery] PaginationRequest request,
        [FromQuery] ShiftSwapStatus? status = null)
    {
        var query = new GetShiftSwapsQuery(RequiredStoreId, CurrentUserId, IsManager, request, status);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    /// <summary>
    /// Lấy các yêu cầu đang chờ xác nhận từ đồng nghiệp (cho user hiện tại)
    /// </summary>
    [HttpGet("pending-for-me")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<PagedResult<ShiftSwapRequestDto>>>> GetPendingForMe(
        [FromQuery] PaginationRequest request)
    {
        // This returns requests where current user is the target and status is pending
        var query = new GetShiftSwapsQuery(RequiredStoreId, CurrentUserId, false, request, ShiftSwapStatus.Pending);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    /// <summary>
    /// Lấy các yêu cầu chờ quản lý duyệt
    /// </summary>
    [HttpGet("pending-approval")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<PagedResult<ShiftSwapRequestDto>>>> GetPendingApproval(
        [FromQuery] PaginationRequest request)
    {
        var query = new GetShiftSwapsQuery(RequiredStoreId, CurrentUserId, true, request, ShiftSwapStatus.TargetAccepted);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    /// <summary>
    /// Tạo yêu cầu đổi ca mới
    /// </summary>
    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<ShiftSwapRequestDto>>> CreateShiftSwap(
        [FromBody] CreateShiftSwapRequestDto request)
    {
        var command = new CreateShiftSwapCommand(
            RequiredStoreId,
            CurrentUserId,
            request.TargetUserId,
            request.RequesterDate,
            request.RequesterShiftId,
            request.TargetDate,
            request.TargetShiftId,
            request.Reason);

        var result = await mediator.Send(command);
        return Ok(result);
    }

    /// <summary>
    /// Phản hồi yêu cầu đổi ca (từ người được yêu cầu)
    /// </summary>
    [HttpPost("{id}/respond")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<bool>>> RespondToSwap(
        Guid id,
        [FromBody] RespondShiftSwapDto request)
    {
        var command = new RespondToSwapCommand(
            RequiredStoreId,
            id,
            CurrentUserId,
            request.Accept,
            request.RejectionReason);

        var result = await mediator.Send(command);
        return Ok(result);
    }

    /// <summary>
    /// Quản lý phê duyệt/từ chối yêu cầu đổi ca
    /// </summary>
    [HttpPost("{id}/approve")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<bool>>> ApproveSwap(
        Guid id,
        [FromBody] ManagerDecisionDto request)
    {
        var command = new ApproveSwapCommand(
            RequiredStoreId,
            id,
            CurrentUserId,
            request.Approve,
            request.RejectionReason,
            request.Note);

        var result = await mediator.Send(command);
        return Ok(result);
    }

    /// <summary>
    /// Hủy yêu cầu đổi ca (chỉ người tạo mới được hủy)
    /// </summary>
    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<bool>>> CancelSwap(Guid id)
    {
        var command = new CancelSwapCommand(RequiredStoreId, id, CurrentUserId);
        var result = await mediator.Send(command);
        return Ok(result);
    }
}
