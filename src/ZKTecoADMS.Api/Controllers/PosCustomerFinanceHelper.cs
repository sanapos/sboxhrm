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
            customer.PointBalance = Math.Max(0, customer.PointBalance - order.PointsEarned);
        if (order.PointsRedeemed > 0)
            customer.PointBalance += order.PointsRedeemed;
        customer.UpdatedAt = DateTime.UtcNow;
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
        return (pay, null);
    }

    private static string _fmt(decimal v) => v.ToString("0.##");
}
