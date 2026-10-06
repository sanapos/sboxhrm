using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

public static class PosCustomerFinanceHelper
{
    /// <summary>Fallback khi cửa hàng chưa cấu hình: 1 điểm / 10.000đ.</summary>
    public const decimal PointsPerAmount = 10_000m;

    /// <summary>Fallback: 1 điểm = 100đ giảm giá.</summary>
    public const decimal PointRedeemValue = 100m;

    public readonly record struct PosLoyaltyRates(
        bool Enabled,
        decimal EarnPerAmount,
        decimal RedeemValue,
        decimal MaxRedeemPercent)
    {
        public static PosLoyaltyRates Defaults { get; } = new(true, PointsPerAmount, PointRedeemValue, 100m);

        public bool CanEarn => Enabled && EarnPerAmount > 0;
        public bool CanRedeem => Enabled && RedeemValue > 0;

        public static PosLoyaltyRates From(PosStoreSellSettings? s)
        {
            if (s == null) return Defaults;
            var maxPct = s.LoyaltyMaxRedeemPercent;
            if (maxPct <= 0) maxPct = 100m;
            if (maxPct > 100m) maxPct = 100m;
            return new(
                s.LoyaltyEnabled,
                Math.Max(0, s.LoyaltyEarnPerAmount),
                Math.Max(0, s.LoyaltyRedeemValue),
                maxPct);
        }
    }

    public static PosLoyaltyRates ResolveRates(PosStoreSellSettings? s) => PosLoyaltyRates.From(s);

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
            // Chặn % > 100 (dữ liệu cũ lưu nhầm kiểu giảm) — không bao giờ giảm quá giá trị đơn theo %.
            ? Math.Round(orderAmountBeforeVoucher * Math.Min(voucher.DiscountValue, 100m) / 100m, 0)
            : voucher.DiscountValue;
        if (voucher.MaxDiscountAmount.HasValue)
            discount = Math.Min(discount, voucher.MaxDiscountAmount.Value);
        discount = Math.Max(0, Math.Min(discount, orderAmountBeforeVoucher));
        if (discount <= 0)
            return new VoucherApplyResult(voucher, 0, "Voucher không giảm được giá trị đơn");

        return new VoucherApplyResult(voucher, discount, null);
    }

    public static (decimal PointsDiscount, decimal PointsRedeemed, string? Error) CalcPointsRedeem(
        decimal pointsToRedeem, decimal customerBalance, decimal maxDiscountFromOrder,
        PosLoyaltyRates? rates = null)
    {
        if (pointsToRedeem <= 0) return (0, 0, null);
        var r = rates ?? PosLoyaltyRates.Defaults;
        if (!r.CanRedeem)
            return (0, 0, "Cửa hàng chưa bật đổi điểm");
        if (pointsToRedeem > customerBalance)
            return (0, 0, "Khách không đủ điểm");
        var cap = maxDiscountFromOrder;
        if (r.MaxRedeemPercent < 100m)
            cap = Math.Min(cap, Math.Round(maxDiscountFromOrder * r.MaxRedeemPercent / 100m, 0));
        cap = Math.Max(0, cap);
        var discount = pointsToRedeem * r.RedeemValue;
        if (discount > cap)
        {
            pointsToRedeem = Math.Floor(cap / r.RedeemValue);
            discount = pointsToRedeem * r.RedeemValue;
        }
        if (pointsToRedeem <= 0)
            return (0, 0, "Số điểm đổi quá nhỏ so với đơn hàng");
        return (discount, pointsToRedeem, null);
    }

    /// <summary>Một dòng hàng để tính điểm: thành tiền dòng + % tích lũy riêng của hàng (null = mức chung).</summary>
    public readonly record struct EarnLine(decimal LineTotal, decimal? LoyaltyPercent);

    /// <summary>
    /// Điểm tích của đơn khi có hàng tích theo %: tiền dòng được chia lại theo tổng đơn thực trả (đã trừ giảm đơn,
    /// voucher, đổi điểm — không vượt thành tiền dòng). Dòng có % → tích (tiền × %) quy ra điểm theo giá trị 1 điểm
    /// (VD 100.000đ × 20% = 20.000đ = 200 điểm khi 1 điểm = 100đ). Dòng không có % → mức chung (X đồng = 1 điểm).
    /// </summary>
    public static decimal CalcPointsEarn(decimal orderTotal, IReadOnlyCollection<EarnLine> lines, PosLoyaltyRates rates)
    {
        if (!rates.Enabled || orderTotal <= 0) return 0;
        if (!lines.Any(l => l.LoyaltyPercent is > 0)) return CalcPointsEarn(orderTotal, rates);
        var sum = lines.Sum(l => Math.Max(0, l.LineTotal));
        if (sum <= 0) return 0;
        var ratio = Math.Min(1m, orderTotal / sum);
        decimal percentMoney = 0, rest = 0;
        foreach (var l in lines)
        {
            var net = Math.Max(0, l.LineTotal) * ratio;
            if (l.LoyaltyPercent is > 0) percentMoney += net * Math.Min(100m, l.LoyaltyPercent.Value) / 100m;
            else rest += net;
        }
        var points = rates.RedeemValue > 0 ? Math.Floor(percentMoney / rates.RedeemValue) : 0;
        if (rates.CanEarn) points += Math.Floor(rest / rates.EarnPerAmount);
        return points;
    }

    /// <summary>Dòng tính điểm của đơn (đọc % tích lũy của hàng).</summary>
    public static async Task<List<EarnLine>> EarnLinesAsync(ZKTecoDbContext db, Guid storeId, PosSaleOrder order)
    {
        List<(Guid ProductId, decimal LineTotal)> lines;
        if (order.Lines.Count > 0)
            lines = order.Lines.Where(l => l.Deleted == null).Select(l => (l.ProductId, l.LineTotal)).ToList();
        else
            lines = (await db.PosSaleOrderLines.AsNoTracking()
                    .Where(l => l.SaleOrderId == order.Id && l.Deleted == null)
                    .Select(l => new { l.ProductId, l.LineTotal })
                    .ToListAsync())
                .Select(x => (x.ProductId, x.LineTotal)).ToList();
        var ids = lines.Select(l => l.ProductId).Distinct().ToList();
        var pct = await db.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == storeId && ids.Contains(p.Id) && p.LoyaltyPercent != null)
            .Select(p => new { p.Id, p.LoyaltyPercent })
            .ToDictionaryAsync(p => p.Id, p => p.LoyaltyPercent);
        return lines.Select(l => new EarnLine(l.LineTotal, pct.GetValueOrDefault(l.ProductId))).ToList();
    }

    public static decimal CalcPointsEarn(decimal netTotalAfterRedeem, PosLoyaltyRates? rates = null)
    {
        var r = rates ?? PosLoyaltyRates.Defaults;
        if (!r.CanEarn || netTotalAfterRedeem <= 0) return 0;
        return Math.Floor(netTotalAfterRedeem / r.EarnPerAmount);
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
        // Phần điểm đã hoàn khi trả hàng trước đó thì không hoàn lần nữa.
        var redeemLeft = order.PointsRedeemed > 0
            ? Math.Max(0, order.PointsRedeemed - await RedeemRefundedAsync(db, storeId, order.Id))
            : 0;
        if (redeemLeft > 0)
        {
            customer.PointBalance += redeemLeft;
            db.PosCustomerPointTransactions.Add(new PosCustomerPointTransaction
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                CustomerId = customer.Id,
                SaleOrderId = order.Id,
                TransactionType = PosCustomerPointType.Adjust,
                Points = redeemLeft,
                BalanceAfter = customer.PointBalance,
                Note = $"Hoàn điểm đổi đơn {order.OrderNo}",
                IsActive = true,
                CreatedBy = updatedBy,
            });
        }
        customer.UpdatedAt = DateTime.UtcNow;
    }

    /// <summary>Đầu ghi chú giao dịch «hoàn điểm đã đổi khi trả hàng» — dùng để cộng dồn / hủy theo phiếu trả.</summary>
    public const string RedeemRefundNotePrefix = "Hoàn điểm đã đổi do trả hàng ";

    /// <summary>Tổng điểm đã đổi trên đơn đã được hoàn lại qua các phiếu trả (còn hiệu lực).</summary>
    public static async Task<decimal> RedeemRefundedAsync(ZKTecoDbContext db, Guid storeId, Guid orderId) =>
        await db.PosCustomerPointTransactions.AsNoTracking()
            .Where(t => t.StoreId == storeId && t.SaleOrderId == orderId && t.IsActive && t.Deleted == null
                        && t.Note != null && t.Note.StartsWith(RedeemRefundNotePrefix))
            .SumAsync(t => (decimal?)t.Points) ?? 0;

    /// <summary>
    /// Điều chỉnh điểm khi trả hàng: thu hồi điểm đã tích theo tỷ lệ doanh thu trả lại.
    /// Nếu cửa hàng bật «Hoàn điểm đã đổi khi trả hàng»: hoàn lại phần điểm khách đã đổi trên đơn theo cùng tỷ lệ
    /// (trả hết đơn → hoàn hết). Tắt: điểm đã đổi coi như đã dùng (đã trừ tiền lúc bán).
    /// </summary>
    public static async Task AdjustPointsOnReturnAsync(
        ZKTecoDbContext db,
        Guid storeId,
        PosSaleOrder order,
        decimal refundTotal,
        decimal totalBeforeRefund,
        string updatedBy,
        string? returnNo = null)
    {
        if (!order.CustomerId.HasValue || refundTotal <= 0 || totalBeforeRefund <= 0) return;
        var ratio = Math.Min(1m, refundTotal / totalBeforeRefund);

        var revoke = order.PointsEarned > 0 ? Math.Min(order.PointsEarned, Math.Floor(order.PointsEarned * ratio)) : 0;

        decimal refundRedeem = 0;
        if (order.PointsRedeemed > 0)
        {
            var refundOn = await db.PosStoreSellSettings.AsNoTracking()
                .Where(x => x.StoreId == storeId && x.Deleted == null)
                .Select(x => x.LoyaltyRefundRedeemOnReturn)
                .FirstOrDefaultAsync();
            if (refundOn)
            {
                var left = Math.Max(0, order.PointsRedeemed - await RedeemRefundedAsync(db, storeId, order.Id));
                refundRedeem = ratio >= 1m ? left : Math.Min(left, Math.Floor(left * ratio));
            }
        }
        if (revoke <= 0 && refundRedeem <= 0) return;

        var customer = await db.PosCustomers.AsTracking()
            .FirstOrDefaultAsync(c => c.Id == order.CustomerId && c.StoreId == storeId && c.Deleted == null);
        if (customer == null) return;

        if (revoke > 0)
        {
            customer.PointBalance = Math.Max(0, customer.PointBalance - revoke);
            order.PointsEarned = Math.Max(0, order.PointsEarned - revoke);
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
        if (refundRedeem > 0)
        {
            customer.PointBalance += refundRedeem;
            db.PosCustomerPointTransactions.Add(new PosCustomerPointTransaction
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                CustomerId = customer.Id,
                SaleOrderId = order.Id,
                TransactionType = PosCustomerPointType.Adjust,
                Points = refundRedeem,
                BalanceAfter = customer.PointBalance,
                Note = $"{RedeemRefundNotePrefix}{returnNo ?? ""} · đơn {order.OrderNo}",
                IsActive = true,
                CreatedBy = updatedBy,
            });
        }
        order.UpdatedAt = DateTime.UtcNow;
        order.UpdatedBy = updatedBy;
        customer.UpdatedAt = DateTime.UtcNow;
    }

    /// <summary>Hoàn lại điểm đã thu hồi khi hủy phiếu trả.</summary>
    public static async Task RestorePointsOnReturnVoidAsync(
        ZKTecoDbContext db,
        Guid storeId,
        PosSaleOrder order,
        decimal refundReversed,
        decimal totalAfterVoid,
        string updatedBy,
        string? returnNo = null)
    {
        if (!order.CustomerId.HasValue || refundReversed <= 0) return;

        // Hủy phiếu trả → thu lại phần điểm đã đổi từng được hoàn theo phiếu đó.
        if (!string.IsNullOrWhiteSpace(returnNo))
        {
            var marker = $"{RedeemRefundNotePrefix}{returnNo} ";
            var refunds = await db.PosCustomerPointTransactions.AsTracking()
                .Where(t => t.StoreId == storeId && t.SaleOrderId == order.Id && t.IsActive && t.Deleted == null
                            && t.Note != null && t.Note.StartsWith(marker))
                .ToListAsync();
            if (refunds.Count > 0)
            {
                var cust = await db.PosCustomers.AsTracking()
                    .FirstOrDefaultAsync(c => c.Id == order.CustomerId && c.StoreId == storeId && c.Deleted == null);
                var back = refunds.Sum(t => t.Points);
                foreach (var t in refunds) t.IsActive = false;
                if (cust != null && back > 0)
                {
                    cust.PointBalance = Math.Max(0, cust.PointBalance - back);
                    cust.UpdatedAt = DateTime.UtcNow;
                    db.PosCustomerPointTransactions.Add(new PosCustomerPointTransaction
                    {
                        Id = Guid.NewGuid(),
                        StoreId = storeId,
                        CustomerId = cust.Id,
                        SaleOrderId = order.Id,
                        TransactionType = PosCustomerPointType.Adjust,
                        Points = -back,
                        BalanceAfter = cust.PointBalance,
                        Note = $"Thu lại điểm đã hoàn do hủy trả {returnNo} · đơn {order.OrderNo}",
                        IsActive = true,
                        CreatedBy = updatedBy,
                    });
                }
            }
        }
        var totalBeforeVoid = totalAfterVoid - refundReversed;
        if (totalBeforeVoid < 0) totalBeforeVoid = 0;

        // Tính lại điểm đáng có theo Total sau khi void return + tỷ lệ cửa hàng hiện tại.
        var settings = await db.PosStoreSellSettings.AsNoTracking()
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.Deleted == null);
        var targetEarned = CalcPointsEarn(order.Total, await EarnLinesAsync(db, storeId, order), PosLoyaltyRates.From(settings));
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
