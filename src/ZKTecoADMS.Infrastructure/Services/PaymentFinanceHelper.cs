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

    public const string CashDisbursementMethod = "Cash";

    // ─── Liên kết chuẩn phiếu thu/chi ↔ chứng từ gốc (SourceType/SourceId) ───
    public const string SourceAdvance = "advance";
    public const string SourceReward = "reward";
    public const string SourcePenaltyTicket = "penalty_ticket";
    public const string SourceTripAdvance = "trip_advance";
    public const string SourceTripSettlement = "trip_settlement";
    public const string SourceTripRefund = "trip_refund";

    private static readonly (string Prefix, string Type)[] MarkerPrefixes =
    {
        ("Tự động tạo từ yêu cầu ứng lương #", SourceAdvance),
        ("Tự động tạo từ phiếu thưởng/phạt #", SourceReward),
        ("Tự động tạo từ ứng công tác #", SourceTripAdvance),
        ("Tự động tạo từ quyết toán công tác phí #", SourceTripSettlement),
        ("Tự động tạo từ thu hoàn ứng công tác #", SourceTripRefund),
    };

    /// <summary>Suy ra (SourceType, SourceId) từ chuỗi đánh dấu cũ trong InternalNote.</summary>
    public static (string Type, Guid Id)? SourceFromMarker(string marker)
    {
        foreach (var (prefix, type) in MarkerPrefixes)
        {
            if (marker.StartsWith(prefix, StringComparison.Ordinal)
                && Guid.TryParse(marker.AsSpan(prefix.Length), out var id))
                return (type, id);
        }
        return null;
    }

    /// <summary>Gắn nguồn chứng từ + nhân viên vào phiếu thu/chi vừa tạo.</summary>
    public static void StampSource(CashTransaction cash, string sourceType, Guid sourceId, Guid? employeeId)
    {
        cash.SourceType = sourceType;
        cash.SourceId = sourceId;
        cash.EmployeeId ??= employeeId;
    }

    public static void StampSource(CashTransaction cash, string marker, Guid? employeeId)
    {
        var src = SourceFromMarker(marker);
        if (src != null) StampSource(cash, src.Value.Type, src.Value.Id, employeeId);
        else cash.EmployeeId ??= employeeId;
    }

    public static bool IsSalaryDisbursement(PaymentTransaction tx)
        => string.Equals(tx.PaymentMethod, SalaryDisbursementMethod, StringComparison.OrdinalIgnoreCase);

    /// <summary>salary / cash — cách xử lý tiền của phiếu thưởng/phạt khi duyệt.</summary>
    public static string ResolveSettlement(PaymentTransaction tx, string? disbursementMode, HrFinanceSettings? settings)
    {
        var mode = disbursementMode ?? tx.Settlement;
        if (string.IsNullOrWhiteSpace(mode))
            mode = tx.Type == "Penalty"
                ? settings?.PenaltyDefaultSettlement ?? "salary"
                : settings?.BonusDefaultSettlement ?? "salary";
        return mode.Trim().ToLowerInvariant() == "cash" ? "cash" : "salary";
    }

    /// <summary>
    /// Duyệt thưởng/phạt — MỘT nơi xử lý tiền duy nhất để không bị tính 2 lần:
    /// • salary → PaymentMethod=Salary, bảng lương cộng/trừ, KHÔNG tạo phiếu thu/chi.
    /// • cash   → PaymentMethod=Cash (bảng lương bỏ qua) + tạo phiếu chi/thu chờ thanh toán.
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

        var settings = await HrFinanceSettingsHelper.GetAsync(db, storeId, cancellationToken);
        var settlement = ResolveSettlement(tx, disbursementMode, settings);
        var tracked = db.Entry(tx).State != EntityState.Detached;
        tx.Settlement = settlement;

        if (settlement == "salary")
        {
            tx.PaymentMethod = SalaryDisbursementMethod;
            await PersistTxAsync(db, tx, tracked, cancellationToken);
            return null;
        }

        // Tiền mặt: đánh dấu ngay để bảng lương bỏ qua (tránh vừa trả tiền mặt vừa cộng lương)
        if (!string.Equals(tx.PaymentMethod, CashDisbursementMethod, StringComparison.OrdinalIgnoreCase)
            && !string.Equals(tx.PaymentMethod, "Transfer", StringComparison.OrdinalIgnoreCase)
            && !string.Equals(tx.PaymentMethod, "BankTransfer", StringComparison.OrdinalIgnoreCase))
            tx.PaymentMethod = CashDisbursementMethod;
        await PersistTxAsync(db, tx, tracked, cancellationToken);

        var cash = await CreateBonusPenaltyPendingOnApproveAsync(
            db, tx, storeId, createdByUserId, cancellationToken);
        if (cash != null && tx.CashTransactionId != cash.Id)
        {
            tx.CashTransactionId = cash.Id;
            await PersistTxAsync(db, tx, tracked, cancellationToken);
        }
        return cash;
    }

    private static async Task PersistTxAsync(ZKTecoDbContext db, PaymentTransaction tx, bool tracked, CancellationToken ct)
    {
        if (!tracked) db.PaymentTransactions.Update(tx);
        await db.SaveChangesAsync(ct);
    }

    /// <summary>Hoàn duyệt / hủy: bỏ đánh dấu cách chi (chỉ khi phiếu thu/chi chưa thanh toán).</summary>
    public static void ClearSalaryDisbursementOnUnapprove(PaymentTransaction tx, CashTransaction? linked = null)
    {
        if (linked != null && linked.IsPaid) return;
        if (IsSalaryDisbursement(tx)
            || string.Equals(tx.PaymentMethod, CashDisbursementMethod, StringComparison.OrdinalIgnoreCase))
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
        var src = SourceFromMarker(marker);
        if (src != null)
        {
            var (type, id) = src.Value;
            var bySource = await db.CashTransactions
                .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive
                    && c.SourceType == type && c.SourceId == id)
                .OrderByDescending(c => c.CreatedAt)
                .FirstOrDefaultAsync(cancellationToken);
            if (bySource != null) return bySource;
        }

        // Dữ liệu cũ chưa có SourceId → tìm theo chuỗi đánh dấu trong ghi chú
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
        StampSource(cashTx, SourceReward, tx.Id, tx.EmployeeId);

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
        // Dùng số tiền thực tế đã duyệt (có thể thấp hơn số tiền yêu cầu ban
        // đầu) — fallback về Amount cho các yêu cầu cũ trước khi có trường
        // ApprovedAmount.
        var payoutAmount = advance.ApprovedAmount ?? advance.Amount;
        var cashTx = new CashTransaction
        {
            Id = Guid.NewGuid(),
            TransactionCode = transactionCode,
            Type = CashTransactionType.Expense,
            CategoryId = category.Id,
            Amount = payoutAmount,
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
        StampSource(cashTx, SourceAdvance, advance.Id, advance.EmployeeId);

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
