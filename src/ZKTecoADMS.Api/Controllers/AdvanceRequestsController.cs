using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Commands.AdvanceRequests;
using ZKTecoADMS.Application.Queries.AdvanceRequests;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.AdvanceRequests;
using ZKTecoADMS.Application.DTOs.Commons;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AdvanceRequestsController(
    IMediator mediator,
    ZKTecoDbContext context,
    IModulePermissionService modulePermissionService,
    ISystemNotificationService notificationService) : AuthenticatedControllerBase
{
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireAnyModulePermission(ModulePermissionAction.View, "AdvanceRequests", "AdvanceReport")]
    public async Task<ActionResult<AppResponse<PagedResult<AdvanceRequestDto>>>> GetAdvanceRequests(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 10,
        [FromQuery] Guid? employeeUserId = null,
        [FromQuery] AdvanceRequestStatus? status = null,
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null)
    {
        if (IsEmployee && !IsManager)
            employeeUserId = CurrentUserId;

        var query = new GetAdvanceRequestsQuery(RequiredStoreId, page, pageSize, employeeUserId, status, fromDate, toDate);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpGet("my")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireAnyModulePermission(ModulePermissionAction.View, "AdvanceRequests", "AdvanceReport")]
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
    [RequireModulePermission("AdvanceRequests", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<AdvanceRequestDto>>> GetAdvanceRequestById(Guid id)
    {
        var query = new GetAdvanceRequestByIdQuery(RequiredStoreId, id);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("AdvanceRequests", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<AdvanceRequestDto>>> CreateAdvanceRequest([FromBody] CreateAdvanceRequestDto request)
    {
        Guid? employeeUserId = request.EmployeeUserId
            ?? (request.EmployeeId == null ? CurrentUserId : (Guid?)null);

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
    [RequireModulePermission("AdvanceRequests", ModulePermissionAction.Approve)]
    public async Task<ActionResult<AppResponse<AdvanceRequestDto>>> ApproveAdvanceRequest(
        Guid id,
        [FromBody] ApproveAdvanceRequestDto request)
    {
        var storeId = RequiredStoreId;
        var command = new ApproveAdvanceRequestCommand(
            storeId,
            id,
            CurrentUserId,
            request.IsApproved,
            request.RejectionReason,
            request.ApprovedAmount);

        var result = await mediator.Send(command);

        try
        {
            if (result.IsSuccess && request.IsApproved
                && result.Data?.Status == AdvanceRequestStatus.Approved)
            {
                await TryCreateAdvancePendingCashAsync(id, storeId);
            }
        }
        catch { /* finance hook is best-effort */ }

        return Ok(result);
    }

    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("AdvanceRequests", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteAdvanceRequest(Guid id)
    {
        var command = new DeleteAdvanceRequestCommand(RequiredStoreId, id);
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpPost("{id}/undo-approve")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("AdvanceRequests", ModulePermissionAction.Approve)]
    public async Task<ActionResult<AppResponse<AdvanceRequestDto>>> UndoApproveAdvanceRequest(Guid id)
    {
        var storeId = RequiredStoreId;
        var command = new UndoApproveAdvanceRequestCommand(storeId, id, CurrentUserId);
        var result = await mediator.Send(command);

        try
        {
            if (result.IsSuccess)
            {
                var linked = await PaymentFinanceHelper.ResolveLinkedAsync(
                    context, storeId, PaymentFinanceHelper.AdvanceNote(id));
                if (linked != null && !linked.IsPaid)
                {
                    PaymentFinanceHelper.CancelLinkedCashTransaction(linked, "Hoàn duyệt yêu cầu ứng lương");
                    await context.SaveChangesAsync();
                }
            }
        }
        catch { /* finance hook is best-effort */ }

        return Ok(result);
    }

    [HttpPost("{id}/cancel")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("AdvanceRequests", ModulePermissionAction.Create)]
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
    [RequireModulePermission("AdvanceRequests", ModulePermissionAction.Approve)]
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
    [RequireModulePermission("AdvanceRequests", ModulePermissionAction.Approve)]
    public async Task<ActionResult<AppResponse<BulkResultDto>>> BulkApprove([FromBody] BulkApproveDto request)
    {
        var storeId = RequiredStoreId;
        int success = 0, failed = 0;
        foreach (var id in request.Ids)
        {
            try
            {
                var command = new ApproveAdvanceRequestCommand(storeId, id, CurrentUserId, true, null);
                var result = await mediator.Send(command);
                if (result.IsSuccess)
                {
                    success++;
                    if (result.Data?.Status == AdvanceRequestStatus.Approved)
                        await TryCreateAdvancePendingCashAsync(id, storeId);
                }
                else failed++;
            }
            catch { failed++; }
        }
        return Ok(AppResponse<BulkResultDto>.Success(new BulkResultDto(success, failed)));
    }

    [HttpPost("bulk-reject")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("AdvanceRequests", ModulePermissionAction.Approve)]
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
    [RequireModulePermission("AdvanceRequests", ModulePermissionAction.Approve)]
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

    private async Task TryCreateAdvancePendingCashAsync(Guid advanceId, Guid storeId)
    {
        var advance = await context.AdvanceRequests
            .Include(a => a.Employee)
            .Include(a => a.EmployeeUser)
            .FirstOrDefaultAsync(a => a.Id == advanceId && a.StoreId == storeId);
        if (advance == null) return;

        var cashTx = await PaymentFinanceHelper.CreateAdvancePendingOnApproveAsync(
            context, advance, storeId, CurrentUserId);
        if (cashTx == null) return;

        await CashTransactionNotificationHelper.NotifyOnCreatedAsync(
            context, modulePermissionService, notificationService,
            cashTx, CurrentUserId, storeId);

        try
        {
            if (advance.EmployeeUserId.HasValue && advance.EmployeeUserId != CurrentUserId)
            {
                var payoutAmount = advance.ApprovedAmount ?? advance.Amount;
                await notificationService.CreateAndSendAsync(
                    advance.EmployeeUserId.Value,
                    NotificationType.Info,
                    "Ứng lương chờ thanh toán",
                    $"Yêu cầu ứng lương {payoutAmount:N0}đ đã được duyệt, đang chờ kế toán thanh toán.",
                    relatedEntityId: advance.Id,
                    relatedEntityType: "AdvanceRequest",
                    fromUserId: CurrentUserId,
                    categoryCode: "payroll",
                    storeId: storeId);
            }
        }
        catch { /* best-effort */ }
    }
}
