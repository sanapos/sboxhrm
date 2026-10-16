using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Nhắc nợ ở màn bán: tóm tắt nợ khách đọc mới (số nợ, số đơn còn nợ, đơn lâu nhất, lần thu gần nhất).</summary>
[Collection("pos-pg")]
public class PosCustomerDebtSummaryTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    [Fact]
    public async Task Ban_no_roi_thu_mot_phan_tom_tat_dung()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var p = await Fx.AddProductAsync(store, "Gạo", PosProductType.Goods, 100, 0, 100000);
        Guid customerId;
        await using (var db = Fx.NewDb())
        {
            var c = new PosCustomer { Id = Guid.NewGuid(), StoreId = store, CustomerCode = "KHNO1", Name = "Chị Ba", IsActive = true };
            db.PosCustomers.Add(c);
            await db.SaveChangesAsync();
            customerId = c.Id;
        }
        // Hai đơn bán nợ: 300.000 trả 100.000 (nợ 200.000), 100.000 trả 0.
        foreach (var (qty, paid) in new[] { (3m, 100000m), (1m, 0m) })
        {
            await using var db = Fx.NewDb();
            var dto = new PosSalesController.CreateSaleDto(
                [new PosSalesController.SaleLineDto(p.Id, qty, null, 100000, null)], 0, paid, "Tiền mặt", null, customerId, null);
            Data(await Sales(db, store).CreateSale(dto));
        }
        // Đơn đầu là đơn cũ 40 ngày.
        await using (var db = Fx.NewDb())
        {
            var first = await db.PosSaleOrders.AsTracking().Where(o => o.CustomerId == customerId).OrderBy(o => o.CreatedAt).FirstAsync();
            first.SaleDate = DateTime.UtcNow.AddDays(-40);
            await db.SaveChangesAsync();
        }
        await using (var db = Fx.NewDb())
        {
            var ctl = PosPgFixture.As(new PosCustomersController(db), store);
            var d = Data(await ctl.DebtSummary(customerId));
            object V(string k) => d.GetType().GetProperty(k)!.GetValue(d)!;
            Assert.Equal(300000m, (decimal)V("currentDebt"));
            Assert.Equal(2, (int)V("openOrderCount"));
            Assert.Equal(40, (int)V("oldestDays"));
            Assert.Equal(200000m, (decimal)V("over30"));
        }
        // Thu 250.000 (FIFO: hết đơn cũ 200.000, đơn mới còn 50.000).
        await using (var db = Fx.NewDb())
        {
            var ctl = PosPgFixture.As(new PosCustomersController(db), store);
            Data(await ctl.AddPayment(customerId, new(250000, "Tiền mặt", null, null)));
        }
        await using (var db = Fx.NewDb())
        {
            var ctl = PosPgFixture.As(new PosCustomersController(db), store);
            var d = Data(await ctl.DebtSummary(customerId));
            object? V(string k) => d.GetType().GetProperty(k)!.GetValue(d);
            Assert.Equal(50000m, (decimal)V("currentDebt")!);
            Assert.Equal(1, (int)V("openOrderCount")!);
            Assert.Equal(0, (int)V("oldestDays")!);
            Assert.Equal(250000m, (decimal)V("lastPaymentAmount")!);
        }
    }

    async Task<Guid> NewCustomerAsync(Guid store, string code, decimal? limit = null, int? term = null)
    {
        await using var db = Fx.NewDb();
        var c = new PosCustomer { Id = Guid.NewGuid(), StoreId = store, CustomerCode = code, Name = "Khách " + code, IsActive = true,
            DebtLimit = limit, PaymentTermDays = term };
        db.PosCustomers.Add(c);
        await db.SaveChangesAsync();
        return c.Id;
    }

    async Task SetPolicyAsync(Guid store, string debtJson)
    {
        await using var db = Fx.NewDb();
        var s = await db.PosStoreSellSettings.AsTracking().FirstOrDefaultAsync(x => x.StoreId == store);
        if (s == null)
        {
            s = new PosStoreSellSettings { Id = Guid.NewGuid(), StoreId = store, IsActive = true };
            db.PosStoreSellSettings.Add(s);
        }
        s.ExtraJson = "{\"debt\":" + debtJson + "}";
        await db.SaveChangesAsync();
    }

    async Task<Microsoft.AspNetCore.Mvc.ActionResult<ZKTecoADMS.Application.Models.AppResponse<PosSalesController.SaleOrderDto>>> SellOnCreditAsync(
        Guid store, Guid productId, Guid customerId, decimal qty, decimal paid)
    {
        await using var db = Fx.NewDb();
        return await Sales(db, store).CreateSale(new PosSalesController.CreateSaleDto(
            [new PosSalesController.SaleLineDto(productId, qty, null, 100000, null)], 0, paid, "Tiền mặt", null, customerId, null));
    }

    [Fact]
    public async Task Vuot_han_muc_no_bi_chan_khi_cua_hang_bat_chan()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var p = await Fx.AddProductAsync(store, "Bia", PosProductType.Goods, 100, 0, 100000);
        var c = await NewCustomerAsync(store, "HM1", limit: 250000);
        await SetPolicyAsync(store, "{\"blockOverLimit\":true}");
        Data(await SellOnCreditAsync(store, p.Id, c, 2, 0));               // nợ 200.000 ≤ 250.000
        var res = await SellOnCreditAsync(store, p.Id, c, 1, 0);           // 300.000 > 250.000
        Assert.Contains("Vượt hạn mức nợ", Error(res));
        Assert.Equal(98, await OnHandAsync(p.Id));                         // đơn bị chặn không trừ kho
        Data(await SellOnCreditAsync(store, p.Id, c, 1, 100000));         // trả đủ → không ghi nợ → bán được
        // Chỉ cảnh báo (không chặn) → máy chủ cho bán.
        await SetPolicyAsync(store, "{\"blockOverLimit\":false}");
        Data(await SellOnCreditAsync(store, p.Id, c, 1, 0));
    }

    [Fact]
    public async Task Co_don_qua_han_bi_chan_ban_no_them()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var p = await Fx.AddProductAsync(store, "Gạo", PosProductType.Goods, 100, 0, 100000);
        var c = await NewCustomerAsync(store, "QH1");
        await SetPolicyAsync(store, "{\"termDays\":30,\"blockOverdue\":true}");
        var first = Data(await SellOnCreditAsync(store, p.Id, c, 1, 0));
        await using (var db = Fx.NewDb())
        {
            var o = await db.PosSaleOrders.AsTracking().FirstAsync(x => x.Id == first.Id);
            o.SaleDate = DateTime.UtcNow.AddDays(-45);
            await db.SaveChangesAsync();
        }
        Assert.Contains("quá hạn", Error(await SellOnCreditAsync(store, p.Id, c, 1, 0)));
        await using (var db = Fx.NewDb())
        {
            var ctl = PosPgFixture.As(new PosCustomersController(db), store);
            var d = Data(await ctl.DebtSummary(c));
            Assert.Equal(15, (int)d.GetType().GetProperty("overdueDays")!.GetValue(d)!);
        }
    }

    [Fact]
    public async Task Nhap_no_dau_ky_khach_va_ncc_tra_duoc_phan_ngoai_phieu()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var c = await NewCustomerAsync(store, "DK1");
        Guid sid;
        await using (var db = Fx.NewDb())
        {
            var s = new PosSupplier { Id = Guid.NewGuid(), StoreId = store, SupplierCode = "NCCDK", Name = "NCC đầu kỳ", IsActive = true };
            db.PosSuppliers.Add(s);
            await db.SaveChangesAsync();
            sid = s.Id;
        }
        await using (var db = Fx.NewDb())
        {
            var ctl = PosPgFixture.As(new PosCustomersController(db), store);
            Assert.NotNull(Error(await ctl.AdjustDebt(c, new(500000, " "))));   // thiếu lý do
            Data(await ctl.AdjustDebt(c, new(500000, "Nợ chuyển từ sổ tay")));
            Data(await ctl.AdjustDebt(c, new(450000, "Đối chiếu lại")));
            // Thu nợ đầu kỳ (không có đơn) được.
            Data(await ctl.AddPayment(c, new(150000, "Tiền mặt", null, null)));
            var sup = PosPgFixture.As(new PosPurchaseSuppliersController(db), store);
            Data(await sup.AdjustDebt(sid, new(800000, "Nợ NCC chuyển sang")));
        }
        await using (var db = Fx.NewDb())
        {
            Assert.Equal(300000m, (await db.PosCustomers.FirstAsync(x => x.Id == c)).CurrentDebt);
            var types = await db.PosDebtLedgerEntries.Where(e => e.PartyId == c).OrderBy(e => e.At).Select(e => e.DocType).ToListAsync();
            Assert.Equal(["Opening", "Adjust", "Payment"], types);
            // Trả NCC 300.000 khi không có phiếu nhập nào còn nợ (trước đây bị chặn «vượt tổng nợ các phiếu»).
            var sup = PosPgFixture.As(new PosPurchaseSuppliersController(db), store);
            Data(await sup.PayAll(sid, new PosPurchaseSuppliersController.SupplierPayAllDto(300000, "Tiền mặt", null, null)));
        }
        await using (var db = Fx.NewDb())
            Assert.Equal(500000m, (await db.PosSuppliers.FirstAsync(x => x.Id == sid)).CurrentDebt);
    }
}
