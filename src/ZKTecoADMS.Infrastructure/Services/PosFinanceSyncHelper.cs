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
        if (payList == null || payList.Count == 0)
        {
            if (order.PaidAmount <= 0) return;
            payList = [new SalePaymentSync(order.PaidAmount, order.PaymentMethod, null)];
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

    public static async Task ReverseSaleOnCancelAsync(
        ZKTecoDbContext db,
        PosSaleOrder order,
        CancellationToken cancellationToken = default)
    {
        var prefix = $"{SaleMarker}{order.Id}";
        var cashList = await db.CashTransactions
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
        ZKTecoDbContext db, Guid storeId, string marker, CancellationToken ct) =>
        await db.CashTransactions
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive
                && c.InternalNote != null && c.InternalNote.Contains(marker))
            .OrderByDescending(c => c.CreatedAt)
            .FirstOrDefaultAsync(ct);

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
        var count = await db.CashTransactions
            .CountAsync(x => x.StoreId == storeId && x.TransactionCode.StartsWith($"{prefix}-{dateStr}"), ct) + 1;
        return $"{prefix}-{dateStr}-{count:D4}";
    }
}
