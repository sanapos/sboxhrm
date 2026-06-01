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

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class TransactionsController(IMediator mediator, ZKTecoDbContext context, ISystemNotificationService notificationService) : AuthenticatedControllerBase
{
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.View, "Transaction", "CashTransaction", "BonusPenalty")]
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
        var query = new GetTransactionsQuery(page, pageSize, employeeUserId, type, status, forMonth, forYear, fromDate, toDate);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpGet("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.View, "Transaction", "CashTransaction", "BonusPenalty")]
    public async Task<ActionResult<AppResponse<PaymentTransactionDto>>> GetTransactionById(Guid id)
    {
        var query = new GetTransactionByIdQuery(id);
        var result = await mediator.Send(query);
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

        // Notify the target employee about the new bonus/penalty
        try
        {
            var empUserId = request.EmployeeUserId;
            if (empUserId != Guid.Empty && empUserId != CurrentUserId)
            {
                var typeLabel = request.Type == "Bonus" ? "thÆ°á»Ÿng" : request.Type == "Penalty" ? "pháº¡t" : request.Type;
                await notificationService.CreateAndSendAsync(
                    empUserId, NotificationType.Info,
                    $"Phiáº¿u {typeLabel} má»›i",
                    $"Báº¡n cÃ³ phiáº¿u {typeLabel}: {request.Amount:N0}Ä‘ - {request.Description}",
                    relatedEntityType: "PaymentTransaction",
                    fromUserId: CurrentUserId, categoryCode: "transaction", storeId: RequiredStoreId);
            }
        }
        catch { /* Notification failure should not affect main operation */ }

        return Ok(result);
    }

    [HttpPut("{id}/status")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.Edit, "Transaction", "CashTransaction", "BonusPenalty")]
    public async Task<ActionResult<AppResponse<PaymentTransactionDto>>> UpdateTransactionStatus(
        Guid id, 
        [FromBody] UpdateTransactionStatusDto request)
    {
        var command = new UpdateTransactionStatusCommand(id, request.Status, CurrentUserId);
        var result = await mediator.Send(command);

        // Notify the target employee about status change
        try
        {
            var tx = await context.PaymentTransactions.AsNoTracking().FirstOrDefaultAsync(t => t.Id == id);
            if (tx != null && tx.EmployeeUserId != Guid.Empty && tx.EmployeeUserId != CurrentUserId)
            {
                var statusLabel = request.Status switch
                {
                    "Completed" => "Ä‘Ã£ duyá»‡t",
                    "Cancelled" => "Ä‘Ã£ há»§y",
                    _ => $"cáº­p nháº­t: {request.Status}"
                };
                await notificationService.CreateAndSendAsync(
                    tx.EmployeeUserId, NotificationType.Info,
                    "Phiáº¿u thÆ°á»Ÿng/pháº¡t cáº­p nháº­t",
                    $"Phiáº¿u {tx.Type} {statusLabel}",
                    relatedEntityType: "PaymentTransaction", relatedEntityId: id,
                    fromUserId: CurrentUserId, categoryCode: "transaction", storeId: RequiredStoreId);
            }
        }
        catch { /* Notification failure should not affect main operation */ }

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
        // Load transaction info before deletion for notification
        var txInfo = await context.PaymentTransactions.AsNoTracking()
            .Where(t => t.Id == id)
            .Select(t => new { t.EmployeeUserId, t.Type, t.Amount })
            .FirstOrDefaultAsync();

        // If the transaction was paid, also delete the corresponding CashTransaction
        var tx = await context.PaymentTransactions.FirstOrDefaultAsync(t => t.Id == id);
        if (tx != null && !string.IsNullOrEmpty(tx.PaymentMethod))
        {
            var searchNote = $"#{id}";
            var cashTx = await context.CashTransactions
                .Where(c => c.InternalNote != null && c.InternalNote.Contains(searchNote))
                .FirstOrDefaultAsync();
            if (cashTx != null)
            {
                context.CashTransactions.Remove(cashTx);
                await context.SaveChangesAsync();
            }
        }

        var command = new DeletePaymentTransactionCommand(id);
        var result = await mediator.Send(command);

        // Notify the target employee about deletion
        try
        {
            if (txInfo != null && txInfo.EmployeeUserId != Guid.Empty && txInfo.EmployeeUserId != CurrentUserId)
            {
                var typeLabel = txInfo.Type == "Bonus" ? "thÆ°á»Ÿng" : txInfo.Type == "Penalty" ? "pháº¡t" : txInfo.Type;
                await notificationService.CreateAndSendAsync(
                    txInfo.EmployeeUserId, NotificationType.Warning,
                    $"Phiáº¿u {typeLabel} Ä‘Ã£ xÃ³a",
                    $"Phiáº¿u {typeLabel} {txInfo.Amount:N0}Ä‘ Ä‘Ã£ bá»‹ xÃ³a",
                    relatedEntityType: "PaymentTransaction",
                    fromUserId: CurrentUserId, categoryCode: "transaction", storeId: RequiredStoreId);
            }
        }
        catch { /* Notification failure should not affect main operation */ }

        return Ok(result);
    }

    [HttpPost("bulk-approve")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.Approve, "Transaction", "CashTransaction", "BonusPenalty")]
    public async Task<ActionResult<AppResponse<BulkTransactionResultDto>>> BulkApprove([FromBody] BulkTransactionApproveDto request)
    {
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

        // Notify all affected employees about bulk approval
        try
        {
            if (approvedIds.Count > 0)
            {
                var txInfos = await context.PaymentTransactions.AsNoTracking()
                    .Where(t => approvedIds.Contains(t.Id))
                    .Select(t => new { t.Id, t.EmployeeUserId, t.Type, t.Amount })
                    .ToListAsync();
                foreach (var t in txInfos)
                {
                    if (t.EmployeeUserId != Guid.Empty && t.EmployeeUserId != CurrentUserId)
                    {
                        var typeLabel = t.Type == "Bonus" ? "thÆ°á»Ÿng" : t.Type == "Penalty" ? "pháº¡t" : t.Type;
                        await notificationService.CreateAndSendAsync(
                            t.EmployeeUserId, NotificationType.Success,
                            $"Phiáº¿u {typeLabel} Ä‘Ã£ duyá»‡t",
                            $"Phiáº¿u {typeLabel} {Math.Abs(t.Amount):N0}Ä‘ Ä‘Ã£ Ä‘Æ°á»£c duyá»‡t",
                            relatedEntityType: "PaymentTransaction", relatedEntityId: t.Id,
                            fromUserId: CurrentUserId, categoryCode: "transaction", storeId: RequiredStoreId);
                    }
                }
            }
        }
        catch { /* Notification failure should not affect main operation */ }

        return Ok(AppResponse<BulkTransactionResultDto>.Success(new BulkTransactionResultDto(success, failed)));
    }

    [HttpPost("bulk-pay")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.Create, "Transaction", "CashTransaction", "BonusPenalty")]
    public async Task<ActionResult<AppResponse<BulkTransactionResultDto>>> BulkPay([FromBody] BulkTransactionPayDto request)
    {
        var storeId = RequiredStoreId;
        int success = 0, failed = 0;

        // Parse payment method
        var paymentMethod = PaymentMethodType.Cash;
        if (!string.IsNullOrEmpty(request.PaymentMethod))
        {
            if (Enum.TryParse<PaymentMethodType>(request.PaymentMethod, true, out var parsed))
                paymentMethod = parsed;
        }

        // Pre-load all transactions and categories to avoid N+1
        var transactions = await context.PaymentTransactions
            .AsTracking()
            .Include(t => t.Employee)
            .Where(t => request.Ids.Contains(t.Id) && t.Status == "Completed")
            .ToDictionaryAsync(t => t.Id);

        var categories = await context.TransactionCategories
            .Where(c => c.IsActive)
            .ToListAsync();

        // Get current max count for transaction codes
        var today = DateTime.UtcNow;
        var dateStr = today.ToString("yyyyMMdd");
        var thCount = await context.CashTransactions
            .CountAsync(x => x.TransactionCode.StartsWith($"TH-{dateStr}"));
        var chCount = await context.CashTransactions
            .CountAsync(x => x.TransactionCode.StartsWith($"CH-{dateStr}"));

        foreach (var id in request.Ids)
        {
            try
            {
                if (!transactions.TryGetValue(id, out var transaction))
                { failed++; continue; }

                // Penalty => Income (Thu), Bonus => Expense (Chi)
                var isPenalty = transaction.Type == "Penalty";
                var cashType = isPenalty ? CashTransactionType.Income : CashTransactionType.Expense;
                var codePrefix = isPenalty ? "TH" : "CH";
                var categoryName = isPenalty ? "Pháº¡t nhÃ¢n viÃªn" : "ThÆ°á»Ÿng nhÃ¢n viÃªn";

                var category = categories.FirstOrDefault(c => c.Name == categoryName && c.Type == cashType);
                if (category == null)
                    category = categories.FirstOrDefault(c => c.Type == cashType);
                if (category == null) { failed++; continue; }

                // Update payment method on the transaction
                transaction.PaymentMethod = request.PaymentMethod ?? "Cash";

                // Create CashTransaction
                var count = (isPenalty ? ++thCount : ++chCount) + success;
                var transactionCode = $"{codePrefix}-{dateStr}-{count:D4}";

                var empName = transaction.Employee != null
                    ? $"{transaction.Employee.LastName} {transaction.Employee.FirstName}".Trim()
                    : "N/A";

                var cashTx = new CashTransaction
                {
                    Id = Guid.NewGuid(),
                    TransactionCode = transactionCode,
                    Type = cashType,
                    CategoryId = category.Id,
                    Amount = Math.Abs(transaction.Amount),
                    TransactionDate = today,
                    Description = $"{(isPenalty ? "Thu tiá»n pháº¡t" : "ThÆ°á»Ÿng")} - {empName} - {transaction.Description}",
                    PaymentMethod = paymentMethod,
                    Status = CashTransactionStatus.Completed,
                    IsPaid = true,
                    PaidDate = today,
                    CreatedByUserId = CurrentUserId,
                    StoreId = storeId,
                    InternalNote = !string.IsNullOrEmpty(transaction.Note)
                        ? $"{transaction.Note} | Tá»± Ä‘á»™ng táº¡o tá»« phiáº¿u thÆ°á»Ÿng/pháº¡t #{transaction.Id}"
                        : $"Tá»± Ä‘á»™ng táº¡o tá»« phiáº¿u thÆ°á»Ÿng/pháº¡t #{transaction.Id}",
                    IsActive = true
                };

                context.CashTransactions.Add(cashTx);
                success++;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[BulkPay ERROR] Id={id}, Exception={ex.Message}, Inner={ex.InnerException?.Message}");
                failed++;
            }
        }

        // Batch save all changes once instead of per-iteration
        if (success > 0)
            await context.SaveChangesAsync();

        // Notify all affected employees about bulk payment
        try
        {
            foreach (var kvp in transactions)
            {
                var t = kvp.Value;
                if (t.EmployeeUserId != Guid.Empty && t.EmployeeUserId != CurrentUserId)
                {
                    var typeLabel = t.Type == "Bonus" ? "thÆ°á»Ÿng" : t.Type == "Penalty" ? "pháº¡t" : t.Type;
                    await notificationService.CreateAndSendAsync(
                        t.EmployeeUserId, NotificationType.Success,
                        $"Phiáº¿u {typeLabel} Ä‘Ã£ thanh toÃ¡n",
                        $"Phiáº¿u {typeLabel} {Math.Abs(t.Amount):N0}Ä‘ Ä‘Ã£ Ä‘Æ°á»£c thanh toÃ¡n",
                        relatedEntityType: "PaymentTransaction", relatedEntityId: t.Id,
                        fromUserId: CurrentUserId, categoryCode: "transaction", storeId: storeId);
                }
            }
        }
        catch { /* Notification failure should not affect main operation */ }

        return Ok(AppResponse<BulkTransactionResultDto>.Success(new BulkTransactionResultDto(success, failed)));
    }
}

