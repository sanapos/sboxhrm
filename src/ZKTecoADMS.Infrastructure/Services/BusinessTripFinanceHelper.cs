using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>Phiếu thu/chi / ứng lương liên kết hồ sơ công tác phí.</summary>
public static class BusinessTripFinanceHelper
{
    public const string AdvanceCategoryName = "Ứng công tác";
    public const string ExpenseCategoryName = "Công tác phí";
    public const string SurplusRefundCategoryName = "Thu hoàn ứng công tác";

    public static string TripAdvanceNote(Guid advanceClaimId)
        => $"Tự động tạo từ ứng công tác #{advanceClaimId}";

    public static string SettlementExtraNote(Guid settlementClaimId)
        => $"Tự động tạo từ quyết toán công tác phí #{settlementClaimId}";

    public static string SurplusRefundNote(Guid settlementClaimId)
        => $"Tự động tạo từ thu hoàn ứng công tác #{settlementClaimId}";

    public static async Task<CashTransaction?> CreateTripAdvancePendingOnApproveAsync(
        ZKTecoDbContext db,
        BusinessTripAdvanceClaim advance,
        BusinessTripCase tripCase,
        Guid storeId,
        Guid createdByUserId,
        CancellationToken cancellationToken = default)
    {
        if (advance.Status != AdvanceRequestStatus.Approved || advance.IsPaid)
            return null;

        var marker = TripAdvanceNote(advance.Id);
        var existing = await PaymentFinanceHelper.ResolveLinkedAsync(db, storeId, marker, cancellationToken);
        if (existing != null)
        {
            advance.CashTransactionId ??= existing.Id;
            await db.SaveChangesAsync(cancellationToken);
            return existing;
        }

        var category = await ResolveOrCreateCategoryAsync(
            db, storeId, CashTransactionType.Expense, AdvanceCategoryName,
            "Chi ứng trước công tác", "flight_takeoff", "#0EA5E9", cancellationToken);

        var empName = await ResolveEmployeeNameAsync(db, tripCase, cancellationToken);
        var transactionCode = await GenerateCodeAsync(
            db, storeId, CashTransactionType.Expense, cancellationToken);

        var cashTx = new CashTransaction
        {
            Id = Guid.NewGuid(),
            TransactionCode = transactionCode,
            Type = CashTransactionType.Expense,
            CategoryId = category.Id,
            Amount = advance.Amount,
            TransactionDate = DateTime.UtcNow,
            Description = $"Chi ứng công tác - {empName} - {tripCase.CaseCode}",
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
        advance.CashTransactionId = cashTx.Id;
        await db.SaveChangesAsync(cancellationToken);
        return cashTx;
    }

    public static async Task<CashTransaction?> CreateSettlementExtraPendingAsync(
        ZKTecoDbContext db,
        BusinessTripSettlementClaim settlement,
        BusinessTripCase tripCase,
        Guid storeId,
        Guid createdByUserId,
        CancellationToken cancellationToken = default)
    {
        if (settlement.SettlementType != BusinessTripSettlementType.PayExtra
            || settlement.BalanceAmount <= 0
            || settlement.IsExtraPaid)
            return null;

        var marker = SettlementExtraNote(settlement.Id);
        var existing = await PaymentFinanceHelper.ResolveLinkedAsync(db, storeId, marker, cancellationToken);
        if (existing != null)
        {
            settlement.ExtraCashTransactionId ??= existing.Id;
            await db.SaveChangesAsync(cancellationToken);
            return existing;
        }

        var category = await ResolveOrCreateCategoryAsync(
            db, storeId, CashTransactionType.Expense, ExpenseCategoryName,
            "Chi bù công tác phí", "receipt_long", "#6366F1", cancellationToken);

        var empName = await ResolveEmployeeNameAsync(db, tripCase, cancellationToken);
        var transactionCode = await GenerateCodeAsync(
            db, storeId, CashTransactionType.Expense, cancellationToken);

        var cashTx = new CashTransaction
        {
            Id = Guid.NewGuid(),
            TransactionCode = transactionCode,
            Type = CashTransactionType.Expense,
            CategoryId = category.Id,
            Amount = settlement.BalanceAmount,
            TransactionDate = DateTime.UtcNow,
            Description = $"Chi bù công tác phí - {empName} - {tripCase.CaseCode}",
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
        settlement.ExtraCashTransactionId = cashTx.Id;
        await db.SaveChangesAsync(cancellationToken);
        return cashTx;
    }

    /// <summary>
    /// Dư ứng → tạo AdvanceRequest đã chi (IsPaid) để trừ lương + PaymentTransaction.
    /// </summary>
    public static async Task<(AdvanceRequest? Advance, PaymentTransaction? Payment)> CreateSurplusAsAdvanceAsync(
        ZKTecoDbContext db,
        BusinessTripSettlementClaim settlement,
        BusinessTripCase tripCase,
        Guid performedByUserId,
        CancellationToken cancellationToken = default)
    {
        if (settlement.BalanceAmount >= 0)
            return (null, null);

        if (settlement.SurplusAdvanceRequestId.HasValue || settlement.SurplusPaymentTransactionId.HasValue)
        {
            AdvanceRequest? existingAdv = null;
            if (settlement.SurplusAdvanceRequestId.HasValue)
                existingAdv = await db.AdvanceRequests.AsNoTracking()
                    .FirstOrDefaultAsync(a => a.Id == settlement.SurplusAdvanceRequestId, cancellationToken);
            PaymentTransaction? existingPt = null;
            if (settlement.SurplusPaymentTransactionId.HasValue)
                existingPt = await db.PaymentTransactions.AsNoTracking()
                    .FirstOrDefaultAsync(p => p.Id == settlement.SurplusPaymentTransactionId, cancellationToken);
            return (existingAdv, existingPt);
        }

        var surplus = Math.Abs(settlement.BalanceAmount);
        var empName = await ResolveEmployeeNameAsync(db, tripCase, cancellationToken);
        var now = DateTime.UtcNow;

        var advanceReq = new AdvanceRequest
        {
            Id = Guid.NewGuid(),
            EmployeeUserId = tripCase.EmployeeUserId,
            EmployeeId = tripCase.EmployeeId,
            Amount = surplus,
            Reason = $"Dư ứng công tác {tripCase.CaseCode} — ghi nợ trừ lương ({empName})",
            RequestDate = now,
            Status = AdvanceRequestStatus.Approved,
            ApprovedById = performedByUserId,
            ApprovedDate = now,
            Note = SettlementExtraNote(settlement.Id),
            IsPaid = true,
            PaymentMethod = "SalaryDebt",
            PaidDate = now,
            ForMonth = now.Month,
            ForYear = now.Year,
            StoreId = tripCase.StoreId,
            TotalApprovalLevels = 1,
            CurrentApprovalStep = 1,
            IsActive = true
        };
        db.AdvanceRequests.Add(advanceReq);

        var paymentTx = new PaymentTransaction
        {
            Id = Guid.NewGuid(),
            EmployeeUserId = tripCase.EmployeeUserId ?? Guid.Empty,
            EmployeeId = tripCase.EmployeeId,
            Type = "AdvancePayment",
            TransactionDate = now,
            Amount = surplus,
            Description = $"Dư ứng công tác {tripCase.CaseCode} — ghi nợ ứng lương ({empName})",
            Status = "Completed",
            PaymentMethod = "SalaryDebt",
            PerformedById = performedByUserId,
            AdvanceRequestId = advanceReq.Id,
            Note = SettlementExtraNote(settlement.Id)
        };
        db.PaymentTransactions.Add(paymentTx);

        settlement.SettlementType = BusinessTripSettlementType.SurplusAsAdvance;
        settlement.SurplusAdvanceRequestId = advanceReq.Id;
        settlement.SurplusPaymentTransactionId = paymentTx.Id;
        await db.SaveChangesAsync(cancellationToken);
        return (advanceReq, paymentTx);
    }

    /// <summary>Dư ứng → phiếu thu chờ hoàn tiền mặt.</summary>
    public static async Task<CashTransaction?> CreateSurplusRefundPendingAsync(
        ZKTecoDbContext db,
        BusinessTripSettlementClaim settlement,
        BusinessTripCase tripCase,
        Guid storeId,
        Guid createdByUserId,
        CancellationToken cancellationToken = default)
    {
        if (settlement.BalanceAmount >= 0)
            return null;

        var marker = SurplusRefundNote(settlement.Id);
        var existing = await PaymentFinanceHelper.ResolveLinkedAsync(db, storeId, marker, cancellationToken);
        if (existing != null)
        {
            settlement.SettlementType = BusinessTripSettlementType.SurplusRefunded;
            settlement.ExtraCashTransactionId ??= existing.Id;
            await db.SaveChangesAsync(cancellationToken);
            return existing;
        }

        var category = await ResolveOrCreateCategoryAsync(
            db, storeId, CashTransactionType.Income, SurplusRefundCategoryName,
            "Thu hoàn dư ứng công tác", "undo", "#10B981", cancellationToken);

        var empName = await ResolveEmployeeNameAsync(db, tripCase, cancellationToken);
        var surplus = Math.Abs(settlement.BalanceAmount);
        var transactionCode = await GenerateCodeAsync(
            db, storeId, CashTransactionType.Income, cancellationToken);

        var cashTx = new CashTransaction
        {
            Id = Guid.NewGuid(),
            TransactionCode = transactionCode,
            Type = CashTransactionType.Income,
            CategoryId = category.Id,
            Amount = surplus,
            TransactionDate = DateTime.UtcNow,
            Description = $"Thu hoàn dư ứng công tác - {empName} - {tripCase.CaseCode}",
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
        settlement.SettlementType = BusinessTripSettlementType.SurplusRefunded;
        settlement.ExtraCashTransactionId = cashTx.Id;
        settlement.IsExtraPaid = false;
        await db.SaveChangesAsync(cancellationToken);
        return cashTx;
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

    private static async Task<string> ResolveEmployeeNameAsync(
        ZKTecoDbContext db, BusinessTripCase tripCase, CancellationToken ct)
    {
        if (tripCase.EmployeeId.HasValue)
        {
            var emp = await db.Employees.AsNoTracking()
                .FirstOrDefaultAsync(e => e.Id == tripCase.EmployeeId, ct);
            if (emp != null)
                return $"{emp.LastName} {emp.FirstName}".Trim();
        }

        if (tripCase.EmployeeUserId.HasValue)
        {
            var user = await db.Users.AsNoTracking()
                .FirstOrDefaultAsync(u => u.Id == tripCase.EmployeeUserId, ct);
            if (user != null)
                return user.FullName ?? user.Email ?? "N/A";
        }

        return "N/A";
    }

    private static async Task<TransactionCategory> ResolveOrCreateCategoryAsync(
        ZKTecoDbContext db,
        Guid storeId,
        CashTransactionType type,
        string name,
        string description,
        string icon,
        string color,
        CancellationToken ct)
    {
        var category = await db.TransactionCategories
            .FirstOrDefaultAsync(c => c.StoreId == storeId && c.Name == name && c.Type == type && c.IsActive, ct);

        if (category != null)
            return category;

        category = new TransactionCategory
        {
            Id = Guid.NewGuid(),
            Name = name,
            Description = description,
            Type = type,
            Icon = icon,
            Color = color,
            IsSystem = true,
            IsActive = true,
            StoreId = storeId
        };
        db.TransactionCategories.Add(category);
        await db.SaveChangesAsync(ct);
        return category;
    }
}
