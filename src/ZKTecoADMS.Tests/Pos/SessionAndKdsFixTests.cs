using System.IdentityModel.Tokens.Jwt;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Settings;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure.Services.Auth;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Mã làm mới phải sống lâu hơn mã truy cập — nếu không máy bị văng ra màn đăng nhập mỗi ngày.</summary>
public class RefreshTokenLifetimeTests
{
    static JwtSettings Settings(double access, double refresh) => new()
    {
        AccessTokenSecret = new string('a', 48),
        RefreshTokenSecret = new string('r', 48),
        AccessTokenExpirationMinutes = access,
        RefreshTokenExpirationMinutes = refresh,
        Issuer = "test-issuer",
        Audience = "test-audience",
    };

    [Theory]
    // Cấu hình đang chạy: truy cập 1.500 phút, làm mới 120 phút → 30 ngày.
    [InlineData(1500, 120, 43200)]
    [InlineData(1500, 1500, 43200)]
    // Cấu hình đúng (làm mới dài hơn truy cập) thì giữ nguyên.
    [InlineData(60, 120, 120)]
    [InlineData(1500, 43200, 43200)]
    // Mã truy cập rất dài → mã làm mới gấp đôi.
    [InlineData(30000, 120, 60000)]
    public void Han_ma_lam_moi_luon_dai_hon_ma_truy_cap(double access, double refresh, double expected)
    {
        var actual = RefreshTokenService.EffectiveRefreshMinutes(access, refresh);
        Assert.Equal(expected, actual);
        Assert.True(actual > access);
    }

    [Fact]
    public async Task Ma_lam_moi_cap_ra_con_hieu_luc_sau_khi_ma_truy_cap_het_han()
    {
        var settings = Settings(access: 1500, refresh: 120);
        var generator = new TokenGeneratorService(settings, NullLogger<TokenGeneratorService>.Instance);
        var service = new RefreshTokenService(generator, settings, NullLogger<RefreshTokenService>.Instance);

        var token = await service.GetTokenAsync(new ApplicationUser());

        Assert.True(service.Validate(token));
        var expires = new JwtSecurityTokenHandler().ReadJwtToken(token).ValidTo;
        // Lúc mã truy cập hết hạn (sau 1.500 phút) mã làm mới phải còn sống.
        Assert.True(expires > DateTime.UtcNow.AddMinutes(1500 + 60));
        Assert.InRange((expires - DateTime.UtcNow).TotalDays, 29.9, 30.1);
    }
}

/// <summary>Màn bếp bấm «Xong»: chỉ đóng phần bếp đã thấy, phần vừa gọi thêm nằm lại.</summary>
public class KdsDoneSeenQtyTests
{
    static PosSaleOrderLine Line(decimal sent, decimal done = 0) => new()
    {
        Id = Guid.NewGuid(), Qty = sent, KitchenSentQty = sent, KitchenDoneQty = done,
        KitchenPrepStatus = PosKitchenKdsHelper.Queued,
    };

    [Fact]
    public void Xong_khi_man_bep_thay_it_hon_so_da_bao_thi_giu_lai_phan_moi()
    {
        // Bếp thấy x2, thu ngân vừa báo thêm thành x3, bếp bấm Xong trước khi màn tải lại.
        var line = Line(sent: 3);
        PosKitchenKdsHelper.ApplyStatus(line, PosKitchenKdsHelper.Done, seenSentQty: 2);
        Assert.Equal(2, line.KitchenDoneQty);
        Assert.Equal(1, PosKitchenKdsHelper.OpenQty(line));
        Assert.Equal(PosKitchenKdsHelper.Queued, line.KitchenPrepStatus);

        // Màn tải lại, thấy đủ x3 → bấm Xong đóng nốt.
        PosKitchenKdsHelper.ApplyStatus(line, PosKitchenKdsHelper.Done, seenSentQty: 3);
        Assert.Equal(3, line.KitchenDoneQty);
        Assert.Equal(PosKitchenKdsHelper.Done, line.KitchenPrepStatus);
    }

    [Fact]
    public void Xong_ca_ve_cung_chi_dong_phan_da_thay()
    {
        var line = Line(sent: 3);
        PosKitchenKdsHelper.Bump(line, seenSentQty: 2);
        Assert.Equal(2, line.KitchenDoneQty);
        Assert.Equal(PosKitchenKdsHelper.Queued, line.KitchenPrepStatus);
    }

    [Fact]
    public void App_cu_khong_gui_so_da_thay_thi_dong_het_nhu_truoc()
    {
        var a = Line(sent: 3);
        PosKitchenKdsHelper.ApplyStatus(a, PosKitchenKdsHelper.Done);
        Assert.Equal(3, a.KitchenDoneQty);
        Assert.Equal(PosKitchenKdsHelper.Done, a.KitchenPrepStatus);

        var b = Line(sent: 3);
        PosKitchenKdsHelper.Bump(b);
        Assert.Equal(3, b.KitchenDoneQty);
        Assert.Equal(PosKitchenKdsHelper.Done, b.KitchenPrepStatus);
    }

    [Fact]
    public void So_da_thay_khong_lam_giam_phan_da_xong_truoc_do()
    {
        var line = Line(sent: 5, done: 3);
        PosKitchenKdsHelper.ApplyStatus(line, PosKitchenKdsHelper.Done, seenSentQty: 2);
        Assert.Equal(3, line.KitchenDoneQty);
        Assert.Equal(2, PosKitchenKdsHelper.OpenQty(line));
    }
}

/// <summary>Vé bếp khi thanh toán: đơn có bàn đóng như cũ, đơn không gắn bàn (tại quầy, online) giữ tới khi bếp bấm Xong.</summary>
public class KdsTicketOnPaidTests
{
    static PosSaleOrderLine Sent(decimal qty) => new()
    {
        Id = Guid.NewGuid(), Qty = qty, KitchenSentQty = qty, KitchenDoneQty = 0,
    };

    [Fact]
    public void Don_tai_quay_thanh_toan_xong_van_con_ve_tren_man_bep()
    {
        var order = new PosSaleOrder { Id = Guid.NewGuid() };
        var line = Sent(2);
        PosKitchenKdsHelper.OnOrderPaid(order, [line]);
        Assert.Equal(0, line.KitchenDoneQty);
        Assert.Equal(2, PosKitchenKdsHelper.OpenQty(line));
        Assert.Equal(PosKitchenKdsHelper.Queued, line.KitchenPrepStatus);
    }

    [Fact]
    public void Don_tai_quay_dang_nau_thi_giu_nguyen_trang_thai()
    {
        var order = new PosSaleOrder { Id = Guid.NewGuid() };
        var line = Sent(2);
        line.KitchenPrepStatus = PosKitchenKdsHelper.Cooking;
        PosKitchenKdsHelper.OnOrderPaid(order, [line]);
        Assert.Equal(PosKitchenKdsHelper.Cooking, line.KitchenPrepStatus);
        Assert.Equal(0, line.KitchenDoneQty);
    }

    [Fact]
    public void Don_co_ban_thanh_toan_xong_thi_dong_ve_nhu_truoc()
    {
        var order = new PosSaleOrder { Id = Guid.NewGuid(), ServiceResourceId = Guid.NewGuid() };
        var line = Sent(2);
        PosKitchenKdsHelper.OnOrderPaid(order, [line]);
        Assert.Equal(2, line.KitchenDoneQty);
        Assert.Equal(PosKitchenKdsHelper.Done, line.KitchenPrepStatus);
    }

    [Fact]
    public void Don_ban_luc_mat_mang_gui_len_sau_thi_dong_ve()
    {
        var order = new PosSaleOrder { Id = Guid.NewGuid() };
        var line = Sent(2);
        PosKitchenKdsHelper.OnOrderPaid(order, [line], offlineSync: true);
        Assert.Equal(2, line.KitchenDoneQty);
        Assert.Equal(PosKitchenKdsHelper.Done, line.KitchenPrepStatus);
    }

    [Fact]
    public void Mon_chua_bao_bep_khong_bi_dua_len_man_bep()
    {
        var order = new PosSaleOrder { Id = Guid.NewGuid() };
        var line = new PosSaleOrderLine { Id = Guid.NewGuid(), Qty = 2 };
        PosKitchenKdsHelper.OnOrderPaid(order, [line]);
        Assert.Equal(0, line.KitchenSentQty);
        Assert.Equal(PosKitchenKdsHelper.None, line.KitchenPrepStatus);
    }
}

/// <summary>Qua controller + PostgreSQL: bán tại quầy có món đã báo bếp, thanh toán xong vé vẫn mở.</summary>
[Collection("pos-pg")]
public class KdsTicketOnPaidFlowTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    [Fact]
    public async Task Ban_tai_quay_thanh_toan_ngay_thi_mon_da_bao_bep_van_mo()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var p = (await Fx.AddProductAsync(store, "Cà phê", ZKTecoADMS.Domain.Enums.PosProductType.Goods, 100, 4000, 10000)).Id;
        ZKTecoADMS.Api.Controllers.PosSalesController.SaleOrderDto paid;
        await using (var db = Fx.NewDb())
            paid = Data(await Sales(db, store).CreateSale(new ZKTecoADMS.Api.Controllers.PosSalesController.CreateSaleDto(
                [new ZKTecoADMS.Api.Controllers.PosSalesController.SaleLineDto(p, 2, null, 10000, null, KitchenSentQty: 2)],
                0, 20000, "Tiền mặt", null, null, null)));
        Assert.Equal("Completed", paid.Status);

        await using var check = Fx.NewDb();
        var line = await Microsoft.EntityFrameworkCore.EntityFrameworkQueryableExtensions.SingleAsync(
            check.PosSaleOrderLines, l => l.SaleOrderId == paid.Id);
        Assert.Equal(2, line.KitchenSentQty);
        Assert.Equal(0, line.KitchenDoneQty);
        Assert.Equal(PosKitchenKdsHelper.Queued, line.KitchenPrepStatus);
    }

    static string Json(Microsoft.AspNetCore.Mvc.ActionResult<ZKTecoADMS.Application.Models.AppResponse<object>> r) =>
        System.Text.Json.JsonSerializer.Serialize(((Microsoft.AspNetCore.Mvc.OkObjectResult)r.Result!).Value);

    [Fact]
    public async Task Man_bep_thay_don_tai_quay_da_thanh_toan_nhung_khong_thay_don_co_ban_da_thanh_toan()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var p = (await Fx.AddProductAsync(store, "Phở bò KDS", ZKTecoADMS.Domain.Enums.PosProductType.Goods, 100, 4000, 10000)).Id;
        var area = Guid.NewGuid();
        var table = Guid.NewGuid();
        await using (var db = Fx.NewDb())
        {
            db.PosServiceAreas.Add(new PosServiceArea { Id = area, StoreId = store, Name = "Tầng 1" });
            db.PosServiceResources.Add(new PosServiceResource { Id = table, StoreId = store, AreaId = area, Code = "B9", Name = "Bàn 9" });
            await db.SaveChangesAsync();
        }
        ZKTecoADMS.Api.Controllers.PosSalesController.SaleLineDto Line() => new(p, 1, null, 10000, null, KitchenSentQty: 1);

        // Đơn tại quầy: app ghi món «đã báo bếp» ngay trong lệnh thanh toán.
        ZKTecoADMS.Api.Controllers.PosSalesController.SaleOrderDto counter, atTable;
        await using (var db = Fx.NewDb())
            counter = Data(await Sales(db, store).CreateSale(new ZKTecoADMS.Api.Controllers.PosSalesController.CreateSaleDto(
                [Line()], 0, 10000, "Tiền mặt", null, null, null)));
        // Đơn có bàn, đã báo bếp, thanh toán.
        await using (var db = Fx.NewDb())
            atTable = Data(await Sales(db, store).CreateSale(new ZKTecoADMS.Api.Controllers.PosSalesController.CreateSaleDto(
                [Line()], 0, 10000, "Tiền mặt", null, null, null, ServiceResourceId: table)));
        Assert.Equal("Completed", counter.Status);
        Assert.Equal("Completed", atTable.Status);

        string open;
        await using (var db = Fx.NewDb())
            open = Json(await PosPgFixture.As(new ZKTecoADMS.Api.Controllers.PosKdsController(db, null!, null!), store).Tickets());

        Assert.Contains(counter.Id.ToString(), open, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(atTable.Id.ToString(), open, StringComparison.OrdinalIgnoreCase);
    }
}
