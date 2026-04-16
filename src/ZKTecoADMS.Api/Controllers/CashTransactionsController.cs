using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Commons;
using ZKTecoADMS.Application.DTOs.Transactions;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class CashTransactionsController(ZKTecoDbContext context, ISystemNotificationService notificationService) : AuthenticatedControllerBase
{
    // ═══════════════════════════════════════════════════════════════════════════
    // GIAO DỊCH THU CHI - CASH TRANSACTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// <summary>
    /// Lấy danh sách giao dịch thu chi
    /// </summary>
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
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
                Status = x.Status,
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
                Status = x.Status,
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

        return Ok(AppResponse<CashTransactionDto>.Success(transaction));
    }

    /// <summary>
    /// Tạo giao dịch mới
    /// </summary>
    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
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

        // Return with full info
        return await GetTransaction(transaction.Id);
    }

    /// <summary>
    /// Cập nhật giao dịch
    /// </summary>
    [HttpPut("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
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
        return await GetTransaction(id);
    }

    /// <summary>
    /// Cập nhật trạng thái giao dịch
    /// </summary>
    [HttpPut("{id}/status")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
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

        transaction.Status = request.Status;
        transaction.LastModified = DateTime.UtcNow;

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

        // Nếu phiếu chi liên quan đến ứng lương, revert advance request về chờ thanh toán
        if (transaction.InternalNote != null && transaction.InternalNote.Contains("thanh toán ứng lương #"))
        {
            var marker = transaction.InternalNote;
            var hashIndex = marker.LastIndexOf('#');
            if (hashIndex >= 0 && Guid.TryParse(marker[(hashIndex + 1)..], out var advanceId))
            {
                var advance = await context.AdvanceRequests.FindAsync(advanceId);
                if (advance != null && advance.IsPaid)
                {
                    advance.IsPaid = false;
                    advance.PaidDate = null;
                    advance.PaymentMethod = null;
                }
            }
        }

        // Nếu phiếu thu/chi liên quan đến thưởng/phạt, revert PaymentTransaction về chờ thanh toán
        if (transaction.InternalNote != null && transaction.InternalNote.Contains("phiếu thưởng/phạt #"))
        {
            var marker = transaction.InternalNote;
            var hashIndex = marker.LastIndexOf('#');
            if (hashIndex >= 0 && Guid.TryParse(marker[(hashIndex + 1)..], out var txId))
            {
                var paymentTx = await context.PaymentTransactions.FindAsync(txId);
                if (paymentTx != null && !string.IsNullOrEmpty(paymentTx.PaymentMethod))
                {
                    paymentTx.PaymentMethod = null;
                }
            }
        }

        await context.SaveChangesAsync();

        return Ok(AppResponse<bool>.Success(true));
    }

    /// <summary>
    /// Lấy tổng hợp thu chi
    /// </summary>
    [HttpGet("summary")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<CashTransactionSummaryDto>>> GetSummary(
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null)
    {
        var storeId = RequiredStoreId;
        
        // Default to current month if no dates provided to prevent loading all historical data
        var effectiveFrom = fromDate ?? new DateTime(DateTime.UtcNow.Year, DateTime.UtcNow.Month, 1);
        var effectiveTo = toDate ?? DateTime.UtcNow;

        var query = context.CashTransactions
            .Include(x => x.Category)
            .Include(x => x.CreatedByUser)
            .Where(x => x.StoreId == storeId && 
                        x.IsActive && 
                        x.Status == CashTransactionStatus.Completed &&
                        x.TransactionDate >= effectiveFrom &&
                        x.TransactionDate <= effectiveTo)
            .AsQueryable();

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

        var pendingCount = await context.CashTransactions
            .CountAsync(x => x.StoreId == storeId && 
                            x.IsActive && 
                            x.Status == CashTransactionStatus.Pending);

        var summary = new CashTransactionSummaryDto
        {
            TotalIncome = incomeTotal,
            TotalExpense = expenseTotal,
            TotalTransactions = transactions.Count,
            IncomeTransactions = transactions.Count(x => x.Type == CashTransactionType.Income),
            ExpenseTransactions = transactions.Count(x => x.Type == CashTransactionType.Expense),
            PendingTransactions = pendingCount,
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
}
