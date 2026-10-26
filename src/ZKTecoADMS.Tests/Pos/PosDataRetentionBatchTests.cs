using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Xóa hóa đơn cũ theo gói chạy theo từng đợt nhỏ nhưng vẫn xóa hết, không đụng đơn nháp / đơn mới.</summary>
[Collection("pos-pg")]
public class PosDataRetentionBatchTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    [Fact]
    public async Task Xoa_don_cu_theo_dot_van_xoa_het()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var nuoc = await Fx.AddProductAsync(store, "Nước", PosProductType.Goods, 100, 4000, 10000);
        var old = new List<Guid>();
        for (var i = 0; i < 5; i++) old.Add((await SellAsync(store, (nuoc.Id, 1, 10000, null))).Id);
        var draft = (await SellAsync(store, (nuoc.Id, 1, 10000, null))).Id;
        var recent = (await SellAsync(store, (nuoc.Id, 1, 10000, null))).Id;
        var longAgo = DateTime.UtcNow.AddYears(-2);
        await using (var db = Fx.NewDb())
        {
            await db.PosSaleOrders.Where(o => old.Contains(o.Id) || o.Id == draft)
                .ExecuteUpdateAsync(s => s.SetProperty(o => o.SaleDate, longAgo));
            await db.PosSaleOrders.Where(o => o.Id == draft)
                .ExecuteUpdateAsync(s => s.SetProperty(o => o.Status, PosSaleOrderStatus.Draft));
        }

        await using (var db = Fx.NewDb())
        {
            var deleted = await PackageDataRetentionBackgroundService.DeleteSaleOrdersAsync(
                db, store, DateTime.UtcNow.AddYears(-1), CancellationToken.None, batch: 2);
            Assert.Equal(5, deleted);
        }

        await using (var check = Fx.NewDb())
        {
            var left = await check.PosSaleOrders.IgnoreQueryFilters().Where(o => o.StoreId == store).Select(o => o.Id).ToListAsync();
            Assert.Equal(new[] { draft, recent }.OrderBy(x => x), left.OrderBy(x => x));
            Assert.False(await check.PosSaleOrderLines.IgnoreQueryFilters().AnyAsync(l => old.Contains(l.SaleOrderId)));
            Assert.False(await check.PosStockTransactions.IgnoreQueryFilters()
                .AnyAsync(t => t.SaleOrderId != null && old.Contains(t.SaleOrderId.Value)));
            // Thẻ kho vẫn giữ (chỉ bỏ liên kết đơn) — tồn kho không đổi.
            Assert.True(await check.PosStockTransactions.IgnoreQueryFilters().CountAsync(t => t.StoreId == store) >= 7);
        }
    }
}
