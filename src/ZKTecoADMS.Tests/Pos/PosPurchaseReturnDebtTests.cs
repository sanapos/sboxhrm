using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Hủy phiếu trả NCC chỉ cộng lại đúng số công nợ đã thực giảm lúc hoàn thành.</summary>
[Collection("pos-pg")]
public class PosPurchaseReturnDebtTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    async Task<(Guid supplierId, PosPurchaseReturn ret)> SetupAsync(decimal debt, decimal returnAmount)
    {
        var store = await Fx.NewStoreAsync();
        await using var db = Fx.NewDb();
        var s = new PosSupplier
        {
            Id = Guid.NewGuid(), StoreId = store, SupplierCode = "NCC1", Name = "NCC", CurrentDebt = debt,
            TotalPurchase = 100000, IsActive = true,
        };
        db.PosSuppliers.Add(s);
        var ret = new PosPurchaseReturn
        {
            Id = Guid.NewGuid(), StoreId = store, ReturnNo = "THN1", SupplierId = s.Id,
            TotalAmount = returnAmount, DiscountAmount = 0, RefundReceived = 0, IsActive = true,
        };
        db.PosPurchaseReturns.Add(ret);
        await db.SaveChangesAsync();
        return (s.Id, ret);
    }

    async Task<decimal> DebtAsync(Guid id)
    {
        await using var db = Fx.NewDb();
        return (await db.PosSuppliers.FirstAsync(x => x.Id == id)).CurrentDebt;
    }

    async Task CompleteThenCancelAsync(PosPurchaseReturn ret)
    {
        await using (var db = Fx.NewDb())
        {
            await PosPurchaseStockHelper.UpdateSupplierOnReturnCompleteAsync(db, ret);
            await db.SaveChangesAsync();
        }
        await using (var db = Fx.NewDb())
        {
            await PosPurchaseStockHelper.ReverseSupplierOnReturnCancelAsync(db, ret);
            await db.SaveChangesAsync();
        }
    }

    [Fact]
    public async Task Tra_hang_khi_da_het_no_roi_huy_thi_cong_no_van_bang_0()
    {
        if (NoDb) return;
        var (sid, ret) = await SetupAsync(debt: 0, returnAmount: 20000);
        await CompleteThenCancelAsync(ret);
        Assert.Equal(0, await DebtAsync(sid)); // trước đây thành 20.000
    }

    [Fact]
    public async Task Tra_hang_vuot_no_roi_huy_thi_ve_dung_no_cu()
    {
        if (NoDb) return;
        var (sid, ret) = await SetupAsync(debt: 15000, returnAmount: 20000);
        await CompleteThenCancelAsync(ret);
        Assert.Equal(15000, await DebtAsync(sid)); // trước đây thành 20.000
    }

    [Fact]
    public async Task Tra_hang_binh_thuong_roi_huy_thi_ve_dung_no_cu()
    {
        if (NoDb) return;
        var (sid, ret) = await SetupAsync(debt: 100000, returnAmount: 20000);
        await CompleteThenCancelAsync(ret);
        Assert.Equal(100000, await DebtAsync(sid));
    }
}
