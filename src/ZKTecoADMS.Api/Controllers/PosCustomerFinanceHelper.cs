using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

public static class PosCustomerFinanceHelper
{
    /// <summary>1 điểm / 10.000đ doanh thu.</summary>
    public const decimal PointsPerAmount = 10_000m;

    /// <summary>1 điểm = 100đ giảm giá.</summary>
    public const decimal PointRedeemValue = 100m;

    public record VoucherApplyResult(PosVoucher Voucher, decimal DiscountAmount, string? Error);

    public static async Task<VoucherApplyResult?> TryApplyVoucherAsync(
        ZKTecoDbContext db,
        Guid storeId,
        string? code,
        decimal orderAmountBeforeVoucher,
        Guid? customerId)
    {
        if (string.IsNullOrWhiteSpace(code)) return null;
        var normalized = code.Trim().ToUpperInvariant();
        var voucher = await db.PosVouchers.AsTracking()
            .FirstOrDefaultAsync(v => v.StoreId == storeId && v.Deleted == null && v.IsActive &&
                                      v.Code.ToUpper() == normalized);
        if (voucher == null)
            return new VoucherApplyResult(null!, 0, "Mã voucher không hợp lệ");

        var now = DateTime.UtcNow;
        if (voucher.ValidFrom.HasValue && now < voucher.ValidFrom.Value)
            return new VoucherApplyResult(voucher, 0, "Voucher chưa có hiệu lực");
        if (voucher.ValidTo.HasValue && now > voucher.ValidTo.Value)
            return new VoucherApplyResult(voucher, 0, "Voucher đã hết hạn");
        if (voucher.MaxUses.HasValue && voucher.UsedCount >= voucher.MaxUses.Value)
            return new VoucherApplyResult(voucher, 0, "Voucher đã hết lượt dùng");
        if (voucher.CustomerId.HasValue && voucher.CustomerId != customerId)
            return new VoucherApplyResult(voucher, 0, "Voucher không áp dụng cho khách này");
        if (orderAmountBeforeVoucher < voucher.MinOrderAmount)
            return new VoucherApplyResult(voucher, 0,
                $"Đơn tối thiểu {_fmt(voucher.MinOrderAmount)} để dùng voucher");

        decimal discount = voucher.DiscountType == PosVoucherDiscountType.Percent
            ? Math.Round(orderAmountBeforeVoucher * voucher.DiscountValue / 100m, 0)
            : voucher.DiscountValue;
        if (voucher.MaxDiscountAmount.HasValue)
            discount = Math.Min(discount, voucher.MaxDiscountAmount.Value);
        discount = Math.Max(0, Math.Min(discount, orderAmountBeforeVoucher));
        if (discount <= 0)
            return new VoucherApplyResult(voucher, 0, "Voucher không giảm được giá trị đơn");

        return new VoucherApplyResult(voucher, discount, null);
    }

    public static (decimal PointsDiscount, decimal PointsRedeemed, string? Error) CalcPointsRedeem(
        decimal pointsToRedeem, decimal customerBalance, decimal maxDiscountFromOrder)
    {
        if (pointsToRedeem <= 0) return (0, 0, null);
        if (pointsToRedeem > customerBalance)
            return (0, 0, "Khách không đủ điểm");
        var discount = pointsToRedeem * PointRedeemValue;
        if (discount > maxDiscountFromOrder)
        {
            pointsToRedeem = Math.Floor(maxDiscountFromOrder / PointRedeemValue);
            discount = pointsToRedeem * PointRedeemValue;
        }
        if (pointsToRedeem <= 0)
            return (0, 0, "Số điểm đổi quá nhỏ so với đơn hàng");
        return (discount, pointsToRedeem, null);
    }

    public static decimal CalcPointsEarn(decimal netTotalAfterRedeem)
    {
        if (netTotalAfterRedeem <= 0) return 0;
        return Math.Floor(netTotalAfterRedeem / PointsPerAmount);
    }

    public static async Task ApplyPointsOnSaleCompleteAsync(
        ZKTecoDbContext db,
        Guid storeId,
        PosSaleOrder order,
        PosCustomer customer,
        string createdBy)
    {
        if (order.PointsRedeemed > 0)
        {
            customer.PointBalance = Math.Max(0, customer.PointBalance - order.PointsRedeemed);
            db.PosCustomerPointTransactions.Add(new PosCustomerPointTransaction
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                CustomerId = customer.Id,
                SaleOrderId = order.Id,
                TransactionType = PosCustomerPointType.Redeem,
                Points = order.PointsRedeemed,
                BalanceAfter = customer.PointBalance,
                Note = $"Đổi điểm đơn {order.OrderNo}",
                IsActive = true,
                CreatedBy = createdBy,
            });
        }

        if (order.PointsEarned > 0)
        {
            customer.PointBalance += order.PointsEarned;
            db.PosCustomerPointTransactions.Add(new PosCustomerPointTransaction
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                CustomerId = customer.Id,
                SaleOrderId = order.Id,
                TransactionType = PosCustomerPointType.Earn,
                Points = order.PointsEarned,
                BalanceAfter = customer.PointBalance,
                Note = $"Tích điểm đơn {order.OrderNo}",
                IsActive = true,
                CreatedBy = createdBy,
            });
        }

        customer.UpdatedAt = DateTime.UtcNow;
        await Task.CompletedTask;
    }

    public static async Task ReversePointsOnSaleCancelAsync(
        ZKTecoDbContext db, Guid storeId, PosSaleOrder order, string updatedBy)
    {
        if (!order.CustomerId.HasValue) return;
        var customer = await db.PosCustomers.AsTracking()
            .FirstOrDefaultAsync(c => c.Id == order.CustomerId && c.StoreId == storeId && c.Deleted == null);
        if (customer == null) return;

        if (order.PointsEarned > 0)
        {
            customer.PointBalance = Math.Max(0, customer.PointBalance - order.PointsEarned);
            db.PosCustomerPointTransactions.Add(new PosCustomerPointTransaction
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                CustomerId = customer.Id,
                SaleOrderId = order.Id,
                TransactionType = PosCustomerPointType.Adjust,
                Points = -order.PointsEarned,
                BalanceAfter = customer.PointBalance,
                Note = $"Hủy tích điểm đơn {order.OrderNo}",
                IsActive = true,
                CreatedBy = updatedBy,
            });
        }
        if (order.PointsRedeemed > 0)
        {
            customer.PointBalance += order.PointsRedeemed;
            db.PosCustomerPointTransactions.Add(new PosCustomerPointTransaction
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                CustomerId = customer.Id,
                SaleOrderId = order.Id,
                TransactionType = PosCustomerPointType.Adjust,
                Points = order.PointsRedeemed,
                BalanceAfter = customer.PointBalance,
                Note = $"Hoàn điểm đổi đơn {order.OrderNo}",
                IsActive = true,
                CreatedBy = updatedBy,
            });
        }
        customer.UpdatedAt = DateTime.UtcNow;
    }

    /// <summary>
    /// Điều chỉnh điểm tích khi trả hàng: thu hồi điểm theo tỷ lệ doanh thu còn lại.
    /// Điểm đã đổi (redeem) giữ nguyên — đã trừ tiền lúc bán.
    /// </summary>
    public static async Task AdjustPointsOnReturnAsync(
        ZKTecoDbContext db,
        Guid storeId,
        PosSaleOrder order,
        decimal refundTotal,
        decimal totalBeforeRefund,
        string updatedBy)
    {
        if (!order.CustomerId.HasValue || refundTotal <= 0 || order.PointsEarned <= 0)
            return;
        if (totalBeforeRefund <= 0) return;

        var customer = await db.PosCustomers.AsTracking()
            .FirstOrDefaultAsync(c => c.Id == order.CustomerId && c.StoreId == storeId && c.Deleted == null);
        if (customer == null) return;

        var ratio = Math.Min(1m, refundTotal / totalBeforeRefund);
        var revoke = Math.Floor(order.PointsEarned * ratio);
        if (revoke <= 0) return;

        // Không thu hồi quá số điểm còn ghi trên đơn.
        revoke = Math.Min(revoke, order.PointsEarned);
        customer.PointBalance = Math.Max(0, customer.PointBalance - revoke);
        order.PointsEarned = Math.Max(0, order.PointsEarned - revoke);
        order.UpdatedAt = DateTime.UtcNow;
        order.UpdatedBy = updatedBy;
        customer.UpdatedAt = DateTime.UtcNow;

        db.PosCustomerPointTransactions.Add(new PosCustomerPointTransaction
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            CustomerId = customer.Id,
            SaleOrderId = order.Id,
            TransactionType = PosCustomerPointType.Adjust,
            Points = -revoke,
            BalanceAfter = customer.PointBalance,
            Note = $"Thu hồi điểm do trả hàng đơn {order.OrderNo}",
            IsActive = true,
            CreatedBy = updatedBy,
        });
    }

    /// <summary>Hoàn lại điểm đã thu hồi khi hủy phiếu trả.</summary>
    public static async Task RestorePointsOnReturnVoidAsync(
        ZKTecoDbContext db,
        Guid storeId,
        PosSaleOrder order,
        decimal refundReversed,
        decimal totalAfterVoid,
        string updatedBy)
    {
        if (!order.CustomerId.HasValue || refundReversed <= 0) return;
        var totalBeforeVoid = totalAfterVoid - refundReversed;
        if (totalBeforeVoid < 0) totalBeforeVoid = 0;

        // Tính lại điểm đáng có theo Total sau khi void return.
        var targetEarned = CalcPointsEarn(order.Total);
        var delta = targetEarned - order.PointsEarned;
        if (delta == 0) return;

        var customer = await db.PosCustomers.AsTracking()
            .FirstOrDefaultAsync(c => c.Id == order.CustomerId && c.StoreId == storeId && c.Deleted == null);
        if (customer == null) return;

        if (delta > 0)
            customer.PointBalance += delta;
        else
            customer.PointBalance = Math.Max(0, customer.PointBalance + delta);

        order.PointsEarned = targetEarned;
        order.UpdatedAt = DateTime.UtcNow;
        order.UpdatedBy = updatedBy;
        customer.UpdatedAt = DateTime.UtcNow;

        db.PosCustomerPointTransactions.Add(new PosCustomerPointTransaction
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            CustomerId = customer.Id,
            SaleOrderId = order.Id,
            TransactionType = PosCustomerPointType.Adjust,
            Points = delta,
            BalanceAfter = customer.PointBalance,
            Note = $"Điều chỉnh điểm khi hủy trả hàng đơn {order.OrderNo}",
            IsActive = true,
            CreatedBy = updatedBy,
        });
    }

    public static async Task<(PosCustomerPayment? payment, string? error)> CollectDebtAsync(
        ZKTecoDbContext db,
        Guid storeId,
        PosCustomer customer,
        decimal amount,
        string paymentMethod,
        DateTime? paidAt,
        string? note,
        Guid? saleOrderId,
        string createdBy)
    {
        if (amount <= 0) return (null, "Số tiền phải > 0");
        if (amount > customer.CurrentDebt)
            return (null, $"Số thu vượt công nợ hiện tại ({_fmt(customer.CurrentDebt)} đ)");

        if (saleOrderId.HasValue)
        {
            var ok = await db.PosSaleOrders.AnyAsync(o =>
                o.Id == saleOrderId && o.StoreId == storeId && o.CustomerId == customer.Id && o.Deleted == null);
            if (!ok) return (null, "Đơn hàng không thuộc khách này");
        }

        var pay = new PosCustomerPayment
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            CustomerId = customer.Id,
            SaleOrderId = saleOrderId,
            PaymentNo = PosStockDocumentNo.NewCustomerPayment(),
            Amount = amount,
            PaymentMethod = string.IsNullOrWhiteSpace(paymentMethod) ? "Tiền mặt" : paymentMethod.Trim(),
            PaidAt = paidAt ?? DateTime.UtcNow,
            Note = note?.Trim(),
            IsActive = true,
            CreatedBy = createdBy,
        };
        customer.CurrentDebt = Math.Max(0, customer.CurrentDebt - amount);
        customer.UpdatedAt = DateTime.UtcNow;
        db.PosCustomerPayments.Add(pay);

        // Cập nhật PaidAmount đơn: ưu tiên SaleOrderId; không có thì FIFO theo đơn còn nợ.
        var remaining = amount;
        if (saleOrderId.HasValue)
        {
            var order = await db.PosSaleOrders.AsTracking()
                .FirstOrDefaultAsync(o =>
                    o.Id == saleOrderId && o.StoreId == storeId &&
                    o.CustomerId == customer.Id && o.Deleted == null);
            if (order != null)
                remaining -= ApplyPaidToOrder(order, remaining, createdBy);
        }
        else
        {
            var unpaid = await db.PosSaleOrders.AsTracking()
                .Where(o => o.StoreId == storeId && o.CustomerId == customer.Id &&
                            o.Deleted == null &&
                            o.Status == PosSaleOrderStatus.Completed &&
                            o.PaidAmount < o.Total)
                .OrderBy(o => o.SaleDate)
                .ThenBy(o => o.CreatedAt)
                .ToListAsync();
            foreach (var order in unpaid)
            {
                if (remaining <= 0) break;
                remaining -= ApplyPaidToOrder(order, remaining, createdBy);
            }
        }

        return (pay, null);
    }

    private static decimal ApplyPaidToOrder(PosSaleOrder order, decimal amount, string createdBy)
    {
        var due = Math.Max(0, order.Total - order.PaidAmount);
        var applied = Math.Min(amount, due);
        if (applied <= 0) return 0;
        order.PaidAmount += applied;
        order.UpdatedAt = DateTime.UtcNow;
        order.UpdatedBy = createdBy;
        return applied;
    }

    private static string _fmt(decimal v) => v.ToString("0.##");
}
