using Xunit;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>
/// Kết quả kinh doanh: doanh thu thuần giữ nguyên; thêm phụ thu, phí giao hàng thu khách − cước hãng tính,
/// khấu hao tài sản, cọc khách bỏ (dòng riêng, không cộng hai lần với thu khác); phiếu chi mua tài sản không tính chi phí.
/// </summary>
[Collection("pos-pg")]
public class PosPnlExtrasTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    static decimal N(object o, string name) =>
        Convert.ToDecimal(o.GetType().GetProperty(name)?.GetValue(o)
                          ?? throw new Xunit.Sdk.XunitException($"Thiếu trường {name}"));

    [Fact]
    public async Task Ket_qua_kinh_doanh_gom_phu_thu_phi_giao_hang_cuoc_khau_hao_coc_khach_bo()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var nowUtc = DateTime.UtcNow;
        var todayVn = nowUtc.AddHours(7).Date;
        // Giữa ngày VN hôm nay (tránh lệch kỳ khi chạy gần nửa đêm).
        var saleUtc = todayVn.AddHours(12 - 7);
        PosSaleOrder O(decimal total, PosSaleOrderStatus st) => new()
        {
            Id = Guid.NewGuid(), StoreId = store, OrderNo = "DH" + Guid.NewGuid().ToString("N")[..6], Status = st,
            SubTotal = total, Total = total, SaleDate = saleUtc, CreatedAt = saleUtc, IsActive = true, PaymentMethod = "Tiền mặt",
        };
        await using (var db = Fx.NewDb())
        {
            var userId = await Microsoft.EntityFrameworkCore.EntityFrameworkQueryableExtensions.FirstAsync(
                db.Users.Where(u => u.StoreId == store).Select(u => u.Id));
            var shipped = O(200_000, PosSaleOrderStatus.Completed);
            shipped.SurchargeAmount = 20_000; shipped.DeliveryFee = 30_000; shipped.DeliveryFeePayer = "shop";
            shipped.DeliveryCarrierCode = "ghtk"; shipped.DeliveryCarrierFee = 22_000; shipped.DeliveryStatusCode = "delivered";
            // Đơn bị hoàn (đã hủy): không có doanh thu nhưng vẫn mất cước + cước hoàn.
            var returned = O(90_000, PosSaleOrderStatus.Cancelled);
            returned.DeliveryCarrierCode = "ghtk"; returned.DeliveryCarrierFee = 18_000; returned.DeliveryReturnFee = 9_000;
            returned.DeliveryStatusCode = "returned";
            db.PosSaleOrders.AddRange(shipped, returned);

            var lost = new TransactionCategory { Id = Guid.NewGuid(), StoreId = store, Name = "Mất cọc đặt chỗ", Type = CashTransactionType.Income, IsActive = true };
            var other = new TransactionCategory { Id = Guid.NewGuid(), StoreId = store, Name = "Thu khác", Type = CashTransactionType.Income, IsActive = true };
            var buy = new TransactionCategory { Id = Guid.NewGuid(), StoreId = store, Name = "Mua tài sản", Type = CashTransactionType.Expense, IsActive = true };
            var power = new TransactionCategory { Id = Guid.NewGuid(), StoreId = store, Name = "Tiền điện", Type = CashTransactionType.Expense, IsActive = true };
            db.AddRange(lost, other, buy, power);
            CashTransaction C(TransactionCategory cat, CashTransactionType t, decimal amt, string? note = null) => new()
            {
                Id = Guid.NewGuid(), StoreId = store, Type = t, Amount = amt, CategoryId = cat.Id, InternalNote = note,
                TransactionCode = "PC" + Guid.NewGuid().ToString("N")[..6], TransactionDate = todayVn.AddHours(12),
                Status = CashTransactionStatus.Completed, IsActive = true, CreatedAt = nowUtc, Description = "test",
                CreatedByUserId = userId,
            };
            db.CashTransactions.AddRange(
                C(lost, CashTransactionType.Income, 150_000, $"{PosFinanceSyncHelper.ReservationDepositMarker}{Guid.NewGuid()}"),
                C(other, CashTransactionType.Income, 40_000),
                C(buy, CashTransactionType.Expense, 8_000_000),
                C(power, CashTransactionType.Expense, 60_000));
            // 36,5 triệu, 100%/năm → 100.000 đ/ngày; kỳ = 1 ngày.
            db.Assets.Add(new Asset
            {
                Id = Guid.NewGuid(), StoreId = store, AssetCode = "TS-" + Guid.NewGuid().ToString("N")[..6], Name = "Tủ mát",
                PurchasePrice = 36_500_000, Quantity = 1, DepreciationRate = 100,
                PurchaseDate = DateTime.SpecifyKind(todayVn.AddDays(-30), DateTimeKind.Utc), Status = AssetStatus.Active, IsActive = true,
            });
            await db.SaveChangesAsync();
        }

        await using var db2 = Fx.NewDb();
        var p = Data(await Reports(db2, store).GetPnlSummary(todayVn, todayVn));
        Assert.Equal(200_000m, N(p, "revenue"));               // doanh thu thuần giữ nguyên
        Assert.Equal(20_000m, N(p, "surchargeIncome"));
        Assert.Equal(30_000m, N(p, "deliveryFeeIncome"));
        Assert.Equal(49_000m, N(p, "carrierCost"));             // 22k + 18k + 9k cước hoàn
        Assert.Equal(100_000m, N(p, "depreciation"));
        Assert.Equal(150_000m, N(p, "forfeitedDeposits"));
        Assert.Equal(40_000m, N(p, "otherIncome"));             // không gồm cọc khách bỏ (không cộng hai lần)
        Assert.Equal(60_000m, N(p, "expenses"));                // không gồm 8 triệu mua tài sản
        // 200 + 20 + 30 − 49 − 100 − 60 + 150 + 40
        Assert.Equal(231_000m, N(p, "netProfit"));
    }
}
