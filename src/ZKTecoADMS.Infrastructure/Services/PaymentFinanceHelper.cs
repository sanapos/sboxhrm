using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>
/// Tạo / hoàn tất / hủy phiếu thu/chi liên kết khi duyệt hoặc thanh toán thưởng, phạt, ứng lương.
/// </summary>
public static class PaymentFinanceHelper
{
    public const string SalaryDisbursementMethod = "Salary";

    public static string BonusPenaltyNote(Guid paymentTxId)
        => $"Tự động tạo từ phiếu thưởng/phạt #{paymentTxId}";

    public static bool IsSalaryDisbursement(PaymentTransaction tx)
        => tx.Type == "Bonus"
           && string.Equals(tx.PaymentMethod, SalaryDisbursementMethod, StringComparison.OrdinalIgnoreCase);

    /// <summary>
    /// Phiếu thưởng: Cash → phiếu chi chờ thanh toán; Salary → gắn PaymentMethod=Salary, không tạo phiếu chi.
    /// Phiếu phạt: luôn tạo phiếu thu.
    /// </summary>
    public static async Task<CashTransaction?> ApplyBonusPenaltyDisbursementOnApproveAsync(
        ZKTecoDbContext db,
        PaymentTransaction tx,
        Guid storeId,
        Guid createdByUserId,
        string? disbursementMode = null,
        CancellationToken cancellationToken = default)
    {
        if (tx.Status != "Completed" || tx.Type is not ("Bonus" or "Penalty"))
            return null;

        if (tx.Type == "Bonus"
            && string.Equals(disbursementMode, SalaryDisbursementMethod, StringComparison.OrdinalIgnoreCase))
        {
            tx.PaymentMethod = SalaryDisbursementMethod;
            await db.SaveChangesAsync(cancellationToken);
            return null;
        }

        if (tx.Type == "Bonus")
            tx.PaymentMethod = null;

        return await CreateBonusPenaltyPendingOnApproveAsync(
            db, tx, storeId, createdByUserId, cancellationToken);
    }

    public static void ClearSalaryDisbursementOnUnapprove(PaymentTransaction tx)
    {
        if (IsSalaryDisbursement(tx))
            tx.PaymentMethod = null;
    }

    public static string AdvanceNote(Guid advanceId)
        => $"Tự động tạo từ yêu cầu ứng lương #{advanceId}";

    public static async Task<CashTransaction?> ResolveLinkedAsync(
        ZKTecoDbContext db,
        Guid storeId,
        string marker,
        CancellationToken cancellationToken = default)
    {
        return await db.CashTransactions
            .Where(c => c.StoreId == storeId
                && c.Deleted == null
                && c.IsActive
                && c.InternalNote != null
                && c.InternalNote.Contains(marker))
            .OrderByDescending(c => c.CreatedAt)
            .FirstOrDefaultAsync(cancellationToken);
    }

    public static async Task<CashTransaction?> CreateBonusPenaltyPendingOnApproveAsync(
        ZKTecoDbContext db,
        PaymentTransaction tx,
        Guid storeId,
        Guid createdByUserId,
        CancellationToken cancellationToken = default)
    {
        if (tx.Status != "Completed" || tx.Type is not ("Bonus" or "Penalty"))
            return null;

        var marker = BonusPenaltyNote(tx.Id);
        var existing = await ResolveLinkedAsync(db, storeId, marker, cancellationToken);
        if (existing != null)
            return existing;

        var isPenalty = tx.Type == "Penalty";
        var cashType = isPenalty ? CashTransactionType.Income : CashTransactionType.Expense;
        var categoryName = isPenalty ? "Phạt nhân viên" : "Thưởng nhân viên";

        var category = await ResolveCategoryAsync(db, storeId, cashType, categoryName, cancellationToken);
        if (category == null) return null;

        var employee = tx.EmployeeId.HasValue
            ? await db.Employees.AsNoTracking().FirstOrDefaultAsync(e => e.Id == tx.EmployeeId, cancellationToken)
            : null;
        var empName = employee != null
            ? $"{employee.LastName} {employee.FirstName}".Trim()
            : "N/A";

        var transactionCode = await GenerateCodeAsync(db, storeId, cashType, cancellationToken);
        var cashTx = new CashTransaction
        {
            Id = Guid.NewGuid(),
            TransactionCode = transactionCode,
            Type = cashType,
            CategoryId = category.Id,
            Amount = Math.Abs(tx.Amount),
            TransactionDate = DateTime.UtcNow,
            Description = $"{(isPenalty ? "Thu tiền phạt" : "Thưởng")} - {empName} - {tx.Description}",
            PaymentMethod = PaymentMethodType.Cash,
            Status = CashTransactionStatus.WaitingPayment,
            IsPaid = false,
            ContactName = empName,
            CreatedByUserId = createdByUserId,
            StoreId = storeId,
            InternalNote = !string.IsNullOrEmpty(tx.Note)
                ? $"{tx.Note} | {marker}"
                : marker,
            IsActive = true
        };

        db.CashTransactions.Add(cashTx);
        await db.SaveChangesAsync(cancellationToken);
        return cashTx;
    }

    public static async Task<CashTransaction?> CreateAdvancePendingOnApproveAsync(
        ZKTecoDbContext db,
        AdvanceRequest advance,
        Guid storeId,
        Guid createdByUserId,
        CancellationToken cancellationToken = default)
    {
        if (advance.Status != AdvanceRequestStatus.Approved || advance.IsPaid)
            return null;

        var marker = AdvanceNote(advance.Id);
        var existing = await ResolveLinkedAsync(db, storeId, marker, cancellationToken);
        if (existing != null)
            return existing;

        var category = await ResolveCategoryAsync(db, storeId, CashTransactionType.Expense, "Ứng lương", cancellationToken);
        if (category == null)
        {
            category = new TransactionCategory
            {
                Id = Guid.NewGuid(),
                Name = "Ứng lương",
                Description = "Chi ứng lương cho nhân viên",
                Type = CashTransactionType.Expense,
                Icon = "money_off",
                Color = "#FF9800",
                IsSystem = true,
                IsActive = true,
                StoreId = storeId
            };
            db.TransactionCategories.Add(category);
            await db.SaveChangesAsync(cancellationToken);
        }

        var employee = advance.EmployeeId.HasValue
            ? await db.Employees.AsNoTracking().FirstOrDefaultAsync(e => e.Id == advance.EmployeeId, cancellationToken)
            : null;
        var empName = employee != null
            ? $"{employee.LastName} {employee.FirstName}".Trim()
            : advance.EmployeeUser != null
                ? $"{advance.EmployeeUser.LastName} {advance.EmployeeUser.FirstName}".Trim()
                : "N/A";

        var transactionCode = await GenerateCodeAsync(db, storeId, CashTransactionType.Expense, cancellationToken);
        var cashTx = new CashTransaction
        {
            Id = Guid.NewGuid(),
            TransactionCode = transactionCode,
            Type = CashTransactionType.Expense,
            CategoryId = category.Id,
            Amount = advance.Amount,
            TransactionDate = DateTime.UtcNow,
            Description = $"Chi ứng lương - {empName} - {advance.Reason}",
            PaymentMethod = PaymentMethodType.Cash,
            Status = CashTransactionStatus.WaitingPayment,
            IsPaid = false,
            ContactName = empName,
            CreatedByUserId = createdByUserId,
            StoreId = storeId,
            InternalNote = marker,
            IsActive = true
        };

        db.CashTransactions.Add(cashTx);
        await db.SaveChangesAsync(cancellationToken);
        return cashTx;
    }

    public static bool CompleteCashTransaction(
        CashTransaction cash,
        PaymentMethodType paymentMethod,
        Guid performedByUserId)
    {
        if (cash.Deleted != null || !cash.IsActive)
            return false;

        cash.PaymentMethod = paymentMethod;
        cash.Status = CashTransactionStatus.Completed;
        cash.IsPaid = true;
        cash.PaidDate = DateTime.UtcNow;
        cash.UpdatedAt = DateTime.UtcNow;
        return true;
    }

    public static bool CancelLinkedCashTransaction(CashTransaction? cash, string? reason = null)
    {
        if (cash == null || cash.Deleted != null)
            return false;

        cash.Status = CashTransactionStatus.Cancelled;
        cash.IsPaid = false;
        cash.PaidDate = null;
        cash.IsActive = false;
        cash.UpdatedAt = DateTime.UtcNow;
        if (!string.IsNullOrWhiteSpace(reason))
            cash.InternalNote = AppendNote(cash.InternalNote, reason);
        return true;
    }

    public static bool SoftDeleteLinkedCashTransaction(CashTransaction? cash, string? reason = null)
    {
        if (cash == null || cash.Deleted != null)
            return false;

        cash.Deleted = DateTime.UtcNow;
        cash.IsActive = false;
        cash.Status = CashTransactionStatus.Cancelled;
        cash.IsPaid = false;
        cash.PaidDate = null;
        cash.UpdatedAt = DateTime.UtcNow;
        if (!string.IsNullOrWhiteSpace(reason))
            cash.InternalNote = AppendNote(cash.InternalNote, reason);
        return true;
    }

    private static async Task<TransactionCategory?> ResolveCategoryAsync(
        ZKTecoDbContext db,
        Guid storeId,
        CashTransactionType type,
        string categoryName,
        CancellationToken cancellationToken)
    {
        var categories = await db.TransactionCategories
            .Where(c => c.IsActive && c.StoreId == storeId && c.Type == type)
            .ToListAsync(cancellationToken);

        return categories.FirstOrDefault(c =>
                   c.Name == categoryName || VietnameseEncodingFix.TryFix(c.Name) == categoryName)
               ?? categories.FirstOrDefault();
    }

    private static async Task<string> GenerateCodeAsync(
        ZKTecoDbContext db,
        Guid storeId,
        CashTransactionType type,
        CancellationToken cancellationToken)
    {
        var today = DateTime.UtcNow;
        var prefix = type == CashTransactionType.Income ? "TH" : "CH";
        var dateStr = today.ToString("yyyyMMdd");
        var count = await db.CashTransactions
            .CountAsync(x => x.StoreId == storeId && x.TransactionCode.StartsWith($"{prefix}-{dateStr}"),
                cancellationToken) + 1;
        return $"{prefix}-{dateStr}-{count:D4}";
    }

    private static string AppendNote(string? existing, string addition)
    {
        if (string.IsNullOrWhiteSpace(existing))
            return addition;
        if (existing.Contains(addition, StringComparison.Ordinal))
            return existing;
        return $"{existing} | {addition}";
    }
}
