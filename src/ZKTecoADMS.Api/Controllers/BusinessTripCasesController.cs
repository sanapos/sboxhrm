using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Commands.BusinessTrip;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.BusinessTrip;
using ZKTecoADMS.Application.DTOs.Commons;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Application.Queries.BusinessTrip;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class BusinessTripCasesController(
    IMediator mediator,
    ZKTecoDbContext context,
    ILogger<BusinessTripCasesController> logger) : AuthenticatedControllerBase
{
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("BusinessTripExpense", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<PagedResult<BusinessTripCaseDto>>>> GetCases(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] Guid? employeeUserId = null,
        [FromQuery] BusinessTripCaseStatus? status = null,
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null,
        [FromQuery] Guid? categoryId = null)
    {
        if (!IsBusinessTripPrivileged)
            employeeUserId = CurrentUserId;

        var result = await mediator.Send(new GetBusinessTripCasesQuery(
            RequiredStoreId, page, pageSize, employeeUserId, status, fromDate, toDate, categoryId));
        return Ok(result);
    }

    [HttpGet("pending-approval")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("BusinessTripExpense", ModulePermissionAction.Approve)]
    public async Task<ActionResult<AppResponse<List<BusinessTripCaseDto>>>> GetPendingApprovals(
        [FromQuery] bool settlementOnly = false)
    {
        var result = await mediator.Send(new GetPendingBusinessTripApprovalsQuery(
            RequiredStoreId, CurrentUserId, settlementOnly));
        return Ok(result);
    }

    [HttpGet("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("BusinessTripExpense", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<BusinessTripCaseDto>>> GetById(Guid id)
    {
        var result = await mediator.Send(new GetBusinessTripCaseByIdQuery(
            RequiredStoreId, id, CurrentUserId, IsBusinessTripPrivileged));
        return Ok(result);
    }

    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("BusinessTripExpense", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<BusinessTripCaseDto>>> CreateCase([FromBody] CreateBusinessTripCaseDto dto)
    {
        var result = await mediator.Send(new CreateBusinessTripCaseCommand(
            RequiredStoreId,
            CurrentUserId,
            dto.EmployeeUserId ?? (dto.EmployeeId == null ? CurrentUserId : null),
            dto.EmployeeId,
            dto.Title,
            dto.Destination,
            dto.TripFromDate,
            dto.TripToDate,
            dto.Note,
            IsBusinessTripPrivileged));
        return Ok(result);
    }

    [HttpPut("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("BusinessTripExpense", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<BusinessTripCaseDto>>> UpdateCase(
        Guid id, [FromBody] UpdateBusinessTripCaseDto dto)
    {
        var result = await mediator.Send(new UpdateBusinessTripCaseCommand(
            RequiredStoreId,
            id,
            CurrentUserId,
            IsBusinessTripPrivileged,
            dto.Title,
            dto.Destination,
            dto.TripFromDate,
            dto.TripToDate,
            dto.Note));
        return Ok(result);
    }

    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("BusinessTripExpense", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteCase(Guid id)
    {
        var result = await mediator.Send(new DeleteBusinessTripCaseCommand(
            RequiredStoreId, id, CurrentUserId, IsBusinessTripPrivileged));
        return Ok(result);
    }

    [HttpPost("{id}/advance")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("BusinessTripExpense", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<BusinessTripCaseDto>>> CreateAdvance(
        Guid id, [FromBody] CreateBusinessTripAdvanceDto dto)
    {
        var result = await mediator.Send(new CreateBusinessTripAdvanceCommand(
            RequiredStoreId, id, CurrentUserId, dto.Amount, dto.Reason, dto.Note, IsBusinessTripPrivileged));
        return Ok(result);
    }

    [HttpPost("{id}/advance/approve")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("BusinessTripExpense", ModulePermissionAction.Approve)]
    public async Task<ActionResult<AppResponse<BusinessTripCaseDto>>> ApproveAdvance(
        Guid id, [FromBody] ApproveBusinessTripDto dto)
    {
        var storeId = RequiredStoreId;
        var result = await mediator.Send(new ApproveBusinessTripAdvanceCommand(
            storeId, id, CurrentUserId, dto.IsApproved, dto.RejectionReason));

        try
        {
            if (result.IsSuccess && dto.IsApproved && result.Data?.Advance?.Status == (int)AdvanceRequestStatus.Approved)
            {
                var tripCase = await context.BusinessTripCases
                    .Include(c => c.AdvanceClaim)
                    .Include(c => c.Employee)
                    .Include(c => c.EmployeeUser)
                    .FirstOrDefaultAsync(c => c.Id == id && c.StoreId == storeId);
                if (tripCase?.AdvanceClaim != null)
                {
                    await BusinessTripFinanceHelper.CreateTripAdvancePendingOnApproveAsync(
                        context, tripCase.AdvanceClaim, tripCase, storeId, CurrentUserId);
                }
            }
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "BusinessTrip advance approve: failed to create pending cash for case {CaseId}", id);
        }

        return Ok(result);
    }

    [HttpPost("{id}/advance/pay")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("BusinessTripExpense", ModulePermissionAction.Approve)]
    public async Task<ActionResult<AppResponse<BusinessTripCaseDto>>> PayAdvance(
        Guid id, [FromBody] PayBusinessTripDto? dto)
    {
        var result = await mediator.Send(new PayBusinessTripAdvanceCommand(
            RequiredStoreId, id, CurrentUserId, dto?.PaymentMethod));
        return Ok(result);
    }

    [HttpPost("{id}/advance/undo-approve")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("BusinessTripExpense", ModulePermissionAction.Approve)]
    public async Task<ActionResult<AppResponse<BusinessTripCaseDto>>> UndoApproveAdvance(Guid id)
    {
        var result = await mediator.Send(new UndoApproveBusinessTripAdvanceCommand(
            RequiredStoreId, id, CurrentUserId));
        return Ok(result);
    }

    [HttpPost("{id}/settlement")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("BusinessTripExpense", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<BusinessTripCaseDto>>> SaveSettlement(
        Guid id, [FromBody] SaveBusinessTripSettlementDto dto)
    {
        var result = await mediator.Send(new SaveBusinessTripSettlementCommand(
            RequiredStoreId, id, CurrentUserId, dto.Note, dto.Lines, IsBusinessTripPrivileged));
        return Ok(result);
    }

    [HttpPost("{id}/settlement/approve")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("BusinessTripExpense", ModulePermissionAction.Approve)]
    public async Task<ActionResult<AppResponse<BusinessTripCaseDto>>> ApproveSettlement(
        Guid id, [FromBody] ApproveBusinessTripDto dto)
    {
        var storeId = RequiredStoreId;
        var result = await mediator.Send(new ApproveBusinessTripSettlementCommand(
            storeId, id, CurrentUserId, dto.IsApproved, dto.RejectionReason));

        try
        {
            if (result.IsSuccess && dto.IsApproved && result.Data?.Settlement?.Status == (int)AdvanceRequestStatus.Approved)
            {
                var tripCase = await context.BusinessTripCases
                    .Include(c => c.SettlementClaim)
                    .Include(c => c.Employee)
                    .Include(c => c.EmployeeUser)
                    .FirstOrDefaultAsync(c => c.Id == id && c.StoreId == storeId);
                var settlement = tripCase?.SettlementClaim;
                if (tripCase != null && settlement != null)
                {
                    if (settlement.SettlementType == BusinessTripSettlementType.PayExtra)
                    {
                        await BusinessTripFinanceHelper.CreateSettlementExtraPendingAsync(
                            context, settlement, tripCase, storeId, CurrentUserId);
                    }
                    else if (settlement.BalanceAmount < 0)
                    {
                        if (dto.SurplusAsCashRefund)
                        {
                            await BusinessTripFinanceHelper.CreateSurplusRefundPendingAsync(
                                context, settlement, tripCase, storeId, CurrentUserId);
                            tripCase.Status = BusinessTripCaseStatus.Settling;
                            tripCase.UpdatedAt = DateTime.UtcNow;
                            await context.SaveChangesAsync();
                        }
                        else
                        {
                            await BusinessTripFinanceHelper.CreateSurplusAsAdvanceAsync(
                                context, settlement, tripCase, CurrentUserId);
                            tripCase.Status = BusinessTripCaseStatus.Closed;
                            tripCase.UpdatedAt = DateTime.UtcNow;
                            await context.SaveChangesAsync();
                        }
                    }
                }
            }
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "BusinessTrip settlement approve: finance voucher failed for case {CaseId}", id);
        }

        return Ok(result);
    }

    [HttpPost("{id}/settlement/confirm-surplus")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("BusinessTripExpense", ModulePermissionAction.Approve)]
    public async Task<ActionResult<AppResponse<BusinessTripCaseDto>>> ConfirmSurplus(
        Guid id, [FromBody] ConfirmSurplusDto dto)
    {
        var storeId = RequiredStoreId;
        var tripCase = await context.BusinessTripCases
            .Include(c => c.SettlementClaim)
            .Include(c => c.Employee)
            .Include(c => c.EmployeeUser)
            .FirstOrDefaultAsync(c => c.Id == id && c.StoreId == storeId);
        var settlement = tripCase?.SettlementClaim;
        if (tripCase == null || settlement == null)
            return Ok(AppResponse<BusinessTripCaseDto>.Error("Không tìm thấy hoạch toán"));
        if (settlement.Status != AdvanceRequestStatus.Approved || settlement.BalanceAmount >= 0)
            return Ok(AppResponse<BusinessTripCaseDto>.Error("Không có khoản dư ứng cần xử lý"));
        if (settlement.SurplusAdvanceRequestId.HasValue
            || (settlement.SettlementType == BusinessTripSettlementType.SurplusRefunded
                && settlement.IsExtraPaid)
            || (settlement.SettlementType == BusinessTripSettlementType.SurplusAsAdvance
                && settlement.SurplusPaymentTransactionId.HasValue
                && tripCase.Status == BusinessTripCaseStatus.Closed))
            return Ok(AppResponse<BusinessTripCaseDto>.Error("Khoản dư đã được xử lý"));

        try
        {
            if (dto.AsAdvanceDebt)
            {
                await BusinessTripFinanceHelper.CreateSurplusAsAdvanceAsync(
                    context, settlement, tripCase, CurrentUserId);
                tripCase.Status = BusinessTripCaseStatus.Closed;
            }
            else
            {
                await BusinessTripFinanceHelper.CreateSurplusRefundPendingAsync(
                    context, settlement, tripCase, storeId, CurrentUserId);
                tripCase.Status = BusinessTripCaseStatus.Settling;
            }
            tripCase.UpdatedAt = DateTime.UtcNow;
            await context.SaveChangesAsync();
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Confirm surplus failed for case {CaseId}", id);
            return Ok(AppResponse<BusinessTripCaseDto>.Error("Không tạo được chứng từ dư ứng"));
        }

        var refreshed = await mediator.Send(new GetBusinessTripCaseByIdQuery(
            storeId, id, CurrentUserId, IsBusinessTripPrivileged));
        return Ok(refreshed);
    }

    [HttpPost("{id}/settlement/pay-extra")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("BusinessTripExpense", ModulePermissionAction.Approve)]
    public async Task<ActionResult<AppResponse<BusinessTripCaseDto>>> PaySettlementExtra(
        Guid id, [FromBody] PayBusinessTripDto? dto)
    {
        var result = await mediator.Send(new PayBusinessTripSettlementExtraCommand(
            RequiredStoreId, id, CurrentUserId, dto?.PaymentMethod));
        return Ok(result);
    }

    [HttpGet("categories")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("BusinessTripExpense", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<BusinessTripExpenseCategoryDto>>>> GetCategories()
    {
        var result = await mediator.Send(new GetBusinessTripExpenseCategoriesQuery(RequiredStoreId));
        return Ok(result);
    }

    [HttpPost("categories")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("BusinessTripExpense", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<BusinessTripExpenseCategoryDto>>> UpsertCategory(
        [FromBody] UpsertBusinessTripExpenseCategoryDto dto, [FromQuery] Guid? id = null)
    {
        var result = await mediator.Send(new UpsertBusinessTripExpenseCategoryCommand(RequiredStoreId, id, dto));
        return Ok(result);
    }

    [HttpDelete("categories/{id}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("BusinessTripExpense", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteCategory(Guid id)
    {
        var result = await mediator.Send(new DeleteBusinessTripExpenseCategoryCommand(RequiredStoreId, id));
        return Ok(result);
    }

    [HttpPost("categories/seed-defaults")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("BusinessTripExpense", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<int>>> SeedCategories()
    {
        var result = await mediator.Send(new SeedBusinessTripExpenseCategoriesCommand(RequiredStoreId));
        return Ok(result);
    }
}
