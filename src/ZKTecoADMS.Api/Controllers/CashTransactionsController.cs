using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.DTOs.Commons;
using ZKTecoADMS.Application.DTOs.Transactions;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class CashTransactionsController(
    ZKTecoDbContext context,
    ISystemNotificationService notificationService,
    IModulePermissionService modulePermissionService) : AuthenticatedControllerBase
{
    // ═══════════════════════════════════════════════════════════════════════════
    // GIAO DỊCH THU CHI - CASH TRANSACTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// <summary>
    /// Lấy danh sách giao dịch thu chi
    /// </summary>
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("CashTransaction", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<PagedResult<CashTransactionDto>>>> GetTransactions(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] CashTransactionType? type = null,
        [FromQuery] Guid? categoryId = null,
        [FromQuery] CashTransactionStatus? status = null,
        [FromQuery] PaymentMethodType? paymentMethod = null,
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null,
        [FromQuery] string? search = null,
        [FromQuery] bool? isPaid = null)
    {
        var storeId = RequiredStoreId;

        // Sửa bản ghi đã thanh toán nhưng status còn Pending/WaitingPayment
        await context.CashTransactions
            .Where(x => x.StoreId == storeId && x.IsActive && x.IsPaid
                && x.Status != CashTransactionStatus.Completed)
            .ExecuteUpdateAsync(s => s
                .SetProperty(x => x.Status, CashTransactionStatus.Completed)
                .SetProperty(x => x.LastModified, DateTime.UtcNow));

        var query = context.CashTransactions
            .Include(x => x.Category)
            .Include(x => x.BankAccount)
            .Include(x => x.CreatedByUser)
            .Where(x => x.StoreId == storeId && x.IsActive)
            .AsQueryable();

        if (type.HasValue)
            query = query.Where(x => x.Type == type.Value);
        
        if (categoryId.HasValue)
            query = query.Where(x => x.CategoryId == categoryId.Value);
        
        if (status.HasValue)
            query = query.Where(x => x.Status == status.Value);
        
        if (paymentMethod.HasValue)
            query = query.Where(x => x.PaymentMethod == paymentMethod.Value);
        
        if (fromDate.HasValue)
            query = query.Where(x => x.TransactionDate >= fromDate.Value);
        
        if (toDate.HasValue)
            query = query.Where(x => x.TransactionDate <= toDate.Value);
        
        if (isPaid.HasValue)
            query = query.Where(x => x.IsPaid == isPaid.Value);
        
        if (!string.IsNullOrEmpty(search))
        {
            var searchPattern = $"%{search}%";
            query = query.Where(x =>
                EF.Functions.ILike(x.TransactionCode, searchPattern) ||
                EF.Functions.ILike(x.Description, searchPattern) ||
                (x.ContactName != null && EF.Functions.ILike(x.ContactName, searchPattern)));
        }

        var totalItems = await query.CountAsync();
        
        var items = await query
            .OrderByDescending(x => x.TransactionDate)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(x => new CashTransactionDto
            {
                Id = x.Id,
                TransactionCode = x.TransactionCode,
                Type = x.Type,
                CategoryId = x.CategoryId,
                CategoryName = x.Category.Name,
                CategoryIcon = x.Category.Icon,
                CategoryColor = x.Category.Color,
                Amount = x.Amount,
                TransactionDate = x.TransactionDate,
                Description = x.Description,
                PaymentMethod = x.PaymentMethod,
                BankAccountId = x.BankAccountId,
                BankAccountName = x.BankAccount != null ? x.BankAccount.AccountName : null,
                Status = x.IsPaid ? CashTransactionStatus.Completed : x.Status,
                ContactName = x.ContactName,
                ContactPhone = x.ContactPhone,
                PaymentReference = x.PaymentReference,
                ReceiptImageUrl = x.ReceiptImageUrl,
                VietQRUrl = x.VietQRUrl,
                IsPaid = x.IsPaid,
                PaidDate = x.PaidDate,
                CreatedByUserId = x.CreatedByUserId,
                CreatedByUserName = x.CreatedByUser.UserName ?? "",
                InternalNote = x.InternalNote,
                Tags = x.Tags,
                LastModified = x.LastModified
            })
            .ToListAsync();

        for (var i = 0; i < items.Count; i++)
            items[i] = FixTransactionDtoEncoding(items[i]);

        var result = new PagedResult<CashTransactionDto>
        {
            Items = items,
            TotalCount = totalItems,
            PageNumber = page,
            PageSize = pageSize
        };

        return Ok(AppResponse<PagedResult<CashTransactionDto>>.Success(result));
    }

    /// <summary>
    /// Lấy chi tiết giao dịch
    /// </summary>
    [HttpGet("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("CashTransaction", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<CashTransactionDto>>> GetTransaction(Guid id)
    {
        var storeId = RequiredStoreId;
        
        var transaction = await context.CashTransactions
            .Include(x => x.Category)
            .Include(x => x.BankAccount)
            .Include(x => x.CreatedByUser)
            .Where(x => x.Id == id && x.StoreId == storeId)
            .Select(x => new CashTransactionDto
            {
                Id = x.Id,
                TransactionCode = x.TransactionCode,
                Type = x.Type,
                CategoryId = x.CategoryId,
                CategoryName = x.Category.Name,
                CategoryIcon = x.Category.Icon,
                CategoryColor = x.Category.Color,
                Amount = x.Amount,
                TransactionDate = x.TransactionDate,
                Description = x.Description,
                PaymentMethod = x.PaymentMethod,
                BankAccountId = x.BankAccountId,
                BankAccountName = x.BankAccount != null ? x.BankAccount.AccountName : null,
                Status = x.IsPaid ? CashTransactionStatus.Completed : x.Status,
                ContactName = x.ContactName,
                ContactPhone = x.ContactPhone,
                PaymentReference = x.PaymentReference,
                ReceiptImageUrl = x.ReceiptImageUrl,
                VietQRUrl = x.VietQRUrl,
                IsPaid = x.IsPaid,
                PaidDate = x.PaidDate,
                CreatedByUserId = x.CreatedByUserId,
                CreatedByUserName = x.CreatedByUser.UserName ?? "",
                InternalNote = x.InternalNote,
                Tags = x.Tags,
                LastModified = x.LastModified
            })
            .FirstOrDefaultAsync();

        if (transaction == null)
            return NotFound(AppResponse<CashTransactionDto>.Error("Không tìm thấy giao dịch"));

        FixTransactionDtoEncoding(transaction);
        return Ok(AppResponse<CashTransactionDto>.Success(transaction));
    }

    /// <summary>
    /// Tạo giao dịch mới
    /// </summary>
    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("CashTransaction", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<CashTransactionDto>>> CreateTransaction([FromBody] CreateCashTransactionDto request)
    {
        var storeId = RequiredStoreId;
        
        // Validate category
        var category = await context.TransactionCategories
            .FirstOrDefaultAsync(x => x.Id == request.CategoryId && x.IsActive && x.StoreId == storeId);
        
        if (category == null)
            return BadRequest(AppResponse<CashTransactionDto>.Error("Danh mục không hợp lệ"));

        if (category.Type != request.Type)
            return BadRequest(AppResponse<CashTransactionDto>.Error("Danh mục không khớp với loại giao dịch"));

        // Generate transaction code
        var today = DateTime.UtcNow;
        var prefix = request.Type == CashTransactionType.Income ? "TH" : "CH";
        var dateStr = today.ToString("yyyyMMdd");
        var count = await context.CashTransactions
            .CountAsync(x => x.StoreId == storeId && x.TransactionCode.StartsWith($"{prefix}-{dateStr}")) + 1;
        var transactionCode = $"{prefix}-{dateStr}-{count:D4}";

        // Generate VietQR URL if using VietQR payment
        string? vietQrUrl = null;
        if (request.PaymentMethod == PaymentMethodType.VietQR && request.BankAccountId.HasValue)
        {
            var bankAccount = await context.BankAccounts.FindAsync(request.BankAccountId.Value);
            if (bankAccount != null)
            {
                vietQrUrl = VietQRBanks.GenerateVietQRUrl(
                    bankAccount.BankCode,
                    bankAccount.AccountNumber,
                    request.Amount,
                    $"{transactionCode} - {request.Description}",
                    bankAccount.VietQRTemplate);
            }
        }

        var transaction = new CashTransaction
        {
            Id = Guid.NewGuid(),
            TransactionCode = transactionCode,
            Type = request.Type,
            CategoryId = request.CategoryId,
            Amount = request.Amount,
            TransactionDate = request.TransactionDate,
            Description = request.Description,
            PaymentMethod = request.PaymentMethod,
            BankAccountId = request.BankAccountId,
            Status = request.IsPaid ? CashTransactionStatus.Completed : CashTransactionStatus.Pending,
            ContactName = request.ContactName,
            ContactPhone = request.ContactPhone,
            PaymentReference = request.PaymentReference,
            ReceiptImageUrl = request.ReceiptImageUrl,
            VietQRUrl = vietQrUrl,
            IsPaid = request.IsPaid,
            PaidDate = request.IsPaid ? DateTime.UtcNow : null,
            CreatedByUserId = CurrentUserId,
            InternalNote = request.InternalNote,
            Tags = request.Tags,
            IsActive = true,
            StoreId = storeId
        };

        context.CashTransactions.Add(transaction);
        await context.SaveChangesAsync();

        try
        {
            await CashTransactionNotificationHelper.NotifyOnCreatedAsync(
                context,
                modulePermissionService,
                notificationService,
                transaction,
                CurrentUserId,
                storeId);
        }
        catch { /* notification is best-effort */ }

        // Return with full info
        return await GetTransaction(transaction.Id);
    }

    /// <summary>
    /// Cập nhật giao dịch
    /// </summary>
    [HttpPut("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("CashTransaction", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<CashTransactionDto>>> UpdateTransaction(Guid id, [FromBody] UpdateCashTransactionDto request)
    {
        var storeId = RequiredStoreId;
        
        var transaction = await context.CashTransactions
            .AsTracking()
            .Include(x => x.CreatedByUser)
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId);

        if (transaction == null)
            return NotFound(AppResponse<CashTransactionDto>.Error("Không tìm thấy giao dịch"));

        // Validate category
        var category = await context.TransactionCategories
            .FirstOrDefaultAsync(x => x.Id == request.CategoryId && x.IsActive && x.StoreId == storeId);
        
        if (category == null)
            return BadRequest(AppResponse<CashTransactionDto>.Error("Danh mục không hợp lệ"));

        if (category.Type != request.Type)
            return BadRequest(AppResponse<CashTransactionDto>.Error("Danh mục không khớp với loại giao dịch"));

        // Generate VietQR URL if using VietQR payment
        string? vietQrUrl = transaction.VietQRUrl;
        if (request.PaymentMethod == PaymentMethodType.VietQR && request.BankAccountId.HasValue)
        {
            var bankAccount = await context.BankAccounts.FindAsync(request.BankAccountId.Value);
            if (bankAccount != null)
            {
                vietQrUrl = VietQRBanks.GenerateVietQRUrl(
                    bankAccount.BankCode,
                    bankAccount.AccountNumber,
                    request.Amount,
                    $"{transaction.TransactionCode} - {request.Description}",
                    bankAccount.VietQRTemplate);
            }
        }

        transaction.Type = request.Type;
        transaction.CategoryId = request.CategoryId;
        transaction.Amount = request.Amount;
        transaction.TransactionDate = request.TransactionDate;
        transaction.Description = request.Description;
        transaction.PaymentMethod = request.PaymentMethod;
        transaction.BankAccountId = request.BankAccountId;
        transaction.ContactName = request.ContactName;
        transaction.ContactPhone = request.ContactPhone;
        transaction.PaymentReference = request.PaymentReference;
        transaction.ReceiptImageUrl = request.ReceiptImageUrl;
        transaction.VietQRUrl = vietQrUrl;
        transaction.InternalNote = request.InternalNote;
        transaction.Tags = request.Tags;
        transaction.LastModified = DateTime.UtcNow;

        var wasPaid = transaction.IsPaid;
        if (request.IsPaid && !transaction.IsPaid)
        {
            transaction.IsPaid = true;
            transaction.PaidDate = DateTime.UtcNow;
            transaction.Status = CashTransactionStatus.Completed;
        }
        else if (!request.IsPaid)
        {
            transaction.IsPaid = false;
            transaction.PaidDate = null;
        }

        await context.SaveChangesAsync();

        if (!wasPaid && transaction.IsPaid)
        {
            try
            {
                await CashTransactionLinkageHelper.ApplyOnCashPaidAsync(
                    context, notificationService, transaction, CurrentUserId, storeId);
            }
            catch { /* best-effort */ }
        }

        return await GetTransaction(id);
    }

    /// <summary>
    /// Cập nhật trạng thái giao dịch
    /// </summary>
    [HttpPut("{id}/status")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("CashTransaction", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<CashTransactionDto>>> UpdateTransactionStatus(
        Guid id, 
        [FromBody] UpdateCashTransactionStatusDto request)
    {
        var storeId = RequiredStoreId;
        
        var transaction = await context.CashTransactions
            .AsTracking()
            .Include(x => x.CreatedByUser)
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId);

        if (transaction == null)
            return NotFound(AppResponse<CashTransactionDto>.Error("Không tìm thấy giao dịch"));

        var wasPaid = transaction.IsPaid;
        transaction.Status = request.Status;
        transaction.LastModified = DateTime.UtcNow;

        if (request.Status == CashTransactionStatus.Completed)
        {
            transaction.IsPaid = true;
            transaction.PaidDate ??= DateTime.UtcNow;
        }

        if (request.PaymentMethod.HasValue)
        {
            transaction.PaymentMethod = request.PaymentMethod.Value;
            if (request.PaymentMethod == PaymentMethodType.VietQR && request.BankAccountId.HasValue)
            {
                var bankAccount = await context.BankAccounts.FindAsync(request.BankAccountId.Value);
                if (bankAccount != null)
                {
                    transaction.BankAccountId = bankAccount.Id;
                    transaction.VietQRUrl = VietQRBanks.GenerateVietQRUrl(
                        bankAccount.BankCode,
                        bankAccount.AccountNumber,
                        transaction.Amount,
                        $"{transaction.TransactionCode} - {transaction.Description}",
                        bankAccount.VietQRTemplate);
                }
            }
            else if (request.PaymentMethod == PaymentMethodType.BankTransfer && request.BankAccountId.HasValue)
            {
                transaction.BankAccountId = request.BankAccountId;
            }
        }

        if (request.IsPaid.HasValue)
        {
            transaction.IsPaid = request.IsPaid.Value;
            if (request.IsPaid.Value)
            {
                transaction.PaidDate = DateTime.UtcNow;
                transaction.Status = CashTransactionStatus.Completed;
            }
        }

        await context.SaveChangesAsync();

        if (!wasPaid && transaction.IsPaid)
        {
            try
            {
                await CashTransactionLinkageHelper.ApplyOnCashPaidAsync(
                    context, notificationService, transaction, CurrentUserId, storeId);
            }
            catch { /* best-effort */ }
        }

        // Notify the creator if someone else changes the status
        try
        {
            if (transaction.CreatedByUserId != CurrentUserId)
            {
                var statusText = transaction.Status switch
                {
                    CashTransactionStatus.Completed => "đã hoàn thành",
                    CashTransactionStatus.Cancelled => "đã hủy",
                    CashTransactionStatus.WaitingPayment => "chờ thanh toán",
                    _ => "đã cập nhật"
                };
                await notificationService.CreateAndSendAsync(
                    transaction.CreatedByUserId, NotificationType.Info,
                    "Phiếu thu/chi cập nhật",
                    $"Phiếu {transaction.TransactionCode} {statusText}",
                    relatedEntityType: "CashTransaction", relatedEntityId: id,
                    fromUserId: CurrentUserId, categoryCode: "transaction", storeId: storeId);
            }
        }
        catch { /* Notification failure should not affect main operation */ }

        return await GetTransaction(id);
    }

    /// <summary>
    /// Xóa giao dịch (soft delete)
    /// </summary>
    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("CashTransaction", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteTransaction(Guid id)
    {
        var storeId = RequiredStoreId;
        
        var transaction = await context.CashTransactions
            .AsTracking()
            .Include(x => x.CreatedByUser)
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId);

        if (transaction == null)
            return NotFound(AppResponse<bool>.Error("Không tìm thấy giao dịch"));

        transaction.IsActive = false;
        transaction.Deleted = DateTime.UtcNow;
        transaction.DeletedBy = CurrentUserId.ToString();

        // Phiếu chi ứng lương → hoàn trạng thái chờ thanh toán
        if (CashTransactionLinkageHelper.TryExtractTrailingGuid(
                transaction.InternalNote, "yêu cầu ứng lương #", out var advanceId)
            || CashTransactionLinkageHelper.TryExtractTrailingGuid(
                transaction.InternalNote, "thanh toán ứng lương #", out advanceId))
        {
            var advance = await context.AdvanceRequests.FindAsync(advanceId);
            if (advance != null && advance.IsPaid)
            {
                advance.IsPaid = false;
                advance.PaidDate = null;
                advance.PaymentMethod = null;
                advance.UpdatedAt = DateTime.UtcNow;
            }
        }

        // Ứng công tác → hoàn chi ứng
        if (CashTransactionLinkageHelper.TryExtractTrailingGuid(
                transaction.InternalNote, "ứng công tác #", out var tripAdvanceId))
        {
            var tripAdvance = await context.BusinessTripAdvanceClaims
                .Include(a => a.Case)
                .FirstOrDefaultAsync(a => a.Id == tripAdvanceId && a.StoreId == storeId);
            if (tripAdvance != null && tripAdvance.IsPaid)
            {
                tripAdvance.IsPaid = false;
                tripAdvance.PaidDate = null;
                tripAdvance.PaymentMethod = null;
                tripAdvance.CashTransactionId = null;
                tripAdvance.UpdatedAt = DateTime.UtcNow;
                if (tripAdvance.Case != null
                    && tripAdvance.Case.Status == BusinessTripCaseStatus.AdvancePaid)
                {
                    tripAdvance.Case.Status = BusinessTripCaseStatus.AdvanceApproved;
                    tripAdvance.Case.UpdatedAt = DateTime.UtcNow;
                }
            }
        }

        // Chi bù / thu hoàn công tác → mở lại Settling
        if (CashTransactionLinkageHelper.TryExtractTrailingGuid(
                transaction.InternalNote, "quyết toán công tác phí #", out var settlementId)
            || CashTransactionLinkageHelper.TryExtractTrailingGuid(
                transaction.InternalNote, "thu hoàn ứng công tác #", out settlementId))
        {
            var settlement = await context.BusinessTripSettlementClaims
                .Include(s => s.Case)
                .FirstOrDefaultAsync(s => s.Id == settlementId && s.StoreId == storeId);
            if (settlement != null && settlement.IsExtraPaid)
            {
                settlement.IsExtraPaid = false;
                settlement.ExtraPaidDate = null;
                settlement.ExtraPaymentMethod = null;
                settlement.UpdatedAt = DateTime.UtcNow;
                if (settlement.Case != null
                    && settlement.Case.Status == BusinessTripCaseStatus.Closed)
                {
                    settlement.Case.Status = BusinessTripCaseStatus.Settling;
                    settlement.Case.UpdatedAt = DateTime.UtcNow;
                }
            }
        }

        // Phiếu thu/chi thưởng/phạt → bỏ đánh dấu đã thanh toán trên PaymentTransaction
        if (CashTransactionLinkageHelper.TryExtractTrailingGuid(
                transaction.InternalNote, "phiếu thưởng/phạt #", out var paymentTxId))
        {
            var paymentTx = await context.PaymentTransactions.FindAsync(paymentTxId);
            if (paymentTx != null && !string.IsNullOrEmpty(paymentTx.PaymentMethod))
            {
                paymentTx.PaymentMethod = null;
                paymentTx.UpdatedAt = DateTime.UtcNow;
            }
        }

        // Phiếu chi lương → hoàn phiếu lương về đã chốt, chưa thanh toán
        var linkedPayslip = await context.Payslips
            .FirstOrDefaultAsync(p => p.CashTransactionId == transaction.Id && p.StoreId == storeId);
        if (linkedPayslip == null && CashTransactionLinkageHelper.TryExtractTrailingGuid(
                transaction.InternalNote, "phiếu lương #", out var payslipId))
        {
            linkedPayslip = await context.Payslips
                .FirstOrDefaultAsync(p => p.Id == payslipId && p.StoreId == storeId);
        }
        if (linkedPayslip != null)
        {
            linkedPayslip.Status = PayslipStatus.Approved;
            linkedPayslip.PaidDate = null;
            linkedPayslip.CashTransactionId = null;
            linkedPayslip.UpdatedAt = DateTime.UtcNow;
        }

        await context.SaveChangesAsync();

        return Ok(AppResponse<bool>.Success(true));
    }

    /// <summary>
    /// Lấy tổng hợp thu chi
    /// </summary>
    [HttpGet("summary")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("CashTransaction", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<CashTransactionSummaryDto>>> GetSummary(
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null,
        [FromQuery] Guid? branchId = null,
        [FromQuery] bool includeChildBranches = true)
    {
        var storeId = RequiredStoreId;

        // Default to current month in VN local time — using DateTime.UtcNow.Year/Month would
        // flip to the wrong month between 00:00 and 07:00 VN at month boundaries.
        var nowVn = DateTime.UtcNow.AddHours(7);
        var effectiveFrom = fromDate ?? new DateTime(nowVn.Year, nowVn.Month, 1);
        var effectiveTo = toDate ?? nowVn;

        var query = context.CashTransactions
            .Include(x => x.Category)
            .Include(x => x.CreatedByUser)
            .Where(x => x.StoreId == storeId && 
                        x.IsActive && 
                        x.Status == CashTransactionStatus.Completed &&
                        x.TransactionDate >= effectiveFrom &&
                        x.TransactionDate <= effectiveTo)
            .AsQueryable();

        var branchScope = await BranchQueryHelper.ResolveEmployeeScopeAsync(
            context, storeId, branchId, includeChildBranches);
        if (branchScope != null)
        {
            if (branchScope.ApplicationUserIds.Count == 0)
            {
                return Ok(AppResponse<CashTransactionSummaryDto>.Success(new CashTransactionSummaryDto
                {
                    FromDate = fromDate,
                    ToDate = toDate
                }));
            }
            query = query.Where(x => branchScope.ApplicationUserIds.Contains(x.CreatedByUserId));
        }

        var transactions = await query.ToListAsync();

        var incomeTotal = transactions.Where(x => x.Type == CashTransactionType.Income).Sum(x => x.Amount);
        var expenseTotal = transactions.Where(x => x.Type == CashTransactionType.Expense).Sum(x => x.Amount);

        // Group by category
        var incomeByCategory = transactions
            .Where(x => x.Type == CashTransactionType.Income)
            .GroupBy(x => new { x.CategoryId, x.Category.Name, x.Category.Icon, x.Category.Color })
            .Select(g => new CategorySummaryDto
            {
                CategoryId = g.Key.CategoryId,
                CategoryName = g.Key.Name,
                Icon = g.Key.Icon,
                Color = g.Key.Color,
                Amount = g.Sum(x => x.Amount),
                Count = g.Count(),
                Percentage = incomeTotal > 0 ? Math.Round(g.Sum(x => x.Amount) / incomeTotal * 100, 2) : 0
            })
            .OrderByDescending(x => x.Amount)
            .ToList();

        var expenseByCategory = transactions
            .Where(x => x.Type == CashTransactionType.Expense)
            .GroupBy(x => new { x.CategoryId, x.Category.Name, x.Category.Icon, x.Category.Color })
            .Select(g => new CategorySummaryDto
            {
                CategoryId = g.Key.CategoryId,
                CategoryName = g.Key.Name,
                Icon = g.Key.Icon,
                Color = g.Key.Color,
                Amount = g.Sum(x => x.Amount),
                Count = g.Count(),
                Percentage = expenseTotal > 0 ? Math.Round(g.Sum(x => x.Amount) / expenseTotal * 100, 2) : 0
            })
            .OrderByDescending(x => x.Amount)
            .ToList();

        incomeByCategory = incomeByCategory.Select(FixCategorySummaryEncoding).ToList();
        expenseByCategory = expenseByCategory.Select(FixCategorySummaryEncoding).ToList();

        // Daily summary
        var dailySummary = transactions
            .GroupBy(x => x.TransactionDate.Date)
            .Select(g => new DailySummaryDto
            {
                Date = g.Key,
                Income = g.Where(x => x.Type == CashTransactionType.Income).Sum(x => x.Amount),
                Expense = g.Where(x => x.Type == CashTransactionType.Expense).Sum(x => x.Amount)
            })
            .OrderByDescending(x => x.Date)
            .Take(30)
            .ToList();

        var pendingQuery = context.CashTransactions
            .Where(x => x.StoreId == storeId
                && x.IsActive
                && !x.IsPaid
                && (x.Status == CashTransactionStatus.Pending
                    || x.Status == CashTransactionStatus.WaitingPayment));

        if (branchScope != null)
            pendingQuery = pendingQuery.Where(x => branchScope.ApplicationUserIds.Contains(x.CreatedByUserId));

        var pendingList = await pendingQuery.ToListAsync();
        var pendingIncome = pendingList.Where(x => x.Type == CashTransactionType.Income).ToList();
        var pendingExpense = pendingList.Where(x => x.Type == CashTransactionType.Expense).ToList();

        var summary = new CashTransactionSummaryDto
        {
            TotalIncome = incomeTotal,
            TotalExpense = expenseTotal,
            TotalTransactions = transactions.Count,
            IncomeTransactions = transactions.Count(x => x.Type == CashTransactionType.Income),
            ExpenseTransactions = transactions.Count(x => x.Type == CashTransactionType.Expense),
            PendingTransactions = pendingList.Count,
            PendingIncomeAmount = pendingIncome.Sum(x => x.Amount),
            PendingExpenseAmount = pendingExpense.Sum(x => x.Amount),
            PendingIncomeCount = pendingIncome.Count,
            PendingExpenseCount = pendingExpense.Count,
            FromDate = fromDate,
            ToDate = toDate,
            IncomeByCategory = incomeByCategory,
            ExpenseByCategory = expenseByCategory,
            DailySummary = dailySummary
        };

        return Ok(AppResponse<CashTransactionSummaryDto>.Success(summary));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIETQR - TẠO MÃ QR THANH TOÁN
    // ═══════════════════════════════════════════════════════════════════════════

    /// <summary>
    /// Tạo VietQR URL từ thông tin thanh toán
    /// </summary>
    [HttpPost("vietqr/generate")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("CashTransaction", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<VietQRResponseDto>>> GenerateVietQR([FromBody] GenerateVietQRRequest request)
    {
        string bankCode, accountNumber, accountName, bankName, bankLogo;

        if (request.BankAccountId.HasValue)
        {
            var bankAccount = await context.BankAccounts.FindAsync(request.BankAccountId.Value);
            if (bankAccount == null)
                return BadRequest(AppResponse<VietQRResponseDto>.Error("Không tìm thấy tài khoản ngân hàng"));

            bankCode = bankAccount.BankCode;
            accountNumber = bankAccount.AccountNumber;
            accountName = bankAccount.AccountName;
            bankName = bankAccount.BankName;
            bankLogo = bankAccount.BankLogoUrl ?? "";
        }
        else if (!string.IsNullOrEmpty(request.BankCode) && !string.IsNullOrEmpty(request.AccountNumber))
        {
            bankCode = request.BankCode;
            accountNumber = request.AccountNumber;
            
            // Try to find bank info
            if (VietQRBanks.Banks.TryGetValue(bankCode, out var bankInfo))
            {
                bankName = bankInfo.Name;
                bankLogo = bankInfo.Logo;
            }
            else
            {
                bankName = bankCode;
                bankLogo = "";
            }
            accountName = "";
        }
        else
        {
            return BadRequest(AppResponse<VietQRResponseDto>.Error("Cần cung cấp BankAccountId hoặc BankCode + AccountNumber"));
        }

        var qrUrl = VietQRBanks.GenerateVietQRUrl(
            bankCode,
            accountNumber,
            request.Amount,
            request.Description,
            request.Template);

        var response = new VietQRResponseDto
        {
            QRUrl = qrUrl,
            QRDataUrl = qrUrl,
            BankName = bankName,
            BankLogo = bankLogo,
            AccountNumber = accountNumber,
            AccountName = accountName,
            Amount = request.Amount,
            Description = request.Description
        };

        return Ok(AppResponse<VietQRResponseDto>.Success(response));
    }

    /// <summary>
    /// Lấy danh sách ngân hàng hỗ trợ VietQR
    /// </summary>
    [HttpGet("vietqr/banks")]
    [AllowAnonymous]
    public ActionResult<AppResponse<List<VietQRBankDto>>> GetVietQRBanks()
    {
        var banks = VietQRBanks.Banks
            .Select(x => new VietQRBankDto
            {
                Code = x.Key,
                BIN = x.Value.BIN,
                Name = x.Value.Name,
                ShortName = x.Value.ShortName,
                LogoUrl = x.Value.Logo
            })
            .OrderBy(x => x.ShortName)
            .ToList();

        return Ok(AppResponse<List<VietQRBankDto>>.Success(banks));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CHUYỂN QUỸ - FUND TRANSFERS
    // ═══════════════════════════════════════════════════════════════════════════

    [HttpGet("fund-transfers")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("CashTransaction", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<PagedResult<FundTransferDto>>>> GetFundTransfers(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null)
    {
        var storeId = RequiredStoreId;
        var query = context.FundTransfers
            .Include(x => x.FromBankAccount)
            .Include(x => x.ToBankAccount)
            .Include(x => x.CreatedByUser)
            .Where(x => x.StoreId == storeId && x.IsActive);

        if (fromDate.HasValue)
            query = query.Where(x => x.TransferDate >= fromDate.Value);
        if (toDate.HasValue)
            query = query.Where(x => x.TransferDate <= toDate.Value);

        var total = await query.CountAsync();
        var entities = await query
            .OrderByDescending(x => x.TransferDate)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();
        var items = entities.Select(MapFundTransferDto).ToList();

        return Ok(AppResponse<PagedResult<FundTransferDto>>.Success(new PagedResult<FundTransferDto>
        {
            Items = items,
            TotalCount = total,
            PageNumber = page,
            PageSize = pageSize
        }));
    }

    [HttpGet("fund-balances")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("CashTransaction", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<FundBalanceDto>>>> GetFundBalances()
    {
        var storeId = RequiredStoreId;
        var balances = await BuildFundBalancesAsync(storeId);
        return Ok(AppResponse<List<FundBalanceDto>>.Success(balances));
    }

    [HttpPost("fund-transfers")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("CashTransaction", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<FundTransferDto>>> CreateFundTransfer(
        [FromBody] CreateFundTransferDto request)
    {
        var storeId = RequiredStoreId;

        if (request.Amount <= 0)
            return BadRequest(AppResponse<FundTransferDto>.Error("Số tiền phải lớn hơn 0"));

        if (request.FromBankAccountId == request.ToBankAccountId)
            return BadRequest(AppResponse<FundTransferDto>.Error("Quỹ nguồn và quỹ đích phải khác nhau"));

        if (!await ValidateBankAccountAsync(storeId, request.FromBankAccountId))
            return BadRequest(AppResponse<FundTransferDto>.Error("Tài khoản nguồn không hợp lệ"));

        if (!await ValidateBankAccountAsync(storeId, request.ToBankAccountId))
            return BadRequest(AppResponse<FundTransferDto>.Error("Tài khoản đích không hợp lệ"));

        var today = DateTime.UtcNow;
        var dateStr = today.ToString("yyyyMMdd");
        var count = await context.FundTransfers
            .CountAsync(x => x.StoreId == storeId && x.TransferCode.StartsWith($"CQ-{dateStr}")) + 1;
        var transferCode = $"CQ-{dateStr}-{count:D4}";

        var transfer = new FundTransfer
        {
            Id = Guid.NewGuid(),
            TransferCode = transferCode,
            FromBankAccountId = request.FromBankAccountId,
            ToBankAccountId = request.ToBankAccountId,
            Amount = request.Amount,
            TransferDate = request.TransferDate,
            Description = request.Description,
            InternalNote = request.InternalNote,
            CreatedByUserId = CurrentUserId,
            StoreId = storeId,
            IsActive = true
        };

        context.FundTransfers.Add(transfer);
        await context.SaveChangesAsync();

        var created = await context.FundTransfers
            .Include(x => x.FromBankAccount)
            .Include(x => x.ToBankAccount)
            .Include(x => x.CreatedByUser)
            .FirstAsync(x => x.Id == transfer.Id);

        return Ok(AppResponse<FundTransferDto>.Success(MapFundTransferDto(created)));
    }

    [HttpDelete("fund-transfers/{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("CashTransaction", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteFundTransfer(Guid id)
    {
        var storeId = RequiredStoreId;
        var transfer = await context.FundTransfers.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.IsActive);
        if (transfer == null)
            return NotFound(AppResponse<bool>.Error("Không tìm thấy phiếu chuyển quỹ"));

        transfer.IsActive = false;
        transfer.LastModified = DateTime.UtcNow;
        await context.SaveChangesAsync();
        return Ok(AppResponse<bool>.Success(true));
    }

    private async Task<bool> ValidateBankAccountAsync(Guid storeId, Guid? bankAccountId)
    {
        if (!bankAccountId.HasValue) return true;
        return await context.BankAccounts.AnyAsync(x =>
            x.Id == bankAccountId.Value && x.StoreId == storeId && x.IsActive);
    }

    private static FundTransferDto MapFundTransferDto(FundTransfer x) => new()
    {
        Id = x.Id,
        TransferCode = x.TransferCode,
        FromBankAccountId = x.FromBankAccountId,
        FromFundLabel = FormatFundLabel(x.FromBankAccount),
        ToBankAccountId = x.ToBankAccountId,
        ToFundLabel = FormatFundLabel(x.ToBankAccount),
        Amount = x.Amount,
        TransferDate = x.TransferDate,
        Description = x.Description,
        InternalNote = x.InternalNote,
        CreatedByUserId = x.CreatedByUserId,
        CreatedByUserName = x.CreatedByUser?.UserName ?? "",
        CreatedAt = x.CreatedAt
    };

    private static string FormatFundLabel(BankAccount? account)
        => account == null
            ? "Tiền mặt"
            : $"{account.BankShortName ?? account.BankName} - {account.AccountNumber}";

    private async Task<List<FundBalanceDto>> BuildFundBalancesAsync(Guid storeId)
    {
        var completed = CashTransactionStatus.Completed;

        var cashIncome = await context.CashTransactions
            .Where(x => x.StoreId == storeId && x.IsActive && x.Status == completed
                        && x.Type == CashTransactionType.Income
                        && x.PaymentMethod == PaymentMethodType.Cash)
            .SumAsync(x => (decimal?)x.Amount) ?? 0m;

        var cashExpense = await context.CashTransactions
            .Where(x => x.StoreId == storeId && x.IsActive && x.Status == completed
                        && x.Type == CashTransactionType.Expense
                        && x.PaymentMethod == PaymentMethodType.Cash)
            .SumAsync(x => (decimal?)x.Amount) ?? 0m;

        var transferInCash = await context.FundTransfers
            .Where(x => x.StoreId == storeId && x.IsActive && x.ToBankAccountId == null)
            .SumAsync(x => (decimal?)x.Amount) ?? 0m;

        var transferOutCash = await context.FundTransfers
            .Where(x => x.StoreId == storeId && x.IsActive && x.FromBankAccountId == null)
            .SumAsync(x => (decimal?)x.Amount) ?? 0m;

        var cashBalance = cashIncome - cashExpense + transferInCash - transferOutCash;

        var result = new List<FundBalanceDto>
        {
            new() { BankAccountId = null, Label = "Tiền mặt", IsCash = true, Balance = cashBalance }
        };

        var bankAccounts = await context.BankAccounts
            .Where(x => x.StoreId == storeId && x.IsActive)
            .OrderByDescending(x => x.IsDefault)
            .ThenBy(x => x.BankName)
            .ToListAsync();

        foreach (var bank in bankAccounts)
        {
            var bankIncome = await context.CashTransactions
                .Where(x => x.StoreId == storeId && x.IsActive && x.Status == completed
                            && x.Type == CashTransactionType.Income && x.BankAccountId == bank.Id)
                .SumAsync(x => (decimal?)x.Amount) ?? 0m;

            var bankExpense = await context.CashTransactions
                .Where(x => x.StoreId == storeId && x.IsActive && x.Status == completed
                            && x.Type == CashTransactionType.Expense && x.BankAccountId == bank.Id)
                .SumAsync(x => (decimal?)x.Amount) ?? 0m;

            var inTransfer = await context.FundTransfers
                .Where(x => x.StoreId == storeId && x.IsActive && x.ToBankAccountId == bank.Id)
                .SumAsync(x => (decimal?)x.Amount) ?? 0m;

            var outTransfer = await context.FundTransfers
                .Where(x => x.StoreId == storeId && x.IsActive && x.FromBankAccountId == bank.Id)
                .SumAsync(x => (decimal?)x.Amount) ?? 0m;

            result.Add(new FundBalanceDto
            {
                BankAccountId = bank.Id,
                Label = $"{bank.AccountName} ({bank.AccountNumber})",
                BankShortName = bank.BankShortName ?? bank.BankName,
                IsCash = false,
                Balance = bankIncome - bankExpense + inTransfer - outTransfer
            });
        }

        return result;
    }

    private static CashTransactionDto FixTransactionDtoEncoding(CashTransactionDto dto)
        => dto with { CategoryName = VietnameseEncodingFix.TryFix(dto.CategoryName) };

    private static CategorySummaryDto FixCategorySummaryEncoding(CategorySummaryDto dto)
        => dto with { CategoryName = VietnameseEncodingFix.TryFix(dto.CategoryName) };
}
