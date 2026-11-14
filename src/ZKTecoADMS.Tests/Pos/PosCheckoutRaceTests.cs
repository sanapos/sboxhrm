using System.Data.Common;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>
/// Đơn bị giao dịch khác ghi xong đúng khe giữa lúc máy chủ nạp đơn và lúc ghi: thanh toán không bỏ sót món
/// khách vừa gọi thêm, dọn ô hóa đơn trống không xóa đơn vừa có món.
/// </summary>
[Collection("pos-pg")]
public class PosCheckoutRaceTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    /// <summary>Chạy <paramref name="action"/> một lần, ngay trước lệnh UPDATE đầu tiên lên bảng đơn.</summary>
    sealed class BeforeFirstOrderUpdate(Func<Task> action) : DbCommandInterceptor
    {
        int _fired;

        public override async ValueTask<InterceptionResult<int>> NonQueryExecutingAsync(
            DbCommand command, CommandEventData eventData, InterceptionResult<int> result,
            CancellationToken cancellationToken = default)
        {
            if (command.CommandText.Contains("UPDATE \"PosSaleOrders\"") && Interlocked.Exchange(ref _fired, 1) == 0)
                await action();
            return result;
        }

        public bool Fired => _fired == 1;
    }

    ZKTecoDbContext DbWith(DbCommandInterceptor interceptor) => new(new DbContextOptionsBuilder<ZKTecoDbContext>()
        .UseNpgsql(Fx.ConnectionString!)
        .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking)
        .AddInterceptors(interceptor)
        .Options);

    static PosSalesController.SaleLineDto L(Guid p, decimal qty) => new(p, qty, null, 10000, null);

    static List<PosSalesController.BaseLineDto> Base(PosSalesController.SaleOrderDto o) =>
        [.. o.Lines.Select(l => new PosSalesController.BaseLineDto(l.Id, l.ProductId, l.VariantId, null, null, l.Qty))];

    static PosSalesController.UpdateSaleDto Pay(List<PosSalesController.SaleLineDto> lines,
        List<PosSalesController.BaseLineDto>? baseLines) =>
        new(lines, 0, lines.Sum(l => l.Qty * 10000), "Tiền mặt", null, null, null,
            Complete: true, BaseLines: baseLines);

    async Task<PosSalesController.SaleOrderDto> DraftAsync(Guid store, params PosSalesController.SaleLineDto[] lines)
    {
        await using var db = Fx.NewDb();
        return Data(await Sales(db, store).CreateSale(new PosSalesController.CreateSaleDto(
            [.. lines], 0, 0, "Tiền mặt", null, null, null, Complete: false)));
    }

    /// <summary>Khách gọi thêm qua QR / máy khác thêm món thẳng vào đơn (đã báo bếp), tăng phiên bản đơn.</summary>
    async Task RemoteAddAsync(Guid store, Guid orderId, Guid product, decimal qty)
    {
        await using var db = Fx.NewDb();
        db.PosSaleOrderLines.Add(new PosSaleOrderLine
        {
            Id = Guid.NewGuid(), StoreId = store, SaleOrderId = orderId, ProductId = product,
            ProductName = "remote", Qty = qty, UnitPrice = 10000, LineTotal = qty * 10000,
            KitchenSentQty = qty, KitchenSentAt = DateTime.UtcNow,
        });
        await db.SaveChangesAsync();
        await db.PosSaleOrders.Where(o => o.Id == orderId)
            .ExecuteUpdateAsync(s => s.SetProperty(o => o.LockVersion, o => o.LockVersion + 1));
    }

    [Fact]
    public async Task Thanh_toan_dung_luc_khach_goi_them_khong_bo_sot_mon_tren_hoa_don()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var tra = (await Fx.AddProductAsync(store, "Trà", PosProductType.Goods, 100, 4000, 10000)).Id;
        var banh = (await Fx.AddProductAsync(store, "Bánh", PosProductType.Goods, 100, 4000, 10000)).Id;
        var a = await DraftAsync(store, L(tra, 2));

        // Món «Bánh» vào đơn sau khi máy chủ đã nạp đơn để thanh toán, ngay trước lệnh nhận đơn.
        var hook = new BeforeFirstOrderUpdate(() => RemoteAddAsync(store, a.Id, banh, 1));
        ActionResult<Application.Models.AppResponse<PosSalesController.SaleOrderDto>> r;
        await using (var db = DbWith(hook))
            r = await Sales(db, store).UpdateSale(a.Id, Pay([L(tra, 2)], Base(a)));

        Assert.True(hook.Fired);
        // Không thu tiền theo giỏ cũ: báo máy bán nạp lại giỏ (có món mới) rồi thanh toán lại.
        Assert.IsType<ConflictObjectResult>(r.Result);
        Assert.Contains(PosSalesController.StaleCartBeforePayMessage, Error(r));
        Assert.Equal(PosSaleOrderStatus.Draft, (await OrderAsync(a.Id)).Status);
        await using (var db = Fx.NewDb())
            Assert.Equal(2, await db.PosSaleOrderLines.CountAsync(l => l.SaleOrderId == a.Id && l.Deleted == null));
        Assert.Equal(100, await OnHandAsync(tra));

        // Máy bán nạp lại giỏ đủ 2 món → thanh toán được, cả hai món vào tổng và trừ kho.
        PosSalesController.SaleOrderDto fresh;
        await using (var db = Fx.NewDb())
            fresh = Data(await Sales(db, store).GetSale(a.Id));
        PosSalesController.SaleOrderDto paid;
        await using (var db = Fx.NewDb())
            paid = Data(await Sales(db, store).UpdateSale(a.Id, Pay([L(tra, 2), L(banh, 1)], Base(fresh))));
        Assert.Equal("Completed", paid.Status);
        Assert.Equal(30000m, paid.Total);
        Assert.Equal(98, await OnHandAsync(tra));
        Assert.Equal(99, await OnHandAsync(banh));
    }

    [Fact]
    public async Task Thanh_toan_khong_bi_chan_khi_don_chi_doi_phien_ban_ma_khong_doi_mon()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var tra = (await Fx.AddProductAsync(store, "Trà", PosProductType.Goods, 100, 4000, 10000)).Id;
        var a = await DraftAsync(store, L(tra, 2));

        // Báo bếp / tự lưu của chính máy này vừa xong: phiên bản đổi, món không đổi.
        var hook = new BeforeFirstOrderUpdate(async () =>
        {
            await using var other = Fx.NewDb();
            await other.PosSaleOrders.Where(o => o.Id == a.Id)
                .ExecuteUpdateAsync(s => s.SetProperty(o => o.LockVersion, o => o.LockVersion + 1));
        });
        PosSalesController.SaleOrderDto paid;
        await using (var db = DbWith(hook))
            paid = Data(await Sales(db, store).UpdateSale(a.Id, Pay([L(tra, 2)], Base(a))));

        Assert.True(hook.Fired);
        Assert.Equal("Completed", paid.Status);
        Assert.Equal(20000m, paid.Total);
        Assert.Equal(98, await OnHandAsync(tra));
        await using (var check = Fx.NewDb())
            Assert.Equal(1, await check.PosSaleOrderLines.CountAsync(l => l.SaleOrderId == a.Id && l.Deleted == null));
    }

    /// <summary>Thêm một ô hóa đơn nháp trống (tạo từ 10 phút trước) bằng cách chép ô sẵn có.</summary>
    async Task<Guid> AddEmptySlotAsync(Guid store, int slot)
    {
        await using var db = Fx.NewDb();
        var o = await db.PosSaleOrders.FirstAsync(x => x.StoreId == store && x.Deleted == null
            && x.Status == PosSaleOrderStatus.Draft && x.InvoiceSlot != null);
        o.Id = Guid.NewGuid();
        o.InvoiceSlot = slot;
        o.OrderNo = "TMPX" + slot;
        o.ClientRequestId = null;
        o.CreatedAt = DateTime.UtcNow.AddMinutes(-10);
        db.PosSaleOrders.Add(o);
        await db.SaveChangesAsync();
        return o.Id;
    }

    [Fact]
    public async Task Don_o_hoa_don_trong_thua_van_xoa_o_trong_va_giu_o_co_mon()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var tra = (await Fx.AddProductAsync(store, "Trà", PosProductType.Goods, 100, 4000, 10000)).Id;
        await using (var db = Fx.NewDb())
            await Sales(db, store).GetInvoiceSlots(pruneEmpty: true);
        var withLine = await AddEmptySlotAsync(store, 4);
        await RemoteAddAsync(store, withLine, tra, 1);
        var empty = await AddEmptySlotAsync(store, 5);

        await using (var db = Fx.NewDb())
            await Sales(db, store).GetInvoiceSlots(pruneEmpty: true);

        await using var check = Fx.NewDb();
        Assert.NotNull(await check.PosSaleOrders.IgnoreQueryFilters().Where(o => o.Id == empty)
            .Select(o => o.Deleted).FirstAsync());
        Assert.Null(await check.PosSaleOrders.IgnoreQueryFilters().Where(o => o.Id == withLine)
            .Select(o => o.Deleted).FirstAsync());
    }

    [Fact]
    public async Task Don_o_hoa_don_trong_khong_xoa_don_vua_duoc_may_khac_them_mon()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var tra = (await Fx.AddProductAsync(store, "Trà", PosProductType.Goods, 100, 4000, 10000)).Id;
        await using (var db = Fx.NewDb())
            await Sales(db, store).GetInvoiceSlots(pruneEmpty: true);
        // Hai ô trống cũ: bước dọn sẽ chọn xóa cả hai (ô cũ trước).
        var slot5 = await AddEmptySlotAsync(store, 5);
        var slot6 = await AddEmptySlotAsync(store, 6);

        // Máy khác lưu món đầu tiên vào cả hai ô sau khi bước dọn đã nạp danh sách, ngay trước lệnh xóa.
        var hook = new BeforeFirstOrderUpdate(async () =>
        {
            await RemoteAddAsync(store, slot5, tra, 1);
            await RemoteAddAsync(store, slot6, tra, 1);
        });
        await using (var db = DbWith(hook))
            await Sales(db, store).GetInvoiceSlots(pruneEmpty: true);

        Assert.True(hook.Fired);
        await using var check = Fx.NewDb();
        foreach (var id in new[] { slot5, slot6 })
        {
            Assert.Null(await check.PosSaleOrders.IgnoreQueryFilters().Where(o => o.Id == id)
                .Select(o => o.Deleted).FirstAsync());
            Assert.Equal(1, await check.PosSaleOrderLines.CountAsync(l => l.SaleOrderId == id && l.Deleted == null));
        }
    }

    /// <summary>Chạy <paramref name="action"/> một lần, ngay trước lệnh đầu tiên có chứa <paramref name="marker"/>.</summary>
    sealed class BeforeFirst(string marker, Func<Task> action) : DbCommandInterceptor
    {
        int _fired;
        public bool Fired => _fired == 1;

        async ValueTask RunAsync(DbCommand command)
        {
            if (command.CommandText.Contains(marker) && Interlocked.Exchange(ref _fired, 1) == 0)
                await action();
        }

        public override async ValueTask<InterceptionResult<int>> NonQueryExecutingAsync(
            DbCommand command, CommandEventData eventData, InterceptionResult<int> result,
            CancellationToken cancellationToken = default)
        {
            await RunAsync(command);
            return result;
        }

        public override async ValueTask<InterceptionResult<DbDataReader>> ReaderExecutingAsync(
            DbCommand command, CommandEventData eventData, InterceptionResult<DbDataReader> result,
            CancellationToken cancellationToken = default)
        {
            await RunAsync(command);
            return result;
        }
    }

    [Fact]
    public async Task Hai_quay_thanh_toan_chong_nhau_deu_thanh_cong_voi_so_hoa_don_khac_nhau()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var tra = (await Fx.AddProductAsync(store, "Trà", PosProductType.Goods, 100, 4000, 10000)).Id;
        var banh = (await Fx.AddProductAsync(store, "Bánh", PosProductType.Goods, 100, 4000, 10000)).Id;

        // Quầy B lưu xong một hóa đơn đúng lúc quầy A (đã cấp số trong giao dịch của mình) sắp ghi đơn:
        // hai quầy cùng số hóa đơn, cùng mã phiếu thu.
        PosSalesController.SaleOrderDto? other = null;
        var hook = new BeforeFirst("INSERT INTO \"PosSaleOrders\"",
            async () => other = await SellAsync(store, (banh, 1m, 10000m, null)));
        PosSalesController.SaleOrderDto mine;
        await using (var db = DbWith(hook))
            mine = Data(await Sales(db, store).CreateSale(new PosSalesController.CreateSaleDto(
                [L(tra, 2)], 0, 20000, "Tiền mặt", null, null, null)));

        Assert.True(hook.Fired);
        Assert.NotNull(other);
        Assert.Equal("Completed", mine.Status);
        Assert.Equal("Completed", other!.Status);
        Assert.NotEqual(other.OrderNo, mine.OrderNo);
        Assert.Equal(98, await OnHandAsync(tra));
        Assert.Equal(99, await OnHandAsync(banh));
        await using var check = Fx.NewDb();
        Assert.Equal(2, await check.PosSaleOrders.CountAsync(o => o.StoreId == store
            && o.Deleted == null && o.Status == PosSaleOrderStatus.Completed));
    }

    [Fact]
    public async Task Hoan_tat_don_dung_luc_khach_goi_them_thi_tinh_ca_mon_moi()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var tra = (await Fx.AddProductAsync(store, "Trà", PosProductType.Goods, 100, 4000, 10000)).Id;
        var banh = (await Fx.AddProductAsync(store, "Bánh", PosProductType.Goods, 100, 4000, 10000)).Id;
        var a = await DraftAsync(store, L(tra, 2));

        var hook = new BeforeFirstOrderUpdate(() => RemoteAddAsync(store, a.Id, banh, 1));
        PosSalesController.SaleOrderDto done;
        await using (var db = DbWith(hook))
            done = Data(await Sales(db, store).CompleteSale(a.Id, new PosSalesController.CompleteSaleDto()));

        Assert.True(hook.Fired);
        Assert.Equal("Completed", done.Status);
        // Món khách vừa gọi thêm cũng được trừ kho — không nằm «treo» trên hóa đơn.
        Assert.Equal(98, await OnHandAsync(tra));
        Assert.Equal(99, await OnHandAsync(banh));
    }

    [Fact]
    public async Task Tien_ve_dung_luc_khach_goi_them_thi_khong_tu_hoan_tat_don()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var tra = (await Fx.AddProductAsync(store, "Trà", PosProductType.Goods, 100, 4000, 10000)).Id;
        var banh = (await Fx.AddProductAsync(store, "Bánh", PosProductType.Goods, 100, 4000, 10000)).Id;
        var a = await DraftAsync(store, L(tra, 2));

        var hook = new BeforeFirstOrderUpdate(() => RemoteAddAsync(store, a.Id, banh, 1));
        await using (var db = DbWith(hook))
        {
            var order = await db.PosSaleOrders.AsTracking().Include(o => o.Lines).FirstAsync(o => o.Id == a.Id);
            var (ok, err) = await ZKTecoADMS.Api.Services.PosOnlineOrderHelper.TryCompletePaidDraftAsync(
                db, store, order, "tingee-webhook", "Tingee", 20000, closeTableSession: false);

            Assert.True(hook.Fired);
            Assert.False(ok);
            Assert.NotNull(err);
            // Đơn trong bộ nhớ trở về như lúc nạp: lần lưu sau của nơi gọi không ghi nhầm «đã hoàn tất».
            Assert.Equal(PosSaleOrderStatus.Draft, order.Status);
            Assert.Equal(EntityState.Unchanged, db.Entry(order).State);
            await db.SaveChangesAsync();
        }
        Assert.Equal(PosSaleOrderStatus.Draft, (await OrderAsync(a.Id)).Status);
        Assert.Equal(100, await OnHandAsync(tra));
        await using var check = Fx.NewDb();
        Assert.Equal(2, await check.PosSaleOrderLines.CountAsync(l => l.SaleOrderId == a.Id && l.Deleted == null));
    }

    [Fact]
    public async Task Tien_ve_khi_don_khong_doi_thi_van_tu_hoan_tat()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var tra = (await Fx.AddProductAsync(store, "Trà", PosProductType.Goods, 100, 4000, 10000)).Id;
        var a = await DraftAsync(store, L(tra, 2));

        await using (var db = Fx.NewDb())
        {
            var order = await db.PosSaleOrders.AsTracking().Include(o => o.Lines).FirstAsync(o => o.Id == a.Id);
            var (ok, err) = await ZKTecoADMS.Api.Services.PosOnlineOrderHelper.TryCompletePaidDraftAsync(
                db, store, order, "tingee-webhook", "Tingee", 20000, closeTableSession: false);
            Assert.True(ok, err);
        }
        Assert.Equal(PosSaleOrderStatus.Completed, (await OrderAsync(a.Id)).Status);
        Assert.Equal(98, await OnHandAsync(tra));
    }

    async Task<Guid> SlotOrderAsync(Guid store, int slot)
    {
        await using var db = Fx.NewDb();
        return await db.PosSaleOrders.Where(o => o.StoreId == store && o.Deleted == null
                && o.Status == PosSaleOrderStatus.Draft && o.InvoiceSlot == slot)
            .Select(o => o.Id).FirstAsync();
    }

    [Fact]
    public async Task Dong_o_hoa_don_khong_xoa_mon_may_khac_vua_them()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var tra = (await Fx.AddProductAsync(store, "Trà", PosProductType.Goods, 100, 4000, 10000)).Id;
        await using (var db = Fx.NewDb())
            await Sales(db, store).GetInvoiceSlots(pruneEmpty: true);
        var slot2 = await SlotOrderAsync(store, 2);
        var slot3 = await SlotOrderAsync(store, 3);

        // Máy khác thêm món vào ô 2 sau khi máy chủ đã nạp ô này để đóng.
        var hook = new BeforeFirstOrderUpdate(() => RemoteAddAsync(store, slot2, tra, 1));
        await using (var db = DbWith(hook))
        {
            var r = await Sales(db, store).RemoveInvoiceSlot(2, force: true);
            Assert.IsType<ConflictObjectResult>(r.Result);
        }
        Assert.True(hook.Fired);
        await using (var check = Fx.NewDb())
        {
            Assert.Null(await check.PosSaleOrders.IgnoreQueryFilters().Where(o => o.Id == slot2)
                .Select(o => o.Deleted).FirstAsync());
            Assert.Equal(1, await check.PosSaleOrderLines.CountAsync(l => l.SaleOrderId == slot2 && l.Deleted == null));
        }

        // Ô không ai đụng tới vẫn đóng được như cũ.
        await using (var db = Fx.NewDb())
            Assert.IsType<OkObjectResult>((await Sales(db, store).RemoveInvoiceSlot(3, force: true)).Result);
        await using (var check = Fx.NewDb())
            Assert.NotNull(await check.PosSaleOrders.IgnoreQueryFilters().Where(o => o.Id == slot3)
                .Select(o => o.Deleted).FirstAsync());
    }
}
