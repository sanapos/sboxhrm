using System.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Lưu nháp gộp 3 chiều: máy cầm giỏ cũ không xóa món máy khác / QR / báo bếp vừa thêm.</summary>
[Collection("pos-pg")]
public class PosDraftMergeTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    static PosSalesController.SaleLineDto L(Guid p, decimal qty) => new(p, qty, null, 10000, null);

    static List<PosSalesController.BaseLineDto> Base(PosSalesController.SaleOrderDto o) =>
        [.. o.Lines.Select(l => new PosSalesController.BaseLineDto(l.Id, l.ProductId, l.VariantId, null, null, l.Qty))];

    static PosSalesController.UpdateSaleDto Save(List<PosSalesController.SaleLineDto> lines,
        List<PosSalesController.BaseLineDto>? baseLines, bool complete = false) =>
        new(lines, 0, complete ? lines.Sum(l => l.Qty * 10000) : 0, "Tiền mặt", null, null, null,
            Complete: complete, BaseLines: baseLines);

    async Task<(Guid Store, Guid Tra, Guid Banh, Guid Com)> SetupAsync()
    {
        var store = await Fx.NewStoreAsync();
        var tra = (await Fx.AddProductAsync(store, "Trà", PosProductType.Goods, 100, 4000, 10000)).Id;
        var banh = (await Fx.AddProductAsync(store, "Bánh", PosProductType.Goods, 100, 4000, 10000)).Id;
        var com = (await Fx.AddProductAsync(store, "Cơm", PosProductType.Goods, 100, 4000, 10000)).Id;
        return (store, tra, banh, com);
    }

    async Task<PosSalesController.SaleOrderDto> DraftAsync(Guid store, params PosSalesController.SaleLineDto[] lines)
    {
        await using var db = Fx.NewDb();
        return Data(await Sales(db, store).CreateSale(new PosSalesController.CreateSaleDto(
            [.. lines], 0, 0, "Tiền mặt", null, null, null, Complete: false)));
    }

    /// <summary>Máy khác / QR / báo bếp thêm món thẳng vào đơn (không qua giỏ máy A).</summary>
    async Task RemoteAddAsync(Guid store, Guid orderId, Guid product, decimal qty)
    {
        await using var db = Fx.NewDb();
        var order = await db.PosSaleOrders.AsTracking().FirstAsync(o => o.Id == orderId);
        db.PosSaleOrderLines.Add(new PosSaleOrderLine
        {
            Id = Guid.NewGuid(), StoreId = store, SaleOrderId = orderId, ProductId = product,
            ProductName = "remote", Qty = qty, UnitPrice = 10000, LineTotal = qty * 10000,
            KitchenSentQty = qty, KitchenSentAt = DateTime.UtcNow,
        });
        order.LockVersion++;
        await db.SaveChangesAsync();
    }

    async Task<Dictionary<Guid, decimal>> QtyAsync(Guid orderId)
    {
        await using var db = Fx.NewDb();
        return (await db.PosSaleOrderLines.Where(l => l.SaleOrderId == orderId && l.Deleted == null).ToListAsync())
            .GroupBy(l => l.ProductId).ToDictionary(g => g.Key, g => g.Sum(x => x.Qty));
    }

    [Fact]
    public async Task Stale_cart_save_keeps_items_added_on_another_device()
    {
        if (NoDb) return;
        var (store, tra, banh, com) = await SetupAsync();
        var a = await DraftAsync(store, L(tra, 1));
        await RemoteAddAsync(store, a.Id, banh, 2);

        // Máy A chưa tải lại: giỏ cũ (Trà 1) + vừa thêm Cơm 1.
        PosSalesController.SaleOrderDto saved;
        await using (var db = Fx.NewDb())
            saved = Data(await Sales(db, store).UpdateSale(a.Id, Save([L(tra, 1), L(com, 1)], Base(a))));

        Assert.Equal(1, saved.MergedRemoteLines);
        var q = await QtyAsync(a.Id);
        Assert.Equal(1, q[tra]);
        Assert.Equal(1, q[com]);
        Assert.Equal(2, q[banh]);
        Assert.Equal(40000m, saved.Total);
        // Món máy khác đã báo bếp vẫn giữ trạng thái đã báo.
        await using (var db = Fx.NewDb())
            Assert.Equal(2, (await db.PosSaleOrderLines.SingleAsync(l => l.SaleOrderId == a.Id && l.ProductId == banh)).KitchenSentQty);
    }

    [Fact]
    public async Task Old_app_without_base_still_overwrites_as_before()
    {
        if (NoDb) return;
        var (store, tra, banh, _) = await SetupAsync();
        var a = await DraftAsync(store, L(tra, 1));
        await RemoteAddAsync(store, a.Id, banh, 2);
        await using (var db = Fx.NewDb())
            Assert.Equal(0, Data(await Sales(db, store).UpdateSale(a.Id, Save([L(tra, 2)], null))).MergedRemoteLines);
        Assert.False((await QtyAsync(a.Id)).ContainsKey(banh));
    }

    [Fact]
    public async Task Removing_a_known_item_still_removes_it_while_keeping_remote_items()
    {
        if (NoDb) return;
        var (store, tra, banh, com) = await SetupAsync();
        var a = await DraftAsync(store, L(tra, 1), L(com, 1));
        await RemoteAddAsync(store, a.Id, banh, 1);
        await using (var db = Fx.NewDb())
            Data(await Sales(db, store).UpdateSale(a.Id, Save([L(com, 1)], Base(a))));
        var q = await QtyAsync(a.Id);
        Assert.False(q.ContainsKey(tra));
        Assert.Equal(1, q[com]);
        Assert.Equal(1, q[banh]);
    }

    [Fact]
    public async Task Both_devices_adding_the_same_item_add_up()
    {
        if (NoDb) return;
        var (store, tra, _, _) = await SetupAsync();
        var a = await DraftAsync(store, L(tra, 1));
        await RemoteAddAsync(store, a.Id, tra, 2);   // máy khác: Trà 1 → 3
        await using (var db = Fx.NewDb())
            Data(await Sales(db, store).UpdateSale(a.Id, Save([L(tra, 2)], Base(a))));   // máy A: 1 → 2
        Assert.Equal(4, (await QtyAsync(a.Id))[tra]);
    }

    [Fact]
    public async Task Resending_a_save_whose_response_was_lost_does_not_double_items()
    {
        if (NoDb) return;
        var (store, tra, _, com) = await SetupAsync();
        var a = await DraftAsync(store, L(tra, 1));
        await using (var db = Fx.NewDb())
            Data(await Sales(db, store).UpdateSale(a.Id, Save([L(tra, 1), L(com, 2)], Base(a))));
        // Mất phản hồi → máy gửi lại cùng giỏ, nền vẫn là bản cũ.
        await using (var db = Fx.NewDb())
            Assert.Equal(0, Data(await Sales(db, store).UpdateSale(a.Id, Save([L(tra, 1), L(com, 2)], Base(a)))).MergedRemoteLines);
        var q = await QtyAsync(a.Id);
        Assert.Equal(1, q[tra]);
        Assert.Equal(2, q[com]);
    }

    [Fact]
    public async Task Paying_from_a_stale_cart_is_refused_and_returns_the_current_order()
    {
        if (NoDb) return;
        var (store, tra, banh, _) = await SetupAsync();
        var a = await DraftAsync(store, L(tra, 1));
        await RemoteAddAsync(store, a.Id, banh, 1);
        await using (var db = Fx.NewDb())
        {
            var r = await Sales(db, store).UpdateSale(a.Id, Save([L(tra, 1)], Base(a), complete: true));
            Assert.IsType<ConflictObjectResult>(r.Result);
            Assert.Equal(PosSalesController.StaleCartBeforePayMessage, Error(r));
            var fresh = ((AppResponse<PosSalesController.SaleOrderDto>)((ConflictObjectResult)r.Result!).Value!).Data!;
            Assert.Equal(2, fresh.Lines.Count);
        }
        await using (var db = Fx.NewDb())
            Assert.Equal(PosSaleOrderStatus.Draft, (await db.PosSaleOrders.SingleAsync(o => o.Id == a.Id)).Status);
        Assert.Equal(100, await OnHandAsync(tra));
    }

    [Fact]
    public async Task Saving_a_40_line_table_stays_fast()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var products = new List<Guid>();
        for (var i = 0; i < 41; i++)
            products.Add((await Fx.AddProductAsync(store, $"Món {i}", PosProductType.Goods, 100, 4000, 10000)).Id);
        var a = await DraftAsync(store, [.. products.Take(40).Select(p => L(p, 1))]);

        var times = new List<long>();
        var current = a;
        for (var round = 0; round < 5; round++)
        {
            var lines = products.Take(40).Select(p => L(p, 1)).ToList();
            lines.Add(L(products[40], round + 1));
            await using var db = Fx.NewDb();
            var sw = Stopwatch.StartNew();
            current = Data(await Sales(db, store).UpdateSale(a.Id, Save(lines, Base(current))));
            times.Add(sw.ElapsedMilliseconds);
        }
        File.WriteAllText(Path.Combine(Path.GetTempPath(), "sbox-draft-save-timing.txt"),
            "40-41 dòng, ms mỗi lần lưu: " + string.Join(", ", times));
        Assert.Equal(41, current.Lines.Count);
        Assert.True(times.Skip(1).Max() < 3000, string.Join(", ", times));
    }
}
