using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Api.Services.Shipping;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Sổ quỹ đơn online COD và hoàn tất đơn tạm: chỉ ghi thu khi quán thật sự cầm tiền, đúng từng phương thức.</summary>
[Collection("pos-pg")]
public class PosOnlineCodCashTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    static PosSalesController.CreateSaleDto Draft(Guid product, string requestId,
        List<PosSalesController.SalePaymentInputDto>? payments = null) =>
        new([new PosSalesController.SaleLineDto(product, 2, null, 10000, null)],
            0, payments?.Sum(p => p.Amount) ?? 0, "Tiền mặt", null, null, null,
            Complete: false, ClientRequestId: requestId, Payments: payments);

    async Task<Guid> OnlineDraftAsync(Guid store, Guid product, string requestId, string? trackingCode)
    {
        Guid id;
        await using (var db = Fx.NewDb())
            id = Data(await Sales(db, store).CreateSale(Draft(product, requestId))).Id;
        await using (var db = Fx.NewDb())
            await db.PosSaleOrders.Where(o => o.Id == id).ExecuteUpdateAsync(s => s
                .SetProperty(o => o.SalesChannel, PosOnlineOrderHelper.QrOnlineChannel)
                .SetProperty(o => o.IsDelivery, true)
                .SetProperty(o => o.DeliveryTrackingCode, trackingCode)
                .SetProperty(o => o.DeliveryCarrierCode, trackingCode == null ? PosOnlineOrderHelper.InternalCarrierCode : "Ghn"));
        return id;
    }

    async Task<(bool Ok, string? Error)> CompleteCodAsync(Guid store, Guid id, bool collected)
    {
        await using var db = Fx.NewDb();
        var order = await db.PosSaleOrders.AsTracking().Include(o => o.Lines).FirstAsync(o => o.Id == id);
        return await PosOnlineOrderHelper.TryCompleteAsCodAsync(db, store, order, "test@sbox.vn", collected);
    }

    async Task<List<CashTransaction>> SaleCashAsync(Guid store)
    {
        await using var db = Fx.NewDb();
        return await db.CashTransactions
            .Where(c => c.StoreId == store && c.Deleted == null && c.IsActive && c.InternalNote != null
                && (c.InternalNote.StartsWith(PosFinanceSyncHelper.SaleMarker)
                    || c.InternalNote.StartsWith(PosFinanceSyncHelper.CodReceiptMarker)))
            .ToListAsync();
    }

    [Fact]
    public async Task Carrier_cod_order_records_cash_only_when_the_carrier_settles()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var p = (await Fx.AddProductAsync(store, "Trà sữa", PosProductType.Goods, 50, 4000, 10000)).Id;
        var id = await OnlineDraftAsync(store, p, "req-cod-carrier-01", "GHN123");

        // Tự hoàn tất lúc xác nhận: chưa thu đồng nào → không phiếu thu tiền mặt, đơn còn nợ.
        Assert.Equal((true, (string?)null), await CompleteCodAsync(store, id, collected: false));
        var done = await OrderAsync(id);
        Assert.Equal(PosSaleOrderStatus.Completed, done.Status);
        Assert.Equal(0m, done.PaidAmount);
        Assert.Empty(await SaleCashAsync(store));
        Assert.Equal(48, await OnHandAsync(p));

        // Hãng giao xong, chuyển tiền thu hộ → đối soát ghi đúng một phiếu «Thu hộ COD» đủ tiền.
        await using (var db = Fx.NewDb())
            await db.PosSaleOrders.Where(o => o.Id == id).ExecuteUpdateAsync(s => s
                .SetProperty(o => o.DeliveryStatusCode, ShipmentStatus.Delivered)
                .SetProperty(o => o.DeliveryCodAmount, 20000m));
        await using (var db = Fx.NewDb())
        {
            var userId = await db.Users.Where(u => u.StoreId == store).Select(u => u.Id).FirstAsync();
            var (n, errors) = await new PosShippingService(db, [], NullLogger<PosShippingService>.Instance)
                .SettleCodAsync(store, [id], true, userId, "test@sbox.vn", default);
            Assert.Equal(1, n);
            Assert.Empty(errors);
        }
        var cash = Assert.Single(await SaleCashAsync(store));
        Assert.StartsWith(PosFinanceSyncHelper.CodReceiptMarker, cash.InternalNote);
        Assert.Equal(20000m, cash.Amount);
        Assert.Equal(20000m, (await OrderAsync(id)).PaidAmount);
    }

    [Fact]
    public async Task Internal_delivery_records_cash_once_when_delivered()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var p = (await Fx.AddProductAsync(store, "Cà phê", PosProductType.Goods, 50, 4000, 10000)).Id;
        var id = await OnlineDraftAsync(store, p, "req-cod-internal-01", trackingCode: null);

        Assert.Equal((true, (string?)null), await CompleteCodAsync(store, id, collected: false));
        Assert.Empty(await SaleCashAsync(store));

        // Người giao của quán giao xong (bấm «Giao thành công» 2 lần / 2 máy) → một phiếu thu tiền mặt đủ.
        for (var i = 0; i < 2; i++)
        {
            await using var db = Fx.NewDb();
            var order = await db.PosSaleOrders.AsTracking().FirstAsync(o => o.Id == id);
            await PosOnlineOrderHelper.CollectCodOnDeliveredAsync(db, store, order, "test@sbox.vn");
            await db.SaveChangesAsync();
        }
        var cash = Assert.Single(await SaleCashAsync(store));
        Assert.Equal(20000m, cash.Amount);
        Assert.Equal(PaymentMethodType.Cash, cash.PaymentMethod);
        Assert.Equal(20000m, (await OrderAsync(id)).PaidAmount);
    }

    [Fact]
    public async Task Draft_delivered_internally_completes_with_cash_receipt()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var p = (await Fx.AddProductAsync(store, "Bánh mì", PosProductType.Goods, 50, 4000, 10000)).Id;
        var id = await OnlineDraftAsync(store, p, "req-cod-internal-02", trackingCode: null);

        Assert.Equal((true, (string?)null), await CompleteCodAsync(store, id, collected: true));
        var cash = Assert.Single(await SaleCashAsync(store));
        Assert.Equal(20000m, cash.Amount);
        Assert.Equal(20000m, (await OrderAsync(id)).PaidAmount);
    }

    [Fact]
    public async Task Completing_split_payment_draft_is_refused_instead_of_one_merged_voucher()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var p = (await Fx.AddProductAsync(store, "Lẩu", PosProductType.Goods, 50, 4000, 10000)).Id;
        Guid id;
        await using (var db = Fx.NewDb())
            id = Data(await Sales(db, store).CreateSale(Draft(p, "req-split-pay-01",
            [
                new PosSalesController.SalePaymentInputDto(10000, "Tiền mặt"),
                new PosSalesController.SalePaymentInputDto(10000, "Chuyển khoản"),
            ]))).Id;
        Assert.Equal("Tiền mặt + Chuyển khoản", (await OrderAsync(id)).PaymentMethod);

        await using (var db = Fx.NewDb())
        {
            var err = Error(await Sales(db, store).CompleteSale(id, new PosSalesController.CompleteSaleDto()));
            Assert.NotNull(err);
            Assert.Contains("nhiều hình thức thanh toán", err);
        }
        Assert.Equal(PosSaleOrderStatus.Draft, (await OrderAsync(id)).Status);
        Assert.Empty(await SaleCashAsync(store));
        Assert.Equal(50, await OnHandAsync(p));
    }

    [Fact]
    public async Task Completing_single_payment_draft_still_records_its_receipt()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var p = (await Fx.AddProductAsync(store, "Phở", PosProductType.Goods, 50, 4000, 10000)).Id;
        Guid id;
        await using (var db = Fx.NewDb())
            id = Data(await Sales(db, store).CreateSale(Draft(p, "req-single-pay-01",
                [new PosSalesController.SalePaymentInputDto(20000, "Tiền mặt")]))).Id;

        await using (var db = Fx.NewDb())
            Data(await Sales(db, store).CompleteSale(id, new PosSalesController.CompleteSaleDto()));
        var cash = Assert.Single(await SaleCashAsync(store));
        Assert.Equal(20000m, cash.Amount);
        Assert.Equal(PaymentMethodType.Cash, cash.PaymentMethod);
    }
}
