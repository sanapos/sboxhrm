using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Thanh toán không trùng / không «thành công giả»: mã chống trùng xét trạng thái, hoàn tất đơn
/// nguyên tử, dọn bàn không xóa bill tách chưa trả.</summary>
[Collection("pos-pg")]
public class PosCheckoutIdempotencyTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    static PosSalesController.CreateSaleDto Cart(Guid product, decimal qty, bool complete, string requestId,
        Guid? table = null, bool split = false) =>
        new([new PosSalesController.SaleLineDto(product, qty, null, 10000, null)],
            0, complete ? 10000 * qty : 0, "Tiền mặt", null, null, null,
            Complete: complete, ServiceResourceId: table, ClientRequestId: requestId, SplitOfTableBill: split);

    [Fact]
    public async Task Same_request_id_as_saved_draft_completes_that_draft_instead_of_fake_success()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var p = (await Fx.AddProductAsync(store, "Trà", PosProductType.Goods, 100, 4000, 10000)).Id;

        PosSalesController.SaleOrderDto draft;
        await using (var db = Fx.NewDb())
            draft = Data(await Sales(db, store).CreateSale(Cart(p, 2, complete: false, "req-same-0001")));
        Assert.Equal("Draft", draft.Status);

        // Lần tự lưu đã tạo nháp nhưng máy mất phản hồi → bấm thanh toán gửi lại cùng mã.
        PosSalesController.SaleOrderDto paid;
        await using (var db = Fx.NewDb())
            paid = Data(await Sales(db, store).CreateSale(Cart(p, 2, complete: true, "req-same-0001")));

        Assert.Equal(draft.Id, paid.Id);
        Assert.Equal("Completed", paid.Status);
        Assert.False(paid.AlreadyCompleted);
        await using (var db = Fx.NewDb())
            // (Ô hóa đơn vừa TT được tạo lại bằng một nháp trống — không tính.)
            Assert.Equal(1, await db.PosSaleOrders.CountAsync(o => o.StoreId == store && o.Deleted == null && o.Total > 0));
        Assert.Equal(98, await OnHandAsync(p));

        // Gửi lại lần nữa (mất phản hồi lần thanh toán) → trả đơn cũ, đánh dấu đã hoàn tất trước đó.
        await using (var db = Fx.NewDb())
        {
            var again = Data(await Sales(db, store).CreateSale(Cart(p, 2, complete: true, "req-same-0001")));
            Assert.Equal(draft.Id, again.Id);
            Assert.True(again.AlreadyCompleted);
        }
        Assert.Equal(98, await OnHandAsync(p));
    }

    [Fact]
    public async Task Completing_an_already_completed_draft_flags_it_and_deducts_stock_once()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var p = (await Fx.AddProductAsync(store, "Bánh", PosProductType.Goods, 50, 4000, 10000)).Id;
        Guid id;
        await using (var db = Fx.NewDb())
            id = Data(await Sales(db, store).CreateSale(Cart(p, 1, complete: false, "req-draft-0001"))).Id;

        await using (var db = Fx.NewDb())
            Assert.False(Data(await Sales(db, store).CompleteSale(id, new PosSalesController.CompleteSaleDto())).AlreadyCompleted);

        // Máy khác / webhook đã TT → thu ngân bấm hoàn tất từ giỏ.
        await using (var db = Fx.NewDb())
        {
            var r = Data(await Sales(db, store).UpdateSale(id, new PosSalesController.UpdateSaleDto(
                [new PosSalesController.SaleLineDto(p, 1, null, 10000, null)], 0, 10000, "Tiền mặt",
                null, null, null, Complete: true)));
            Assert.True(r.AlreadyCompleted);
            Assert.Equal("Completed", r.Status);
        }
        await using (var db = Fx.NewDb())
            Assert.True(Data(await Sales(db, store).CompleteSale(id, new PosSalesController.CompleteSaleDto())).AlreadyCompleted);
        Assert.Equal(49, await OnHandAsync(p));
    }

    [Fact]
    public async Task Two_simultaneous_completions_of_one_draft_deduct_stock_once()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var p = (await Fx.AddProductAsync(store, "Cơm", PosProductType.Goods, 20, 4000, 10000)).Id;
        Guid id;
        await using (var db = Fx.NewDb())
            id = Data(await Sales(db, store).CreateSale(Cart(p, 3, complete: false, "req-race-0001"))).Id;

        await using var db1 = Fx.NewDb();
        await using var db2 = Fx.NewDb();
        var t1 = Sales(db1, store).CompleteSale(id, new PosSalesController.CompleteSaleDto());
        var t2 = Sales(db2, store).CompleteSale(id, new PosSalesController.CompleteSaleDto());
        var results = await Task.WhenAll(t1, t2);
        var done = results.Select(Data).ToList();

        Assert.All(done, d => Assert.Equal("Completed", d.Status));
        Assert.Equal(1, done.Count(d => !d.AlreadyCompleted));
        Assert.Equal(17, await OnHandAsync(p));
    }

    [Fact]
    public async Task Paying_main_bill_keeps_the_unpaid_split_bill_on_the_table()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var p = (await Fx.AddProductAsync(store, "Lẩu", PosProductType.Goods, 100, 4000, 10000)).Id;
        var area = Guid.NewGuid();
        var table = Guid.NewGuid();
        await using (var db = Fx.NewDb())
        {
            db.PosServiceAreas.Add(new PosServiceArea { Id = area, StoreId = store, Name = "Tầng 1" });
            db.PosServiceResources.Add(new PosServiceResource { Id = table, StoreId = store, AreaId = area, Code = "B5", Name = "Bàn 5" });
            await db.SaveChangesAsync();
        }
        Guid mainId;
        await using (var db = Fx.NewDb())
            mainId = Data(await Sales(db, store).CreateSale(Cart(p, 2, complete: false, "req-main-0001", table))).Id;
        await using (var db = Fx.NewDb())
        {
            db.PosResourceSessions.Add(new PosResourceSession
            {
                Id = Guid.NewGuid(), StoreId = store, ResourceId = table, SaleOrderId = mainId,
                StartedAt = DateTime.UtcNow.AddMinutes(-15), Status = PosResourceSessionStatus.Open,
            });
            await db.SaveChangesAsync();
        }
        await using (var db = Fx.NewDb())
            Data(await Sales(db, store).CreateSale(Cart(p, 1, complete: false, "req-split-0001", table, split: true)));
        Guid splitId;
        await using (var db = Fx.NewDb())
        {
            var split = await db.PosSaleOrders.SingleAsync(o => o.StoreId == store && o.ClientRequestId == "req-split-0001");
            Assert.Equal(mainId, split.SplitFromOrderId);
            splitId = split.Id;
        }

        await using (var db = Fx.NewDb())
            Data(await Sales(db, store).CompleteSale(mainId, new PosSalesController.CompleteSaleDto()));

        await using (var db = Fx.NewDb())
        {
            var split = await db.PosSaleOrders.SingleAsync(o => o.Id == splitId);
            Assert.Null(split.Deleted);
            Assert.Equal(PosSaleOrderStatus.Draft, split.Status);
            Assert.Equal(table, split.ServiceResourceId);
            Assert.Equal(PosSaleOrderStatus.Completed,
                (await db.PosSaleOrders.SingleAsync(o => o.Id == mainId)).Status);
        }
    }
}
