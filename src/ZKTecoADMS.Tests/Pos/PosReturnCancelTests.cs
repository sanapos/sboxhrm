using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Trả hàng / hủy đơn: không trả vượt, quy đổi ĐVT, không hoàn hai lần.</summary>
[Collection("pos-pg")]
public class PosReturnCancelTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    [Fact]
    public async Task Ban_tru_kho_va_tra_hang_cong_lai_dung()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var nuoc = await Fx.AddProductAsync(store, "Nước", PosProductType.Goods, 10, 4000, 10000);

        var order = await SellAsync(store, (nuoc.Id, 3, 10000, null));
        Assert.Equal(7, await OnHandAsync(nuoc.Id));

        Assert.Null(Error(await ReturnAsync(store, order.Id, (nuoc.Id, 2))));
        Assert.Equal(9, await OnHandAsync(nuoc.Id));
        Assert.Equal(10000, (await OrderAsync(order.Id)).Total);
        // Trả vượt số đã bán bị chặn
        Assert.NotNull(Error(await ReturnAsync(store, order.Id, (nuoc.Id, 2))));
    }

    [Fact]
    public async Task Tra_mon_dich_vu_khong_duoc_vuot_so_da_ban()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var bun = await Fx.AddProductAsync(store, "Bún chả", PosProductType.Service, 0, 28000, 70000);
        var order = await SellAsync(store, (bun.Id, 1, 70000, null));

        Assert.Null(Error(await ReturnAsync(store, order.Id, (bun.Id, 1))));
        Assert.NotNull(Error(await ReturnAsync(store, order.Id, (bun.Id, 1))));
        Assert.Equal(0, (await OrderAsync(order.Id)).Total);
    }

    [Fact]
    public async Task Tra_combo_khong_vuot_va_tien_hoan_khong_nhan_theo_thanh_phan()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var nuoc = await Fx.AddProductAsync(store, "Nước", PosProductType.Goods, 10, 4000, 10000);
        var banh = await Fx.AddProductAsync(store, "Bánh", PosProductType.Goods, 10, 6000, 15000);
        var combo = await Fx.AddProductAsync(store, "Combo", PosProductType.Combo, 0, 0, 20000);
        await AddComboLineAsync(store, combo.Id, nuoc.Id, 1);
        await AddComboLineAsync(store, combo.Id, banh.Id, 1);

        var order = await SellAsync(store, (combo.Id, 2, 20000, null));
        Assert.Equal(8, await OnHandAsync(nuoc.Id));

        Assert.Null(Error(await ReturnAsync(store, order.Id, (combo.Id, 1))));
        Assert.Equal(9, await OnHandAsync(nuoc.Id));
        Assert.Equal(9, await OnHandAsync(banh.Id));
        Assert.Null(Error(await ReturnAsync(store, order.Id, (combo.Id, 1))));
        // Đã trả đủ 2 combo — trả thêm phải bị chặn
        Assert.NotNull(Error(await ReturnAsync(store, order.Id, (combo.Id, 1))));
        Assert.Equal(10, await OnHandAsync(nuoc.Id));

        // Tổng tiền hoàn ghi nhận = 40.000 (không nhân 2 theo số thành phần)
        await using var db = Fx.NewDb();
        var reports = Reports(db, store);
        var sum = Data(await reports.GetSalesSummary(DateTime.UtcNow.AddDays(-1), DateTime.UtcNow.AddDays(1)));
        Assert.Equal(40000m, (decimal)sum.GetType().GetProperty("totalRefund")!.GetValue(sum)!);
    }

    [Fact]
    public async Task Tra_mon_dinh_luong_hoan_nguyen_lieu_va_khong_vuot()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var cafeBot = await Fx.AddProductAsync(store, "Cà phê bột", PosProductType.Material, 1000, 220, 0);
        var ly = await Fx.AddProductAsync(store, "Cà phê sữa", PosProductType.Goods, 0, 0, 29000);
        await AddRecipeLineAsync(store, ly.Id, cafeBot.Id, 25);

        var order = await SellAsync(store, (ly.Id, 2, 29000, null));
        Assert.Equal(950, await OnHandAsync(cafeBot.Id));
        Assert.Null(Error(await ReturnAsync(store, order.Id, (ly.Id, 2))));
        Assert.Equal(1000, await OnHandAsync(cafeBot.Id));
        Assert.NotNull(Error(await ReturnAsync(store, order.Id, (ly.Id, 1))));
    }

    [Fact]
    public async Task Tra_hang_ban_theo_thung_quy_doi_ve_don_vi_co_ban()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var bia = await Fx.AddProductAsync(store, "Bia", PosProductType.Goods, 48, 10000, 15000);
        var thung = await AddUnitAsync(store, bia.Id, "Thùng", 24);

        var order = await SellAsync(store, (bia.Id, 1, 340000, thung));
        Assert.Equal(24, await OnHandAsync(bia.Id));

        Assert.Null(Error(await ReturnAsync(store, order.Id, (bia.Id, 1))));
        Assert.Equal(48, await OnHandAsync(bia.Id));
        Assert.NotNull(Error(await ReturnAsync(store, order.Id, (bia.Id, 1))));
    }

    [Fact]
    public async Task Huy_don_dong_thoi_chi_hoan_kho_mot_lan()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var nuoc = await Fx.AddProductAsync(store, "Nước", PosProductType.Goods, 10, 4000, 10000);
        var order = await SellAsync(store, (nuoc.Id, 3, 10000, null));

        async Task<string?> Cancel()
        {
            await using var db = Fx.NewDb();
            return Error(await Sales(db, store).CancelSale(order.Id));
        }
        var results = await Task.WhenAll(Enumerable.Range(0, 4).Select(_ => Task.Run(Cancel)));

        Assert.Equal(10, await OnHandAsync(nuoc.Id));
        Assert.Equal(1, results.Count(r => r == null));
        await using var check = Fx.NewDb();
        Assert.Equal(1, await check.PosStockTransactions.CountAsync(t =>
            t.SaleOrderId == order.Id && t.TransactionType == PosStockTransactionType.Return));
    }

    [Fact]
    public async Task Tien_hoan_chia_theo_giam_gia_cua_don_khong_hoan_qua_so_da_tra()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var nuoc = await Fx.AddProductAsync(store, "Nước", PosProductType.Goods, 10, 4000, 50000);
        // 2 × 50.000 − giảm giá đơn 10.000 = 90.000
        var order = await SellAsync(store, 10000, 0, (nuoc.Id, 2, 50000, null));
        Assert.Equal(90000, (await OrderAsync(order.Id)).Total);

        Assert.Null(Error(await ReturnAsync(store, order.Id, (nuoc.Id, 1))));
        Assert.Equal(45000, (await OrderAsync(order.Id)).Total);
        Assert.Null(Error(await ReturnAsync(store, order.Id, (nuoc.Id, 1))));
        var after = await OrderAsync(order.Id);
        Assert.Equal(0, after.Total);
        Assert.Equal(0, after.PaidAmount);
        await using var db = Fx.NewDb();
        Assert.Equal(90000m, await db.PosSaleReturnLines.Where(r => r.SaleOrderId == order.Id).SumAsync(r => r.RefundAmount));
    }

    [Fact]
    public async Task Huy_phieu_tra_chi_co_dich_vu_hoan_tac_tien_va_tra_lai_duoc()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var bun = await Fx.AddProductAsync(store, "Bún chả", PosProductType.Service, 0, 28000, 70000);
        var order = await SellAsync(store, (bun.Id, 1, 70000, null));
        Assert.Null(Error(await ReturnAsync(store, order.Id, (bun.Id, 1))));

        string returnNo;
        await using (var db = Fx.NewDb())
        {
            returnNo = (await db.PosSaleReturnLines.FirstAsync(r => r.SaleOrderId == order.Id)).ReturnNo;
            var list = Data(await Sales(db, store).GetReturns(order.Id));
            Assert.Equal(70000m, Assert.Single(list).RefundAmount);
        }
        await using (var db = Fx.NewDb())
            Data(await Sales(db, store).CancelReturn(order.Id, new ZKTecoADMS.Api.Controllers.PosSalesController.CancelSaleReturnDto(returnNo)));

        Assert.Equal(70000, (await OrderAsync(order.Id)).Total);
        // Phiếu đã hủy → được trả lại
        Assert.Null(Error(await ReturnAsync(store, order.Id, (bun.Id, 1))));
        Assert.Equal(0, (await OrderAsync(order.Id)).Total);
    }

    [Fact]
    public async Task Ban_dich_vu_ghi_gia_von_va_huy_don_khong_loi()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var bun = await Fx.AddProductAsync(store, "Bún chả", PosProductType.Service, 0, 28000, 70000);
        var order = await SellAsync(store, (bun.Id, 2, 70000, null));
        await using (var db = Fx.NewDb())
        {
            var cogs = await db.PosStockTransactions.Where(t => t.SaleOrderId == order.Id && t.TransactionType == PosStockTransactionType.Sale)
                .SumAsync(t => t.LineAmount ?? 0);
            Assert.Equal(56000m, cogs);
            Assert.Null(Error(await Sales(db, store).CancelSale(order.Id)));
        }
        Assert.Equal(PosSaleOrderStatus.Cancelled, (await OrderAsync(order.Id)).Status);
    }
}
