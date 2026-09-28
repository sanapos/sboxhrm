using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Interceptors;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Tests;

/// <summary>
/// Tồn kho theo chi nhánh qua interceptor: chênh lệch tồn ghi đúng chi nhánh thao tác / chi nhánh của chứng từ,
/// trụ sở tính ngầm, hàng đang chuyển, đổi trụ sở.
/// </summary>
public class BranchStockInterceptorTests
{
    private readonly Guid _store = Guid.NewGuid();
    private readonly Guid _hq = Guid.NewGuid();
    private readonly Guid _b = Guid.NewGuid();
    private readonly BranchContext _ctx = new();

    private ZKTecoDbContext NewDb(string name) => new(new DbContextOptionsBuilder<ZKTecoDbContext>()
        .UseInMemoryDatabase(name)
        .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking)
        .AddInterceptors(new BranchStockInterceptor(_ctx))
        .Options);

    private async Task<(string name, Guid productId)> SeedAsync()
    {
        var name = Guid.NewGuid().ToString();
        await using var db = NewDb(name);
        db.Branches.AddRange(
            new Branch { Id = _hq, StoreId = _store, Code = "HQ", Name = "Trụ sở", IsHeadquarter = true, IsActive = true },
            new Branch { Id = _b, StoreId = _store, Code = "B", Name = "Chi nhánh B", IsActive = true });
        var p = new PosProduct { Id = Guid.NewGuid(), StoreId = _store, ProductCode = "SP", Name = "Sản phẩm",
            ProductType = PosProductType.Goods, OnHandQty = 0 };
        db.PosProducts.Add(p);
        await db.SaveChangesAsync();
        return (name, p.Id);
    }

    private async Task AddStockAsync(string name, Guid productId, decimal delta, Guid? ambient)
    {
        _ctx.CurrentBranchId = ambient;
        await using var db = NewDb(name);
        var p = await db.PosProducts.AsTracking().FirstAsync(x => x.Id == productId);
        p.OnHandQty += delta;
        await db.SaveChangesAsync();
    }

    private async Task<decimal> QtyAsync(string name, Guid productId, Guid branch)
    {
        await using var db = NewDb(name);
        var d = await BranchStockService.GetBranchQtyAsync(db, _store, branch, _hq, [productId]);
        return d.GetValueOrDefault((productId, (Guid?)null));
    }

    [Fact]
    public async Task Nhap_tai_chi_nhanh_va_tru_so()
    {
        var (name, pid) = await SeedAsync();
        await AddStockAsync(name, pid, 10, _b);   // nhập 10 tại B
        await AddStockAsync(name, pid, 5, _hq);   // nhập 5 tại trụ sở
        await AddStockAsync(name, pid, 7, null);  // không rõ chi nhánh → trụ sở

        Assert.Equal(10, await QtyAsync(name, pid, _b));
        Assert.Equal(12, await QtyAsync(name, pid, _hq));
    }

    [Fact]
    public async Task The_kho_theo_don_lay_chi_nhanh_cua_don()
    {
        var (name, pid) = await SeedAsync();
        await AddStockAsync(name, pid, 10, _b);

        // Đơn bán ở B nhưng người thao tác đang ở trụ sở (vd hủy / trả đơn cũ) → trừ kho B.
        _ctx.CurrentBranchId = _hq;
        await using (var db = NewDb(name))
        {
            var order = new PosSaleOrder { Id = Guid.NewGuid(), StoreId = _store, OrderNo = "HD1", BranchId = _b };
            db.PosSaleOrders.Add(order);
            await db.SaveChangesAsync();

            var p = await db.PosProducts.AsTracking().FirstAsync(x => x.Id == pid);
            p.OnHandQty -= 3;
            db.PosStockTransactions.Add(new PosStockTransaction
            {
                Id = Guid.NewGuid(), StoreId = _store, ProductId = pid, SaleOrderId = order.Id,
                TransactionType = PosStockTransactionType.Sale, QtyChange = -3, QtyAfter = p.OnHandQty,
            });
            await db.SaveChangesAsync();

            var tx = await db.PosStockTransactions.FirstAsync();
            Assert.Equal(_b, tx.BranchId); // thẻ kho kế thừa chi nhánh của đơn
        }
        Assert.Equal(7, await QtyAsync(name, pid, _b));
        Assert.Equal(0, await QtyAsync(name, pid, _hq));
    }

    [Fact]
    public async Task Chung_tu_moi_duoc_gan_chi_nhanh_dang_thao_tac()
    {
        var (name, _) = await SeedAsync();
        _ctx.CurrentBranchId = _b;
        await using var db = NewDb(name);
        var cash = new CashTransaction { Id = Guid.NewGuid(), StoreId = _store, Amount = 100 };
        db.CashTransactions.Add(cash);
        await db.SaveChangesAsync();
        Assert.Equal(_b, (await db.CashTransactions.FirstAsync()).BranchId);
    }

    [Fact]
    public async Task Hang_dang_chuyen_khong_tinh_vao_kho_nao()
    {
        var (name, pid) = await SeedAsync();
        await AddStockAsync(name, pid, 20, _hq);
        await using (var db = NewDb(name))
        {
            db.PosStockTransfers.Add(new PosStockTransfer
            {
                Id = Guid.NewGuid(), StoreId = _store, TransferNo = "CK1", FromBranchId = _hq, ToBranchId = _b,
                Status = PosStockTransferStatus.Sent,
                Lines = [new PosStockTransferLine { Id = Guid.NewGuid(), ProductId = pid, ProductName = "SP", Qty = 6 }],
            });
            await db.SaveChangesAsync();
        }
        Assert.Equal(14, await QtyAsync(name, pid, _hq)); // 20 − 6 đang chuyển
        Assert.Equal(0, await QtyAsync(name, pid, _b));
    }

    [Fact]
    public async Task Doi_tru_so_giu_nguyen_ton_tung_chi_nhanh()
    {
        var (name, pid) = await SeedAsync();
        await AddStockAsync(name, pid, 10, _b);
        await AddStockAsync(name, pid, 30, _hq);

        await using (var db = NewDb(name))
        {
            await BranchStockService.RebaseHeadquarterAsync(db, _store, _hq, _b);
            var old = await db.Branches.AsTracking().FirstAsync(x => x.Id == _hq);
            var nw = await db.Branches.AsTracking().FirstAsync(x => x.Id == _b);
            old.IsHeadquarter = false;
            nw.IsHeadquarter = true;
            await db.SaveChangesAsync();

            var d = await BranchStockService.GetBranchQtyAsync(db, _store, _hq, _b, [pid]);
            Assert.Equal(30, d.GetValueOrDefault((pid, (Guid?)null)));   // trụ sở cũ giờ là số lưu
            var d2 = await BranchStockService.GetBranchQtyAsync(db, _store, _b, _b, [pid]);
            Assert.Equal(10, d2.GetValueOrDefault((pid, (Guid?)null)));  // trụ sở mới tính ngầm = 40 − 30
        }
    }
}
