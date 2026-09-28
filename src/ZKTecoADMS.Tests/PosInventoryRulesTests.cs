using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>Nguyên tắc kho: giá vốn bình quân khi nhập / hủy nhập, đối soát giữ chỗ tồn.</summary>
public class PosInventoryRulesTests
{
    [Theory]
    [InlineData(10, 100, 5, 130)]
    [InlineData(3, 50, 7, 80)]
    [InlineData(1, 1000, 999, 1)]
    public void Huy_phieu_nhap_tra_gia_von_ve_nhu_truoc(decimal oldQty, decimal oldCost, decimal addQty, decimal addCost)
    {
        var avg = PosPurchaseStockHelper.WeightedAverageCost(oldQty, oldCost, addQty, addCost);
        var back = PosPurchaseStockHelper.ReverseWeightedAverageCost(oldQty + addQty, avg, addQty, addCost);
        Assert.Equal(oldCost, back, 2);
    }

    [Fact]
    public void Huy_nhap_khi_het_ton_giu_nguyen_gia_von()
    {
        Assert.Equal(120m, PosPurchaseStockHelper.ReverseWeightedAverageCost(5, 120, 5, 130));
        Assert.Equal(120m, PosPurchaseStockHelper.ReverseWeightedAverageCost(2, 120, 5, 130));
    }

    [Fact]
    public async Task Doi_soat_giu_cho_ghi_lai_dung_nhu_cau_don_mo()
    {
        var store = Guid.NewGuid();
        await using var db = new ZKTecoDbContext(new DbContextOptionsBuilder<ZKTecoDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking)
            .Options);

        var cafe = new PosProduct { Id = Guid.NewGuid(), StoreId = store, ProductCode = "CF", Name = "Cà phê",
            ProductType = PosProductType.Goods, OnHandQty = 20, ReservedQty = 9 }; // 9 = rò rỉ cũ
        var tra = new PosProduct { Id = Guid.NewGuid(), StoreId = store, ProductCode = "TR", Name = "Trà",
            ProductType = PosProductType.Goods, OnHandQty = 5, ReservedQty = 4 }; // không còn đơn mở
        db.PosProducts.AddRange(cafe, tra);

        await db.SaveChangesAsync();

        // Nhu cầu giữ chỗ tính từ đơn tạm đang mở: 3 ly cà phê; trà không còn đơn mở.
        var changed = await PosReservedStockReconciler.ApplyNeedsAsync(
            db, store, new Dictionary<Guid, decimal> { [cafe.Id] = 3m });

        Assert.Equal(2, changed);
        db.ChangeTracker.Clear();
        Assert.Equal(3m, (await db.PosProducts.FirstAsync(p => p.Id == cafe.Id)).ReservedQty);
        Assert.Equal(0m, (await db.PosProducts.FirstAsync(p => p.Id == tra.Id)).ReservedQty);
    }
}
