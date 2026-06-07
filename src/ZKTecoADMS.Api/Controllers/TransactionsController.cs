using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Commands.Transactions;
using ZKTecoADMS.Application.Queries.Transactions;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Transactions;
using ZKTecoADMS.Application.DTOs.Commons;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class TransactionsController(
    IMediator mediator,
    ZKTecoDbContext context,
    IModulePermissionService modulePermissionService,
    ISystemNotificationService notificationService) : AuthenticatedControllerBase
{
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireAnyModulePermission(ModulePermissionAction.View, "Transaction", "CashTransaction", "BonusPenalty", "Benefit")]
    public async Task<ActionResult<AppResponse<PagedResult<PaymentTransactionDto>>>> GetTransactions(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 10,
        [FromQuery] Guid? employeeUserId = null,
        [FromQuery] string? type = null,
        [FromQuery] string? status = null,
        [FromQuery] int? forMonth = null,
        [FromQuery] int? forYear = null,
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null)
    {
        if (IsEmployee && !IsManager)
            employeeUserId = CurrentUserId;

        var query = new GetTransactionsQuery(page, pageSize, employeeUserId, type, status, forMonth, forYear, fromDate, toDate, RequiredStoreId);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpGet("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireAnyModulePermission(ModulePermissionAction.View, "Transaction", "CashTransaction", "BonusPenalty", "Benefit")]
    public async Task<ActionResult<AppResponse<PaymentTransactionDto>>> GetTransactionById(Guid id)
    {
        var query = new GetTransactionByIdQuery(id);
        var result = await mediator.Send(query);
        if (!result.IsSuccess || result.Data == null)
            return Ok(result);

        if (IsEmployee && !IsManager && result.Data.EmployeeUserId != CurrentUserId)
            return Forbid();

        return Ok(result);
    }

    [HttpGet("summary")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.View, "Transaction", "CashTransaction", "BonusPenalty")]
    public async Task<ActionResult<AppResponse<TransactionSummaryDto>>> GetTransactionSummary(
        [FromQuery] Guid? employeeUserId = null,
        [FromQuery] int? forMonth = null,
        [FromQuery] int? forYear = null)
    {
        var query = new GetTransactionSummaryQuery(employeeUserId, forMonth, forYear);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.Create, "Transaction", "CashTransaction", "BonusPenalty")]
    public async Task<ActionResult<AppResponse<PaymentTransactionDto>>> CreateTransaction([FromBody] CreatePaymentTransactionDto request)
    {
        var command = new CreatePaymentTransactionCommand(
            request.EmployeeUserId,
            request.EmployeeId,
            request.Type,
            request.ForMonth,
            request.ForYear,
            request.TransactionDate,
            request.Amount,
            request.Description,
            request.PaymentMethod,
            request.Note,
            request.AdvanceRequestId,
            request.PayslipId,
            CurrentUserId);

        var result = await mediator.Send(command);

        try
        {
            if (result.IsSuccess && result.Data != null)
            {
                var tx = await context.PaymentTransactions.AsNoTracking()
                    .FirstOrDefaultAsync(t => t.Id == result.Data.Id);
                if (tx != null)
                {
                    await PaymentTransactionNotificationHelper.NotifyCreatedAsync(
                        context, modulePermissionService, notificationService,
                        tx, CurrentUserId, RequiredStoreId);
                }
            }
        }
        catch { /* notification is best-effort */ }

        return Ok(result);
    }

    [HttpPut("{id}/status")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.Edit, "Transaction", "CashTransaction", "BonusPenalty")]
    public async Task<ActionResult<AppResponse<PaymentTransactionDto>>> UpdateTransactionStatus(
        Guid id,
        [FromBody] UpdateTransactionStatusDto request)
    {
        var storeId = RequiredStoreId;
        var command = new UpdateTransactionStatusCommand(id, request.Status, CurrentUserId);
        var result = await mediator.Send(command);

        try
        {
            if (result.IsSuccess)
            {
                var tx = await context.PaymentTransactions
                    .Include(t => t.Employee)
                    .FirstOrDefaultAsync(t => t.Id == id);
                if (tx != null)
                {
                    if (request.Status == "Completed")
                    {
                        var cashTx = await PaymentFinanceHelper.ApplyBonusPenaltyDisbursementOnApproveAsync(
                            context, tx, storeId, CurrentUserId, request.DisbursementMode);
                        if (cashTx != null)
                        {
                            await CashTransactionNotificationHelper.NotifyOnCreatedAsync(
                                context, modulePermissionService, notificationService,
                                cashTx, CurrentUserId, storeId);
                        }
                    }
                    else if (request.Status is "Pending" or "Cancelled")
                    {
                        PaymentFinanceHelper.ClearSalaryDisbursementOnUnapprove(tx);
                        var linked = await PaymentFinanceHelper.ResolveLinkedAsync(
                            context, storeId, PaymentFinanceHelper.BonusPenaltyNote(id));
                        if (linked != null && !linked.IsPaid)
                        {
                            PaymentFinanceHelper.CancelLinkedCashTransaction(
                                linked, request.Status == "Cancelled" ? "Hủy theo phiếu thưởng/phạt" : "Hoàn duyệt phiếu thưởng/phạt");
                        }
                        await context.SaveChangesAsync();
                    }

                    await PaymentTransactionNotificationHelper.NotifyStatusChangedAsync(
                        notificationService, tx, request.Status, CurrentUserId, storeId);
                }
            }
        }
        catch { /* notification is best-effort */ }

        return Ok(result);
    }

    [HttpPut("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.Edit, "Transaction", "CashTransaction", "BonusPenalty")]
    public async Task<ActionResult<AppResponse<PaymentTransactionDto>>> UpdateTransaction(
        Guid id,
        [FromBody] UpdatePaymentTransactionDto request)
    {
        var command = new UpdatePaymentTransactionCommand(
            id,
            request.Type,
            request.Amount,
            request.Description,
            request.Note,
            request.TransactionDate,
            request.ForMonth,
            request.ForYear);
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.Delete, "Transaction", "CashTransaction", "BonusPenalty")]
    public async Task<ActionResult<AppResponse<bool>>> DeleteTransaction(Guid id)
    {
        var storeId = RequiredStoreId;
        var txInfo = await context.PaymentTransactions.AsNoTracking()
            .Where(t => t.Id == id)
            .Select(t => new { t.EmployeeUserId, t.Type, t.Amount })
            .FirstOrDefaultAsync();

        var linked = await PaymentFinanceHelper.ResolveLinkedAsync(
            context, storeId, PaymentFinanceHelper.BonusPenaltyNote(id));
        if (linked != null)
        {
            PaymentFinanceHelper.SoftDeleteLinkedCashTransaction(linked, "Xóa theo phiếu thưởng/phạt");
            await context.SaveChangesAsync();
        }

        var command = new DeletePaymentTransactionCommand(id);
        var result = await mediator.Send(command);

        try
        {
            if (result.IsSuccess && txInfo != null)
            {
                await PaymentTransactionNotificationHelper.NotifyDeletedAsync(
                    notificationService,
                    txInfo.EmployeeUserId,
                    txInfo.Type,
                    txInfo.Amount,
                    CurrentUserId,
                    storeId);
            }
        }
        catch { /* notification is best-effort */ }

        return Ok(result);
    }

    [HttpPost("bulk-approve")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.Approve, "Transaction", "CashTransaction", "BonusPenalty")]
    public async Task<ActionResult<AppResponse<BulkTransactionResultDto>>> BulkApprove([FromBody] BulkTransactionApproveDto request)
    {
        var storeId = RequiredStoreId;
        int success = 0, failed = 0;
        var approvedIds = new List<Guid>();

        foreach (var id in request.Ids)
        {
            try
            {
                var command = new UpdateTransactionStatusCommand(id, "Completed", CurrentUserId);
                var result = await mediator.Send(command);
                if (result.IsSuccess) { success++; approvedIds.Add(id); } else failed++;
            }
            catch { failed++; }
        }

        try
        {
            if (approvedIds.Count > 0)
            {
                var txs = await context.PaymentTransactions
                    .Include(t => t.Employee)
                    .Where(t => approvedIds.Contains(t.Id))
                    .ToListAsync();

                foreach (var tx in txs)
                {
                    var cashTx = await PaymentFinanceHelper.ApplyBonusPenaltyDisbursementOnApproveAsync(
                        context, tx, storeId, CurrentUserId, request.DisbursementMode);
                    if (cashTx != null)
                    {
                        await CashTransactionNotificationHelper.NotifyOnCreatedAsync(
                            context, modulePermissionService, notificationService,
                            cashTx, CurrentUserId, storeId);
                    }

                    await PaymentTransactionNotificationHelper.NotifyStatusChangedAsync(
                        notificationService, tx, "Completed", CurrentUserId, storeId);
                }
            }
        }
        catch { /* notification is best-effort */ }

        return Ok(AppResponse<BulkTransactionResultDto>.Success(new BulkTransactionResultDto(success, failed)));
    }

    [HttpPost("bulk-pay")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.Create, "Transaction", "CashTransaction", "BonusPenalty")]
    public async Task<ActionResult<AppResponse<BulkTransactionResultDto>>> BulkPay([FromBody] BulkTransactionPayDto request)
    {
        var storeId = RequiredStoreId;
        int success = 0, failed = 0;
        var paidTransactions = new List<PaymentTransaction>();

        var paymentMethod = PaymentMethodType.Cash;
        if (!string.IsNullOrEmpty(request.PaymentMethod))
        {
            if (Enum.TryParse<PaymentMethodType>(request.PaymentMethod, true, out var parsed))
                paymentMethod = parsed;
        }

        var transactions = await context.PaymentTransactions
            .AsTracking()
            .Include(t => t.Employee)
            .Where(t => request.Ids.Contains(t.Id) && t.Status == "Completed")
            .ToDictionaryAsync(t => t.Id);

        foreach (var id in request.Ids)
        {
            try
            {
                if (!transactions.TryGetValue(id, out var transaction))
                { failed++; continue; }

                transaction.PaymentMethod = request.PaymentMethod ?? "Cash";

                var marker = PaymentFinanceHelper.BonusPenaltyNote(transaction.Id);
                var linked = await PaymentFinanceHelper.ResolveLinkedAsync(context, storeId, marker);

                if (linked != null && !linked.IsPaid)
                {
                    PaymentFinanceHelper.CompleteCashTransaction(linked, paymentMethod, CurrentUserId);
                }
                else if (linked == null)
                {
                    // Legacy: chưa có phiếu chờ → tạo bù đã thanh toán
                    var isPenalty = transaction.Type == "Penalty";
                    var cashType = isPenalty ? CashTransactionType.Income : CashTransactionType.Expense;
                    var categoryName = isPenalty ? "Phạt nhân viên" : "Thưởng nhân viên";
                    var categories = await context.TransactionCategories
                        .Where(c => c.IsActive && c.StoreId == storeId && c.Type == cashType)
                        .ToListAsync();
                    var category = categories.FirstOrDefault(c => c.Name == categoryName)
                        ?? categories.FirstOrDefault();
                    if (category == null) { failed++; continue; }

                    var empName = transaction.Employee != null
                        ? $"{transaction.Employee.LastName} {transaction.Employee.FirstName}".Trim()
                        : "N/A";
                    var today = DateTime.UtcNow;
                    var prefix = isPenalty ? "TH" : "CH";
                    var dateStr = today.ToString("yyyyMMdd");
                    var count = await context.CashTransactions
                        .CountAsync(x => x.StoreId == storeId && x.TransactionCode.StartsWith($"{prefix}-{dateStr}")) + success + 1;

                    var cashTx = new CashTransaction
                    {
                        Id = Guid.NewGuid(),
                        TransactionCode = $"{prefix}-{dateStr}-{count:D4}",
                        Type = cashType,
                        CategoryId = category.Id,
                        Amount = Math.Abs(transaction.Amount),
                        TransactionDate = today,
                        Description = $"{(isPenalty ? "Thu tiền phạt" : "Thưởng")} - {empName} - {transaction.Description}",
                        PaymentMethod = paymentMethod,
                        Status = CashTransactionStatus.Completed,
                        IsPaid = true,
                        PaidDate = today,
                        CreatedByUserId = CurrentUserId,
                        StoreId = storeId,
                        InternalNote = !string.IsNullOrEmpty(transaction.Note)
                            ? $"{transaction.Note} | {marker}"
                            : marker,
                        IsActive = true
                    };
                    context.CashTransactions.Add(cashTx);
                }

                paidTransactions.Add(transaction);
                success++;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[BulkPay ERROR] Id={id}, Exception={ex.Message}, Inner={ex.InnerException?.Message}");
                failed++;
            }
        }

        if (success > 0)
            await context.SaveChangesAsync();

        try
        {
            foreach (var tx in paidTransactions)
            {
                await PaymentTransactionNotificationHelper.NotifyPaidAsync(
                    notificationService, tx, CurrentUserId, storeId);
            }
        }
        catch { /* notification is best-effort */ }

        return Ok(AppResponse<BulkTransactionResultDto>.Success(new BulkTransactionResultDto(success, failed)));
    }
}
