using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>Một lần trả lương: phần tiền mặt + phần chuyển khoản (từ tài khoản của cửa hàng).</summary>
public sealed record PayslipPayRequest(
    Guid PayslipId,
    decimal CashAmount,
    decimal BankAmount,
    Guid? BankAccountId,
    string? Reference,
    DateTime? PaidAt);

/// <summary>
/// Trả lương theo phiếu lương. Mỗi phương thức là một phiếu chi riêng (cùng gắn phiếu lương) để số dư quỹ
/// tiền mặt / từng tài khoản ngân hàng luôn đúng. Phiếu lương «Đã trả» khi tổng phiếu chi hoàn thành ≥ thực lĩnh.
/// </summary>
public static class PayslipPayments
{
    public const string SourceType = "payslip";

    public static IQueryable<CashTransaction> LinkedVouchers(ZKTecoDbContext db, Payslip p)
    {
        var marker = PayslipCashTransactionHelper.BuildInternalNote(p.Id);
        var cashId = p.CashTransactionId;
        return db.CashTransactions.AsTracking().Where(c =>
            c.StoreId == p.StoreId && c.IsActive && c.Deleted == null && c.Type == CashTransactionType.Expense &&
            ((c.SourceType == SourceType && c.SourceId == p.Id) ||
             (cashId != null && c.Id == cashId) ||
             (c.InternalNote != null && c.InternalNote.Contains(marker))));
    }

    public static string EmployeeName(Employee? e) =>
        e == null ? "Nhân viên" : $"{e.LastName} {e.FirstName}".Trim() is { Length: > 0 } n ? n : e.EmployeeCode;

    private static string NewCode(DateTime now) => $"CH-{now:yyyyMMdd}-{Guid.NewGuid().ToString()[..4].ToUpperInvariant()}";

    private static async Task<TransactionCategory> SalaryCategoryAsync(ZKTecoDbContext db, Guid storeId, CancellationToken ct)
    {
        var cat = await db.TransactionCategories.AsTracking().FirstOrDefaultAsync(
            c => c.Name == "Chi lương" && c.Type == CashTransactionType.Expense && c.StoreId == storeId, ct);
        if (cat != null) return cat;
        cat = new TransactionCategory
        {
            Id = Guid.NewGuid(),
            Name = "Chi lương",
            Description = "Chi trả lương nhân viên",
            Type = CashTransactionType.Expense,
            Icon = "payments",
            Color = "#059669",
            IsSystem = true,
            StoreId = storeId,
        };
        db.TransactionCategories.Add(cat);
        return cat;
    }

    /// <summary>
    /// Tính lại số đã trả / trạng thái phiếu lương. <paramref name="ensurePending"/>: còn thiếu mà không có phiếu chi chờ
    /// thì tạo mới (chốt lương, trả một phần, chốt lại tăng lương). Không lưu — người gọi SaveChanges.
    /// </summary>
    public static async Task<PayslipPaymentState> RecomputeAsync(ZKTecoDbContext db, Payslip p, Guid userId, bool ensurePending,
        CancellationToken ct = default)
    {
        var storeId = p.StoreId ?? Guid.Empty;
        var vouchers = await LinkedVouchers(db, p).OrderBy(c => c.CreatedAt).ToListAsync(ct);
        foreach (var v in vouchers.Where(v => v.SourceId == null))
        {
            v.SourceType = SourceType;
            v.SourceId = p.Id;
        }

        var paidRows = vouchers.Where(v => v.IsPaid && v.Status == CashTransactionStatus.Completed).ToList();
        var paid = paidRows.Sum(v => v.Amount);
        var remaining = Math.Max(0, p.NetSalary - paid);
        var pending = vouchers.Where(v => !v.IsPaid && v.Status != CashTransactionStatus.Cancelled).ToList();
        var employee = p.Employee ?? await db.Employees.AsNoTracking().FirstOrDefaultAsync(e => e.Id == p.EmployeeId, ct);
        var name = EmployeeName(employee);
        var label = $"Chi lương T{p.Month:D2}/{p.Year} - {name}{(paid > 0 ? " (còn lại)" : "")}";

        CashTransaction? open = null;
        if (remaining > 0 && p.Status != PayslipStatus.Cancelled)
        {
            open = pending.FirstOrDefault();
            if (open != null)
            {
                open.Amount = remaining;
                open.Description = label;
                open.ContactName = name;
                open.BranchId ??= employee?.BranchId;
                open.UpdatedAt = DateTime.UtcNow;
                foreach (var extra in pending.Skip(1)) extra.Status = CashTransactionStatus.Cancelled;
            }
            else if (ensurePending && storeId != Guid.Empty)
            {
                var now = DateTime.UtcNow;
                var cat = await SalaryCategoryAsync(db, storeId, ct);
                open = new CashTransaction
                {
                    Id = Guid.NewGuid(),
                    TransactionCode = NewCode(now),
                    Type = CashTransactionType.Expense,
                    CategoryId = cat.Id,
                    Amount = remaining,
                    TransactionDate = VnTimeHelper.UtcToVn(now), // phiếu thu chi lưu giờ VN
                    Description = label,
                    PaymentMethod = PaymentMethodType.Cash,
                    Status = CashTransactionStatus.Pending,
                    ContactName = name,
                    CreatedByUserId = userId,
                    IsPaid = false,
                    InternalNote = PayslipCashTransactionHelper.BuildInternalNote(p.Id),
                    SourceType = SourceType,
                    SourceId = p.Id,
                    EmployeeId = p.EmployeeId,
                    BranchId = employee?.BranchId,
                    IsActive = true,
                    StoreId = storeId,
                };
                db.CashTransactions.Add(open);
            }
        }
        else
        {
            // Đã trả đủ (hoặc phiếu hủy) → phiếu chi chờ thừa thì hủy, tránh chi trùng.
            foreach (var v in pending) v.Status = CashTransactionStatus.Cancelled;
        }

        p.PaidAmount = paid;
        if (p.Status != PayslipStatus.Cancelled)
        {
            if (p.NetSalary > 0 && paid >= p.NetSalary)
            {
                p.Status = PayslipStatus.Paid;
                p.PaidDate = paidRows.Max(v => v.PaidDate) ?? DateTime.UtcNow;
            }
            else if (p.Status == PayslipStatus.Paid)
            {
                p.Status = PayslipStatus.Approved;
                p.PaidDate = null;
            }
        }
        p.CashTransactionId = open?.Id ?? paidRows.LastOrDefault()?.Id;
        p.UpdatedAt = DateTime.UtcNow;
        return new PayslipPaymentState(p.NetSalary, paid, remaining, p.Status);
    }

    /// <summary>Ghi nhận một lần trả lương. Trả về lỗi (null = thành công).</summary>
    public static async Task<string?> PayAsync(ZKTecoDbContext db, ISystemNotificationService notifications, Guid storeId, Guid userId,
        PayslipPayRequest r, CancellationToken ct = default)
    {
        var p = await db.Payslips.AsTracking().Include(x => x.Employee)
            .FirstOrDefaultAsync(x => x.Id == r.PayslipId && x.StoreId == storeId, ct);
        if (p == null) return "Không tìm thấy phiếu lương";
        var name = EmployeeName(p.Employee);
        if (p.Status == PayslipStatus.Cancelled) return $"{name}: phiếu lương đã hủy";
        if (r.CashAmount < 0 || r.BankAmount < 0) return $"{name}: số tiền không hợp lệ";
        var total = r.CashAmount + r.BankAmount;
        if (total <= 0) return $"{name}: chưa nhập số tiền trả";

        var state = await RecomputeAsync(db, p, userId, ensurePending: true, ct);
        if (state.Remaining <= 0) return $"{name}: đã trả đủ lương kỳ này";
        if (total > state.Remaining + 0.5m) return $"{name}: trả {total:N0}đ vượt số còn lại {state.Remaining:N0}đ";

        BankAccount? bank = null;
        if (r.BankAmount > 0)
        {
            if (r.BankAccountId == null) return "Chọn tài khoản ngân hàng chi lương";
            bank = await db.BankAccounts.AsNoTracking().FirstOrDefaultAsync(b => b.Id == r.BankAccountId && b.StoreId == storeId && b.IsActive, ct);
            if (bank == null) return "Tài khoản ngân hàng chi lương không hợp lệ";
        }
        await db.SaveChangesAsync(ct); // phiếu chi chờ (nếu vừa tạo) có mã trước khi tách

        var paidAt = r.PaidAt ?? DateTime.UtcNow;
        var pending = await LinkedVouchers(db, p)
            .Where(c => !c.IsPaid && c.Status != CashTransactionStatus.Cancelled)
            .OrderBy(c => c.CreatedAt).FirstOrDefaultAsync(ct);
        var parts = new List<(decimal Amount, PaymentMethodType Method)>();
        if (r.CashAmount > 0) parts.Add((r.CashAmount, PaymentMethodType.Cash));
        if (r.BankAmount > 0) parts.Add((r.BankAmount, PaymentMethodType.BankTransfer));
        var month = $"T{p.Month:D2}/{p.Year}";
        var categoryId = pending?.CategoryId ?? (await SalaryCategoryAsync(db, storeId, ct)).Id;

        foreach (var (amount, method) in parts)
        {
            var v = pending;
            pending = null;
            if (v == null)
            {
                v = new CashTransaction
                {
                    Id = Guid.NewGuid(),
                    TransactionCode = NewCode(paidAt),
                    Type = CashTransactionType.Expense,
                    CategoryId = categoryId,
                    CreatedByUserId = userId,
                    InternalNote = PayslipCashTransactionHelper.BuildInternalNote(p.Id),
                    SourceType = SourceType,
                    SourceId = p.Id,
                    EmployeeId = p.EmployeeId,
                    IsActive = true,
                    StoreId = storeId,
                };
                db.CashTransactions.Add(v);
            }
            v.Amount = amount;
            v.PaymentMethod = method;
            v.BankAccountId = method == PaymentMethodType.BankTransfer ? bank!.Id : null;
            v.Description = $"Chi lương {month} - {name} ({(method == PaymentMethodType.Cash ? "tiền mặt" : "chuyển khoản")})";
            v.ContactName = name;
            v.BranchId ??= p.Employee?.BranchId;
            v.PaymentReference = method == PaymentMethodType.BankTransfer ? r.Reference : null;
            v.TransactionDate = VnTimeHelper.UtcToVn(paidAt); // phiếu thu chi lưu giờ VN
            v.Status = CashTransactionStatus.Completed;
            v.IsPaid = true;
            v.PaidDate = paidAt;
            v.UpdatedAt = DateTime.UtcNow;
        }
        await db.SaveChangesAsync(ct);

        var after = await RecomputeAsync(db, p, userId, ensurePending: true, ct);
        await db.SaveChangesAsync(ct);

        var uid = p.EmployeeUserId ?? p.Employee?.ApplicationUserId;
        if (uid.HasValue && uid != userId)
        {
            var how = string.Join(", ", parts.Select(x => $"{(x.Method == PaymentMethodType.Cash ? "tiền mặt" : "chuyển khoản")} {x.Amount:N0}đ"));
            try
            {
                await notifications.CreateAndSendAsync(uid.Value, NotificationType.Success,
                    after.Remaining <= 0 ? "Lương đã thanh toán" : "Đã trả một phần lương",
                    after.Remaining <= 0
                        ? $"Lương kỳ {month} ({p.NetSalary:N0}đ) đã thanh toán đủ — {how}."
                        : $"Lương kỳ {month}: đã nhận {how}. Còn lại {after.Remaining:N0}đ.",
                    relatedEntityType: "Payslip", relatedEntityId: p.Id, fromUserId: userId,
                    categoryCode: "payroll", storeId: storeId);
            }
            catch { /* thông báo lỗi không chặn trả lương */ }
        }
        return null;
    }

    /// <summary>Phiếu chi đổi trạng thái / bị xóa ở màn Thu chi → cập nhật phiếu lương liên kết.</summary>
    public static async Task<(Payslip? Payslip, bool BecamePaid)> SyncForVoucherAsync(ZKTecoDbContext db, CashTransaction cash, Guid storeId,
        Guid userId, bool ensurePending, CancellationToken ct = default)
    {
        Payslip? p = null;
        if (cash.SourceType == SourceType && cash.SourceId is Guid sid)
            p = await db.Payslips.AsTracking().Include(x => x.Employee).FirstOrDefaultAsync(x => x.Id == sid && x.StoreId == storeId, ct);
        p ??= await db.Payslips.AsTracking().Include(x => x.Employee)
            .FirstOrDefaultAsync(x => x.CashTransactionId == cash.Id && x.StoreId == storeId, ct);
        if (p == null && CashTransactionLinkageHelper.TryExtractTrailingGuid(cash.InternalNote, PayslipCashTransactionHelper.InternalNoteMarker, out var pid))
            p = await db.Payslips.AsTracking().Include(x => x.Employee).FirstOrDefaultAsync(x => x.Id == pid && x.StoreId == storeId, ct);
        if (p == null) return (null, false);
        var wasPaid = p.Status == PayslipStatus.Paid;
        await RecomputeAsync(db, p, userId, ensurePending, ct);
        await db.SaveChangesAsync(ct);
        return (p, !wasPaid && p.Status == PayslipStatus.Paid);
    }
}

public sealed class PayslipPaymentService(ZKTecoDbContext db) : IPayslipPaymentService
{
    public async Task<PayslipPaymentState?> SyncAsync(Guid payslipId, Guid storeId, Guid userId, bool ensurePending,
        CancellationToken cancellationToken = default)
    {
        var p = await db.Payslips.AsTracking().Include(x => x.Employee)
            .FirstOrDefaultAsync(x => x.Id == payslipId && x.StoreId == storeId, cancellationToken);
        if (p == null) return null;
        var state = await PayslipPayments.RecomputeAsync(db, p, userId, ensurePending, cancellationToken);
        await db.SaveChangesAsync(cancellationToken);
        return state;
    }
}
