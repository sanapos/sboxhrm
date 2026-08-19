using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>
/// Đồng bộ phiếu thu/chi quỹ khi hoàn thành bán hàng, nhập hàng, trả hàng POS.
/// </summary>
public static class PosFinanceSyncHelper
{
    public const string SaleMarker = "pos bán hàng #";
    public const string ReservationDepositMarker = "pos cọc đặt chỗ #";
    public const string ReservationDepositRefundMarker = "pos hoàn cọc đặt chỗ #";
    public const string PurchaseReceiptMarker = "pos nhập hàng #";
    public const string SupplierPaymentMarker = "pos thanh toán ncc #";
    public const string CustomerReturnMarker = "pos trả khách #";
    public const string CustomerPaymentMarker = "pos thu nợ kh #";
    public const string PurchaseReturnRefundMarker = "pos thu trả ncc #";

    public static async Task SyncSaleOnCompleteAsync(
        ZKTecoDbContext db,
        PosSaleOrder order,
        Guid createdByUserId,
        IReadOnlyList<SalePaymentSync>? payments = null,
        CancellationToken cancellationToken = default)
    {
        if (order.Status != PosSaleOrderStatus.Completed)
            return;

        var payList = payments?
            .Where(p => p.Amount > 0)
            .ToList();
        if (payList == null)
        {
            // Không truyền danh sách TT → dùng PaidAmount (luồng cũ).
            if (order.PaidAmount <= 0) return;
            payList = [new SalePaymentSync(order.PaidAmount, order.PaymentMethod, null)];
        }
        else if (payList.Count == 0)
        {
            // Danh sách rỗng chủ đích: cọc đã thu quỹ, không phiếu bán hàng thêm.
            return;
        }

        var category = await EnsureCategoryAsync(
            db, order.StoreId, CashTransactionType.Income, "Bán hàng",
            "shopping_cart", "#22C55E", cancellationToken);
        if (category == null) return;

        for (var i = 0; i < payList.Count; i++)
        {
            var pay = payList[i];
            var marker = $"{SaleMarker}{order.Id}|{i}";
            if (await HasActiveCashAsync(db, order.StoreId, marker, cancellationToken))
                continue;

            var cash = new CashTransaction
            {
                Id = Guid.NewGuid(),
                TransactionCode = await GenerateCodeAsync(db, order.StoreId, CashTransactionType.Income, cancellationToken),
                Type = CashTransactionType.Income,
                CategoryId = category.Id,
                Amount = pay.Amount,
                TransactionDate = order.SaleDate ?? order.CreatedAt,
                Description = $"Bán hàng POS — {order.OrderNo}" +
                              (string.IsNullOrWhiteSpace(order.CustomerName) ? "" : $" — {order.CustomerName}") +
                              (payList.Count > 1 ? $" ({pay.PaymentMethod})" : ""),
                PaymentMethod = ParsePaymentMethod(pay.PaymentMethod),
                BankAccountId = pay.BankAccountId,
                Status = CashTransactionStatus.Completed,
                IsPaid = true,
                PaidDate = order.SaleDate ?? DateTime.UtcNow,
                ContactName = order.CustomerName,
                CreatedByUserId = createdByUserId,
                StoreId = order.StoreId,
                InternalNote = marker,
                IsActive = true,
                CreatedAt = DateTime.UtcNow,
            };
            db.CashTransactions.Add(cash);
        }
    }

    public record SalePaymentSync(decimal Amount, string PaymentMethod, Guid? BankAccountId);

    /// <summary>Trừ cọc đã thu quỹ khỏi danh sách TT (tránh phiếu thu bán hàng cộng trùng cọc).</summary>
    public static List<SalePaymentSync> SubtractAlreadyCashed(
        IReadOnlyList<SalePaymentSync> payments, decimal alreadyCashed)
    {
        if (alreadyCashed <= 0 || payments.Count == 0)
            return payments.ToList();
        var left = alreadyCashed;
        var result = new List<SalePaymentSync>(payments.Count);
        foreach (var p in payments)
        {
            if (left <= 0)
            {
                result.Add(p);
                continue;
            }
            if (p.Amount <= left)
            {
                left -= p.Amount;
                continue;
            }
            result.Add(p with { Amount = p.Amount - left });
            left = 0;
        }
        return result;
    }

    public static async Task SyncReservationDepositCollectedAsync(
        ZKTecoDbContext db,
        PosResourceReservation booking,
        decimal amount,
        Guid createdByUserId,
        Guid? bankAccountId = null,
        CancellationToken cancellationToken = default)
    {
        if (amount <= 0) return;
        var marker = $"{ReservationDepositMarker}{booking.Id}|{amount:0.##}|{DateTime.UtcNow.Ticks}";
        var category = await EnsureCategoryAsync(
            db, booking.StoreId, CashTransactionType.Income, "Cọc đặt chỗ",
            "payments", "#0F766E", cancellationToken);
        if (category == null) return;

        db.CashTransactions.Add(new CashTransaction
        {
            Id = Guid.NewGuid(),
            TransactionCode = await GenerateCodeAsync(db, booking.StoreId, CashTransactionType.Income, cancellationToken),
            Type = CashTransactionType.Income,
            CategoryId = category.Id,
            Amount = amount,
            TransactionDate = DateTime.UtcNow,
            Description = $"Thu cọc đặt chỗ — {booking.CustomerName}" +
                          (string.IsNullOrWhiteSpace(booking.Phone) ? "" : $" — {booking.Phone}"),
            PaymentMethod = ParsePaymentMethod(booking.DepositPaymentMethod),
            BankAccountId = bankAccountId,
            Status = CashTransactionStatus.Completed,
            IsPaid = true,
            PaidDate = DateTime.UtcNow,
            ContactName = booking.CustomerName,
            ContactPhone = booking.Phone,
            CreatedByUserId = createdByUserId,
            StoreId = booking.StoreId,
            InternalNote = marker,
            IsActive = true,
            CreatedAt = DateTime.UtcNow,
        });
    }

    public static async Task SyncReservationDepositRefundAsync(
        ZKTecoDbContext db,
        PosResourceReservation booking,
        Guid createdByUserId,
        CancellationToken cancellationToken = default)
    {
        if (booking.DepositPaid <= 0) return;
        var marker = $"{ReservationDepositRefundMarker}{booking.Id}";
        if (await HasActiveCashAsync(db, booking.StoreId, marker, cancellationToken))
            return;

        var category = await EnsureCategoryAsync(
            db, booking.StoreId, CashTransactionType.Expense, "Hoàn cọc đặt chỗ",
            "undo", "#DC2626", cancellationToken);
        if (category == null) return;

        var origPrefix = $"{ReservationDepositMarker}{booking.Id}";
        var orig = await db.CashTransactions.AsNoTracking()
            .Where(c => c.StoreId == booking.StoreId && c.Deleted == null && c.IsActive
                && c.Type == CashTransactionType.Income
                && c.InternalNote != null && c.InternalNote.StartsWith(origPrefix))
            .OrderByDescending(c => c.CreatedAt)
            .FirstOrDefaultAsync(cancellationToken);

        db.CashTransactions.Add(new CashTransaction
        {
            Id = Guid.NewGuid(),
            TransactionCode = await GenerateCodeAsync(db, booking.StoreId, CashTransactionType.Expense, cancellationToken),
            Type = CashTransactionType.Expense,
            CategoryId = category.Id,
            Amount = booking.DepositPaid,
            TransactionDate = DateTime.UtcNow,
            Description = $"Hoàn cọc đặt chỗ — {booking.CustomerName}",
            PaymentMethod = orig?.PaymentMethod ?? ParsePaymentMethod(booking.DepositPaymentMethod),
            BankAccountId = orig?.BankAccountId,
            Status = CashTransactionStatus.Completed,
            IsPaid = true,
            PaidDate = DateTime.UtcNow,
            ContactName = booking.CustomerName,
            ContactPhone = booking.Phone,
            CreatedByUserId = createdByUserId,
            StoreId = booking.StoreId,
            InternalNote = marker,
            IsActive = true,
            CreatedAt = DateTime.UtcNow,
        });
    }

    /// <summary>
    /// Mất cọc: không tạo phiếu thu mới (tiền đã vào quỹ lúc thu).
    /// Đổi danh mục phiếu cọc → «Mất cọc đặt chỗ» để sổ quỹ / cuối ngày nhận là thu nhập.
    /// </summary>
    public static async Task ReclassifyDepositOnForfeitAsync(
        ZKTecoDbContext db,
        PosResourceReservation booking,
        CancellationToken cancellationToken = default)
    {
        if (booking.DepositPaid <= 0) return;
        var prefix = $"{ReservationDepositMarker}{booking.Id}";
        var cashList = await db.CashTransactions
            .AsTracking()
            .Where(c => c.StoreId == booking.StoreId && c.Deleted == null && c.IsActive
                && c.Type == CashTransactionType.Income
                && c.InternalNote != null && c.InternalNote.StartsWith(prefix))
            .ToListAsync(cancellationToken);
        if (cashList.Count == 0) return;

        var category = await EnsureCategoryAsync(
            db, booking.StoreId, CashTransactionType.Income, "Mất cọc đặt chỗ",
            "gavel", "#B45309", cancellationToken);
        if (category == null) return;

        foreach (var cash in cashList)
        {
            cash.CategoryId = category.Id;
            cash.Description = $"Mất cọc đặt chỗ — {booking.CustomerName}";
        }
    }

    public static async Task ReverseSaleOnCancelAsync(
        ZKTecoDbContext db,
        PosSaleOrder order,
        CancellationToken cancellationToken = default)
    {
        var prefix = $"{SaleMarker}{order.Id}";
        // .AsTracking(): CancelLinkedCashTransaction ghi IsActive/Status lên cash rồi
        // SaveChangesAsync ở caller — thiếu tracking thì thu tiền bán hàng vẫn "active"
        // sau khi hủy đơn, làm sai số dư quỹ.
        var cashList = await db.CashTransactions
            .AsTracking()
            .Where(c => c.StoreId == order.StoreId && c.Deleted == null && c.IsActive
                && c.InternalNote != null && c.InternalNote.StartsWith(prefix))
            .ToListAsync(cancellationToken);
        foreach (var cash in cashList)
            PaymentFinanceHelper.CancelLinkedCashTransaction(cash, $"Hủy đơn {order.OrderNo}");
    }

    public static async Task SyncPurchaseReceiptPaymentAsync(
        ZKTecoDbContext db,
        PosStockReceipt receipt,
        Guid createdByUserId,
        CancellationToken cancellationToken = default)
    {
        if (receipt.Status != PosPurchaseReceiptStatus.Completed || receipt.PaidAmount <= 0)
            return;

        var marker = $"{PurchaseReceiptMarker}{receipt.Id}";
        if (await HasActiveCashAsync(db, receipt.StoreId, marker, cancellationToken))
            return;

        var category = await EnsureCategoryAsync(
            db, receipt.StoreId, CashTransactionType.Expense, "Nhập hàng",
            "inventory", "#EF4444", cancellationToken);
        if (category == null) return;

        var cash = new CashTransaction
        {
            Id = Guid.NewGuid(),
            TransactionCode = await GenerateCodeAsync(db, receipt.StoreId, CashTransactionType.Expense, cancellationToken),
            Type = CashTransactionType.Expense,
            CategoryId = category.Id,
            Amount = receipt.PaidAmount,
            TransactionDate = receipt.ImportDate ?? receipt.CreatedAt,
            Description = $"Thanh toán nhập hàng — {receipt.ReceiptNo}",
            PaymentMethod = PaymentMethodType.Cash,
            Status = CashTransactionStatus.Completed,
            IsPaid = true,
            PaidDate = receipt.ImportDate ?? DateTime.UtcNow,
            CreatedByUserId = createdByUserId,
            StoreId = receipt.StoreId,
            InternalNote = marker,
            IsActive = true,
            CreatedAt = DateTime.UtcNow,
        };
        db.CashTransactions.Add(cash);
    }

    public static async Task SyncSupplierPaymentAsync(
        ZKTecoDbContext db,
        PosSupplierPayment payment,
        PosStockReceipt receipt,
        Guid createdByUserId,
        CancellationToken cancellationToken = default)
    {
        if (payment.Amount <= 0) return;

        var marker = $"{SupplierPaymentMarker}{payment.Id}";
        if (await HasActiveCashAsync(db, payment.StoreId, marker, cancellationToken))
            return;

        var category = await EnsureCategoryAsync(
            db, payment.StoreId, CashTransactionType.Expense, "Nhập hàng",
            "inventory", "#EF4444", cancellationToken);
        if (category == null) return;

        var cash = new CashTransaction
        {
            Id = Guid.NewGuid(),
            TransactionCode = await GenerateCodeAsync(db, payment.StoreId, CashTransactionType.Expense, cancellationToken),
            Type = CashTransactionType.Expense,
            CategoryId = category.Id,
            Amount = payment.Amount,
            TransactionDate = payment.PaidAt,
            Description = $"Thanh toán NCC — {receipt.ReceiptNo} ({payment.PaymentNo})",
            PaymentMethod = ParsePaymentMethod(payment.PaymentMethod),
            Status = CashTransactionStatus.Completed,
            IsPaid = true,
            PaidDate = payment.PaidAt,
            CreatedByUserId = createdByUserId,
            StoreId = payment.StoreId,
            InternalNote = marker,
            IsActive = true,
            CreatedAt = DateTime.UtcNow,
        };
        db.CashTransactions.Add(cash);
    }

    public static async Task SyncCustomerReturnAsync(
        ZKTecoDbContext db,
        PosSaleOrder order,
        string returnNo,
        decimal refundAmount,
        string? paymentMethod,
        Guid createdByUserId,
        CancellationToken cancellationToken = default)
    {
        if (refundAmount <= 0) return;

        var marker = $"{CustomerReturnMarker}{order.Id}|{returnNo}";
        if (await HasActiveCashAsync(db, order.StoreId, marker, cancellationToken))
            return;

        var category = await EnsureCategoryAsync(
            db, order.StoreId, CashTransactionType.Expense, "Trả hàng khách",
            "undo", "#F59E0B", cancellationToken);
        if (category == null) return;

        var cash = new CashTransaction
        {
            Id = Guid.NewGuid(),
            TransactionCode = await GenerateCodeAsync(db, order.StoreId, CashTransactionType.Expense, cancellationToken),
            Type = CashTransactionType.Expense,
            CategoryId = category.Id,
            Amount = refundAmount,
            TransactionDate = DateTime.UtcNow,
            Description = $"Hoàn tiền trả hàng — {order.OrderNo} ({returnNo})",
            PaymentMethod = ParsePaymentMethod(paymentMethod ?? order.PaymentMethod),
            Status = CashTransactionStatus.Completed,
            IsPaid = true,
            PaidDate = DateTime.UtcNow,
            ContactName = order.CustomerName,
            CreatedByUserId = createdByUserId,
            StoreId = order.StoreId,
            InternalNote = marker,
            IsActive = true,
            CreatedAt = DateTime.UtcNow,
        };
        db.CashTransactions.Add(cash);
    }

    public static async Task ReverseCustomerReturnAsync(
        ZKTecoDbContext db,
        PosSaleOrder order,
        string returnNo,
        CancellationToken cancellationToken = default)
    {
        var marker = $"{CustomerReturnMarker}{order.Id}|{returnNo}";
        var cashList = await db.CashTransactions
            .AsTracking()
            .Where(c => c.StoreId == order.StoreId && c.Deleted == null && c.IsActive
                && c.InternalNote != null && c.InternalNote.StartsWith(marker))
            .ToListAsync(cancellationToken);
        foreach (var cash in cashList)
            PaymentFinanceHelper.CancelLinkedCashTransaction(cash, $"Hủy trả hàng {returnNo} — {order.OrderNo}");
    }

    public static async Task SyncCustomerPaymentAsync(
        ZKTecoDbContext db,
        PosCustomerPayment payment,
        PosCustomer customer,
        Guid createdByUserId,
        Guid? bankAccountId = null,
        CancellationToken cancellationToken = default)
    {
        if (payment.Amount <= 0) return;

        var marker = $"{CustomerPaymentMarker}{payment.Id}";
        if (await HasActiveCashAsync(db, payment.StoreId, marker, cancellationToken))
            return;

        var category = await EnsureCategoryAsync(
            db, payment.StoreId, CashTransactionType.Income, "Thu nợ khách",
            "account_balance_wallet", "#0EA5E9", cancellationToken);
        if (category == null) return;

        var cash = new CashTransaction
        {
            Id = Guid.NewGuid(),
            TransactionCode = await GenerateCodeAsync(db, payment.StoreId, CashTransactionType.Income, cancellationToken),
            Type = CashTransactionType.Income,
            CategoryId = category.Id,
            Amount = payment.Amount,
            TransactionDate = payment.PaidAt,
            Description = $"Thu nợ khách — {customer.Name} ({payment.PaymentNo})",
            PaymentMethod = ParsePaymentMethod(payment.PaymentMethod),
            BankAccountId = bankAccountId,
            Status = CashTransactionStatus.Completed,
            IsPaid = true,
            PaidDate = payment.PaidAt,
            ContactName = customer.Name,
            CreatedByUserId = createdByUserId,
            StoreId = payment.StoreId,
            InternalNote = marker,
            IsActive = true,
            CreatedAt = DateTime.UtcNow,
        };
        db.CashTransactions.Add(cash);
    }

    public static async Task SyncPurchaseReturnRefundAsync(
        ZKTecoDbContext db,
        PosPurchaseReturn ret,
        Guid createdByUserId,
        CancellationToken cancellationToken = default)
    {
        if (ret.Status != PosPurchaseReturnStatus.Completed || ret.RefundReceived <= 0)
            return;

        var marker = $"{PurchaseReturnRefundMarker}{ret.Id}";
        if (await HasActiveCashAsync(db, ret.StoreId, marker, cancellationToken))
            return;

        var category = await EnsureCategoryAsync(
            db, ret.StoreId, CashTransactionType.Income, "Thu trả hàng NCC",
            "reply", "#3B82F6", cancellationToken);
        if (category == null) return;

        var cash = new CashTransaction
        {
            Id = Guid.NewGuid(),
            TransactionCode = await GenerateCodeAsync(db, ret.StoreId, CashTransactionType.Income, cancellationToken),
            Type = CashTransactionType.Income,
            CategoryId = category.Id,
            Amount = ret.RefundReceived,
            TransactionDate = ret.ReturnDate ?? ret.CreatedAt,
            Description = $"NCC hoàn tiền trả hàng — {ret.ReturnNo}",
            PaymentMethod = PaymentMethodType.Cash,
            Status = CashTransactionStatus.Completed,
            IsPaid = true,
            PaidDate = ret.ReturnDate ?? DateTime.UtcNow,
            CreatedByUserId = createdByUserId,
            StoreId = ret.StoreId,
            InternalNote = marker,
            IsActive = true,
            CreatedAt = DateTime.UtcNow,
        };
        db.CashTransactions.Add(cash);
    }

    public static PaymentMethodType ParsePaymentMethod(string? method)
    {
        if (string.IsNullOrWhiteSpace(method)) return PaymentMethodType.Cash;
        var m = method.Trim().ToLowerInvariant();
        if (m.Contains("chuyển") || m.Contains("chuyen") || m.Contains("transfer"))
            return PaymentMethodType.BankTransfer;
        if (m.Contains("thẻ") || m.Contains("the ") || m.Contains("card"))
            return PaymentMethodType.Card;
        if (m.Contains("qr")) return PaymentMethodType.VietQR;
        if (m.Contains("ví") || m.Contains("vi ") || m.Contains("wallet"))
            return PaymentMethodType.EWallet;
        return PaymentMethodType.Cash;
    }

    private static async Task<bool> HasActiveCashAsync(
        ZKTecoDbContext db, Guid storeId, string marker, CancellationToken ct) =>
        await FindActiveCashAsync(db, storeId, marker, ct) != null;

    private static async Task<CashTransaction?> FindActiveCashAsync(
        ZKTecoDbContext db, Guid storeId, string marker, CancellationToken ct)
    {
        // Exact match trước; fallback prefix (marker + "|..." hoặc ghi chú hủy nối thêm).
        var exact = await db.CashTransactions
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive
                && c.InternalNote == marker)
            .OrderByDescending(c => c.CreatedAt)
            .FirstOrDefaultAsync(ct);
        if (exact != null) return exact;

        return await db.CashTransactions
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive
                && c.InternalNote != null
                && (c.InternalNote.StartsWith(marker + "|")
                    || c.InternalNote.StartsWith(marker + " ")
                    || c.InternalNote.StartsWith(marker + "\n")))
            .OrderByDescending(c => c.CreatedAt)
            .FirstOrDefaultAsync(ct);
    }

    private static async Task<TransactionCategory?> EnsureCategoryAsync(
        ZKTecoDbContext db,
        Guid storeId,
        CashTransactionType type,
        string name,
        string icon,
        string color,
        CancellationToken ct)
    {
        var categories = await db.TransactionCategories
            .Where(c => c.IsActive && c.StoreId == storeId && c.Type == type)
            .ToListAsync(ct);

        var existing = categories.FirstOrDefault(c =>
            c.Name == name || VietnameseEncodingFix.TryFix(c.Name) == name);
        if (existing != null) return existing;

        var category = new TransactionCategory
        {
            Id = Guid.NewGuid(),
            Name = name,
            Description = $"Tự động từ POS — {name}",
            Type = type,
            Icon = icon,
            Color = color,
            IsSystem = true,
            IsActive = true,
            StoreId = storeId,
            CreatedAt = DateTime.UtcNow,
        };
        db.TransactionCategories.Add(category);
        return category;
    }

    private static async Task<string> GenerateCodeAsync(
        ZKTecoDbContext db, Guid storeId, CashTransactionType type, CancellationToken ct)
    {
        var prefix = type == CashTransactionType.Income ? "TH" : "CH";
        var dateStr = DateTime.UtcNow.ToString("yyyyMMdd");
        var fullPrefix = $"{prefix}-{dateStr}";
        var dbCount = await db.CashTransactions
            .CountAsync(x => x.StoreId == storeId && x.TransactionCode.StartsWith(fullPrefix), ct);
        // Đơn bán chia nhiều hình thức thanh toán gọi hàm này nhiều lần LIÊN TIẾP trong cùng 1
        // request, TRƯỚC khi SaveChanges — phải cộng cả các CashTransaction vừa Add (chưa lưu)
        // để mỗi payment nhận mã khác nhau, tránh trùng mã chắc chắn ngay trong 1 batch.
        var pendingCount = db.ChangeTracker.Entries<CashTransaction>()
            .Count(e => e.State == Microsoft.EntityFrameworkCore.EntityState.Added
                && e.Entity.StoreId == storeId
                && e.Entity.TransactionCode.StartsWith(fullPrefix));
        var next = dbCount + pendingCount + 1;
        return $"{fullPrefix}-{next:D4}";
    }

    /// <summary>
    /// GenerateCodeAsync đếm rồi +1 (không lock) — 2 request cùng store tạo phiếu thu/chi gần
    /// như đồng thời (rất thường gặp khi nhiều máy POS bán hàng cùng lúc) có thể tính ra cùng mã,
    /// SaveChangesAsync ném DbUpdateException do trùng unique (StoreId, TransactionCode). Gọi hàm
    /// này trong catch để cấp lại mã mới cho mọi CashTransaction vừa Add trong batch rồi retry.
    /// </summary>
    public static async Task RegenerateDuplicateCodesAsync(
        ZKTecoDbContext db, Guid storeId, CancellationToken ct = default)
    {
        var pending = db.ChangeTracker.Entries<CashTransaction>()
            .Where(e => e.State == Microsoft.EntityFrameworkCore.EntityState.Added &&
                        e.Entity.StoreId == storeId)
            .Select(e => e.Entity)
            .ToList();
        if (pending.Count == 0) return;

        var dateStr = DateTime.UtcNow.ToString("yyyyMMdd");
        foreach (var group in pending.GroupBy(c => c.Type))
        {
            var prefix = group.Key == CashTransactionType.Income ? "TH" : "CH";
            var existingCodes = (await db.CashTransactions
                .Where(x => x.StoreId == storeId && x.TransactionCode.StartsWith($"{prefix}-{dateStr}"))
                .Select(x => x.TransactionCode)
                .ToListAsync(ct)).ToHashSet();

            var next = existingCodes.Count + 1;
            foreach (var cash in group)
            {
                string candidate;
                do
                {
                    candidate = $"{prefix}-{dateStr}-{next:D4}";
                    next++;
                } while (!existingCodes.Add(candidate));
                cash.TransactionCode = candidate;
            }
        }
    }
}
