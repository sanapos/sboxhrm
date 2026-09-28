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

        // Kỳ lương trừ ứng: mặc định tháng hiện tại
        var now = DateTime.Now;
        if (request.ForMonth is not (>= 1 and <= 12) || request.ForYear is null or < 2000)
        {
            request.ForMonth = now.Month;
            request.ForYear = now.Year;
        }

        var settings = await HrFinanceSettingsHelper.GetAsync(context, RequiredStoreId);
        var installments = Math.Clamp(request.InstallmentCount ?? 1, 1, Math.Max(1, settings.AdvanceMaxInstallments));
        var limitError = await CheckAdvanceLimitAsync(request, employeeUserId, installments, settings);
        if (limitError != null)
            return Ok(AppResponse<AdvanceRequestDto>.Error(limitError));

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
        if (result.IsSuccess && result.Data != null && installments > 1)
        {
            var created = await context.AdvanceRequests.AsTracking()
                .FirstOrDefaultAsync(a => a.Id == result.Data.Id);
            if (created != null)
            {
                created.InstallmentCount = installments;
                await context.SaveChangesAsync();
                result.Data.InstallmentCount = installments;
            }
        }
        return Ok(result);
    }

    /// <summary>Hạn mức ứng lương mỗi kỳ (xem trước cho form "Xin ứng").</summary>
    [HttpGet("limit")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<object>>> GetAdvanceLimit(
        [FromQuery] Guid? employeeId, [FromQuery] int? year, [FromQuery] int? month)
    {
        var now = DateTime.Now;
        var y = year ?? now.Year;
        var m = month ?? now.Month;
        var empId = employeeId ?? await context.Employees.AsNoTracking()
            .Where(e => e.ApplicationUserId == CurrentUserId)
            .Select(e => (Guid?)e.Id).FirstOrDefaultAsync();
        var settings = await HrFinanceSettingsHelper.GetAsync(context, RequiredStoreId);
        decimal? monthly = empId.HasValue
            ? await HrFinanceSettingsHelper.EstimateMonthlySalaryAsync(context, empId.Value, new DateTime(y, m, 1).AddMonths(1).AddDays(-1))
            : null;
        var limit = HrFinanceSettingsHelper.AdvanceLimit(settings, monthly);
        var used = empId.HasValue ? await UsedInPeriodAsync(empId.Value, y, m) : 0m;
        return Ok(AppResponse<object>.Success(new
        {
            year = y,
            month = m,
            monthlySalary = monthly,
            limitPercent = settings.AdvanceLimitPercent,
            limitAmount = settings.AdvanceLimitAmount,
            limit,
            used,
            remaining = limit.HasValue ? Math.Max(0, limit.Value - used) : (decimal?)null,
            maxInstallments = settings.AdvanceMaxInstallments,
        }));
    }

    private async Task<decimal> UsedInPeriodAsync(Guid employeeId, int year, int month)
    {
        var list = await context.AdvanceRequests.AsNoTracking()
            .Where(a => a.EmployeeId == employeeId
                && (a.Status == AdvanceRequestStatus.Pending || a.Status == AdvanceRequestStatus.Approved))
            .ToListAsync();
        return list.Sum(a => HrFinanceSettingsHelper.AdvanceDeductionForPeriod(a, year, month));
    }

    private async Task<string?> CheckAdvanceLimitAsync(
        CreateAdvanceRequestDto request, Guid? employeeUserId, int installments,
        Domain.Entities.HrFinanceSettings settings)
    {
        var empId = request.EmployeeId;
        if (empId == null && employeeUserId.HasValue)
        {
            var uid = employeeUserId.Value;
            empId = await context.Employees.AsNoTracking()
                .Where(e => e.ApplicationUserId == uid || e.Id == uid)
                .Select(e => (Guid?)e.Id).FirstOrDefaultAsync();
        }
        if (empId == null) return null;

        var y = request.ForYear!.Value;
        var m = request.ForMonth!.Value;
        if (settings.AdvanceMaxRequestsPerPeriod is > 0)
        {
            var count = await context.AdvanceRequests.AsNoTracking()
                .CountAsync(a => a.EmployeeId == empId && a.ForYear == y && a.ForMonth == m
                    && (a.Status == AdvanceRequestStatus.Pending || a.Status == AdvanceRequestStatus.Approved));
            if (count >= settings.AdvanceMaxRequestsPerPeriod)
                return $"Đã đạt số lần ứng tối đa trong kỳ {m:D2}/{y} ({settings.AdvanceMaxRequestsPerPeriod} lần).";
        }

        var monthly = await HrFinanceSettingsHelper.EstimateMonthlySalaryAsync(
            context, empId.Value, new DateTime(y, m, 1).AddMonths(1).AddDays(-1));
        var limit = HrFinanceSettingsHelper.AdvanceLimit(settings, monthly);
        if (limit == null) return null;

        var probe = new Domain.Entities.AdvanceRequest
        {
            Amount = request.Amount, ForYear = y, ForMonth = m, InstallmentCount = installments,
        };
        var need = HrFinanceSettingsHelper.AdvanceDeductionForPeriod(probe, y, m);
        var used = await UsedInPeriodAsync(empId.Value, y, m);
        if (used + need > limit.Value)
        {
            var remaining = Math.Max(0, limit.Value - used);
            return $"Vượt hạn mức ứng kỳ {m:D2}/{y}: hạn mức {limit.Value:N0}đ, đã ứng {used:N0}đ, còn được ứng {remaining:N0}đ"
                + (installments > 1 ? $" (mỗi kỳ trả góp {need:N0}đ)." : ".");
        }
        return null;
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
