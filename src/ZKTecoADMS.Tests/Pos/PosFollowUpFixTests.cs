using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Api.Services.PaymentGateway;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Mã đối soát chuyển khoản riêng cho từng đơn và cách tìm mã trong nội dung chuyển khoản.</summary>
public class PosTransferCodeTests
{
    sealed record Waiting(string Name, string? Code, string? OrderNo);

    static Waiting? Pick(string content, params Waiting[] waiting) =>
        PosTransferCode.PickByContent(content, waiting, w => [w.Code, w.OrderNo]);

    [Fact]
    public void Ma_gom_so_don_va_bon_ky_tu_dau_cua_ma_dinh_danh_don()
    {
        var id = Guid.Parse("a3f9c0de-1111-2222-3333-444444444444");
        Assert.Equal("TMP05A3F9", PosTransferCode.For("TMP05", id));
        // Hai đơn khác nhau cùng ô hóa đơn (cùng số TMP05) có mã khác nhau.
        Assert.NotEqual(PosTransferCode.For("TMP05", id),
            PosTransferCode.For("TMP05", Guid.Parse("0b7e0000-1111-2222-3333-444444444444")));
        // Chưa có mã định danh đơn → giữ nguyên số đơn (app cũ).
        Assert.Equal("TMP05", PosTransferCode.For("TMP05", null));
    }

    [Fact]
    public void Tim_ma_khi_ngan_hang_chen_tien_to_va_dau_cham()
    {
        var a = new Waiting("A", "TMP05A3F9", "TMP05");
        var b = new Waiting("B", "TMP070B7E", "TMP07");
        Assert.Same(a, Pick("MBVCB.7745123.TMP05A3F9.CT tu 0123456789 NGUYEN VAN A", a, b));
        Assert.Same(b, Pick("tmp070b7e chuyen tien", a, b));
        // Ngân hàng bỏ hết dấu cách: mã đủ dài vẫn nhận ra.
        Assert.Same(a, Pick("QRTMP05A3F9THANHTOAN", a, b));
    }

    [Fact]
    public void Don_moi_cung_o_khong_bi_khop_nham_boi_ma_cua_don_cu()
    {
        // Lệnh cũ (app đời trước, mã = số đơn nháp) còn treo; đơn mới cùng ô có mã riêng.
        var old = new Waiting("old", "TMP05", "TMP05");
        var fresh = new Waiting("new", "TMP05A3F9", null);
        Assert.Same(fresh, Pick("TMP05A3F9", old, fresh));
        // Nội dung chỉ có số đơn nháp trần → chỉ khớp lệnh cũ, không khớp đơn mới.
        Assert.Same(old, Pick("TMP05 chuyen khoan", old, fresh));
    }

    [Fact]
    public void Khong_co_ma_hoac_hai_lenh_cung_khop_thi_khong_doan()
    {
        var a = new Waiting("A", "TMP05A3F9", null);
        var twin = new Waiting("twin", "TMP05A3F9", null);
        Assert.Null(Pick("Chuyen tien an trua 150000", a));
        Assert.Null(Pick("TMP05A3F9", a, twin));
        Assert.Null(Pick("", a));
    }
}

/// <summary>Nháp thứ hai trên bàn, đơn offline của bàn đã thanh toán ở nơi khác, đóng ca.</summary>
[Collection("pos-pg")]
public class PosFollowUpFixTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    static PosSalesController.SaleLineDto L(Guid p, decimal qty) => new(p, qty, null, 10000, null);

    async Task<Guid> NewTableAsync(Guid store)
    {
        var area = Guid.NewGuid();
        var table = Guid.NewGuid();
        await using var db = Fx.NewDb();
        db.PosServiceAreas.Add(new PosServiceArea { Id = area, StoreId = store, Name = "Tầng 1" });
        db.PosServiceResources.Add(new PosServiceResource { Id = table, StoreId = store, AreaId = area, Code = "B5", Name = "Bàn 5" });
        await db.SaveChangesAsync();
        return table;
    }

    async Task<Guid> TableDraftAsync(Guid store, Guid table, string requestId, params PosSalesController.SaleLineDto[] lines)
    {
        await using var db = Fx.NewDb();
        return Data(await Sales(db, store).CreateSale(new PosSalesController.CreateSaleDto(
            [.. lines], 0, 0, "Tiền mặt", null, null, null,
            Complete: false, ServiceResourceId: table, ClientRequestId: requestId))).Id;
    }

    [Fact]
    public async Task Tra_don_chinh_thi_nhap_thu_hai_con_mon_duoc_giu_lam_bill_tach()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var p = (await Fx.AddProductAsync(store, "Lẩu", PosProductType.Goods, 100, 4000, 10000)).Id;
        var table = await NewTableAsync(store);
        var mainId = await TableDraftAsync(store, table, "req-main-keep1", L(p, 2));
        await using (var db = Fx.NewDb())
        {
            db.PosResourceSessions.Add(new PosResourceSession
            {
                Id = Guid.NewGuid(), StoreId = store, ResourceId = table, SaleOrderId = mainId,
                StartedAt = DateTime.UtcNow.AddMinutes(-15), Status = PosResourceSessionStatus.Open,
            });
            await db.SaveChangesAsync();
        }
        // Đơn nháp thứ hai của cùng bàn (không phải bill tách): giỏ mở lúc mất mạng trùng bàn.
        var secondId = await TableDraftAsync(store, table, "req-second-keep1", L(p, 3));

        await using (var db = Fx.NewDb())
            Data(await Sales(db, store).CompleteSale(mainId, new PosSalesController.CompleteSaleDto()));

        await using var check = Fx.NewDb();
        var second = await check.PosSaleOrders.IgnoreQueryFilters().SingleAsync(o => o.Id == secondId);
        Assert.Null(second.Deleted);
        Assert.Equal(PosSaleOrderStatus.Draft, second.Status);
        Assert.Equal(mainId, second.SplitFromOrderId);
        Assert.Equal(table, second.ServiceResourceId);
        Assert.Equal(1, await check.PosSaleOrderLines.CountAsync(l => l.SaleOrderId == secondId && l.Deleted == null));
        Assert.Equal(PosSaleOrderStatus.Completed, (await check.PosSaleOrders.SingleAsync(o => o.Id == mainId)).Status);

        // Bill giữ lại vẫn thanh toán được như một bill tách.
        await using (var db = Fx.NewDb())
            Assert.Equal("Completed",
                Data(await Sales(db, store).CompleteSale(secondId, new PosSalesController.CompleteSaleDto())).Status);
        Assert.Equal(95, await OnHandAsync(p));
    }

    [Fact]
    public async Task Don_offline_cua_ban_da_thanh_toan_noi_khac_duoc_gan_so_offline_va_khong_tao_don_moi()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var p = (await Fx.AddProductAsync(store, "Trà", PosProductType.Goods, 100, 4000, 10000)).Id;
        Guid id;
        await using (var db = Fx.NewDb())
            id = Data(await Sales(db, store).CreateSale(new PosSalesController.CreateSaleDto(
                [L(p, 2)], 0, 0, "Tiền mặt", null, null, null, Complete: false))).Id;
        // Máy khác (còn mạng) đã thanh toán đơn này.
        await using (var db = Fx.NewDb())
            Data(await Sales(db, store).CompleteSale(id, new PosSalesController.CompleteSaleDto()));

        // Máy mất mạng cũng đã thu tiền, in hóa đơn OFF-000012; có mạng lại thì gửi lên.
        var offlineNo = PosOfflineSaleRules.Format(12);
        var offline = new PosSalesController.UpdateSaleDto(
            [L(p, 2)], 0, 20000, "Tiền mặt", null, null, null, Complete: true,
            OfflineNo: offlineNo, OfflineAt: DateTime.UtcNow.AddMinutes(-40), OfflineDeviceKey: "a:test-device");
        await using (var db = Fx.NewDb())
        {
            var r = Data(await Sales(db, store).UpdateSale(id, offline));
            Assert.True(r.AlreadyCompleted);
            Assert.Equal(id, r.Id);
        }

        await using (var check = Fx.NewDb())
        {
            var order = await check.PosSaleOrders.SingleAsync(o => o.Id == id);
            Assert.Equal(offlineNo, order.OfflineNo);
            Assert.Equal("a:test-device", order.OfflineDeviceKey);
            // Không có đơn thứ hai, kho chỉ trừ một lần.
            Assert.Equal(1, await check.PosSaleOrders.CountAsync(o => o.StoreId == store
                && o.Deleted == null && o.Status == PosSaleOrderStatus.Completed));
        }
        Assert.Equal(98, await OnHandAsync(p));

        // Gửi lại lần nữa (mất phản hồi) vẫn êm.
        await using (var db = Fx.NewDb())
            Assert.True(Data(await Sales(db, store).UpdateSale(id, offline)).AlreadyCompleted);
    }

    [Fact]
    public async Task Dong_ca_hai_lan_thi_lan_sau_bi_tu_choi()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        await using (var db = Fx.NewDb())
        {
            db.PosStoreSellSettings.Add(new PosStoreSellSettings { Id = Guid.NewGuid(), StoreId = store, EnableCashierShift = true, IsActive = true });
            await db.SaveChangesAsync();
        }
        await using (var db = Fx.NewDb())
            Data(await PosPgFixture.As(new PosCashierShiftsController(db), store)
                .Open(new PosCashierShiftsController.OpenShiftDto { OpeningCash = 100000 }));
        Guid shiftId;
        await using (var db = Fx.NewDb())
            shiftId = await db.PosCashierShifts.Where(s => s.StoreId == store).Select(s => s.Id).SingleAsync();

        // Hai máy cùng nạp ca đang mở rồi cùng bấm đóng.
        await using var db1 = Fx.NewDb();
        await using var db2 = Fx.NewDb();
        var r1 = await PosPgFixture.As(new PosCashierShiftsController(db1), store)
            .Close(shiftId, new PosCashierShiftsController.CloseShiftDto { CountedCash = 100000 });
        var r2 = await PosPgFixture.As(new PosCashierShiftsController(db2), store)
            .Close(shiftId, new PosCashierShiftsController.CloseShiftDto { CountedCash = 90000 });

        Assert.IsType<OkObjectResult>(r1.Result);
        Assert.IsType<BadRequestObjectResult>(r2.Result);
        await using var check = Fx.NewDb();
        var shift = await check.PosCashierShifts.SingleAsync(s => s.Id == shiftId);
        Assert.Equal("Closed", shift.Status);
        Assert.Equal(100000m, shift.CountedCash);
        Assert.Equal(100000m, shift.ExpectedCash);
    }
}
