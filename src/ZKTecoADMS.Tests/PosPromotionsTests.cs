using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>Khuyến mãi: máy bán gửi PromotionsJson → máy chủ chỉ giữ chương trình có thật của cửa hàng.</summary>
public class PosPromotionsTests
{
    static ZKTecoDbContext NewDb() =>
        new(new DbContextOptionsBuilder<ZKTecoDbContext>().UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);

    [Fact]
    public async Task Gui_id_la_hoac_cua_cua_hang_khac_bi_loai()
    {
        await using var db = NewDb();
        var store = Guid.NewGuid();
        var other = Guid.NewGuid();
        var mine = new PosPromotion { Id = Guid.NewGuid(), StoreId = store, Name = "Giảm 10%", Type = "time_discount" };
        var theirs = new PosPromotion { Id = Guid.NewGuid(), StoreId = other, Name = "KM cửa hàng khác", Type = "time_discount" };
        db.PosPromotions.AddRange(mine, theirs);
        await db.SaveChangesAsync();

        var json = JsonSerializer.Serialize(new
        {
            applied = new object[]
            {
                new { id = mine.Id, name = "Tên giả", amount = 5000 },
                new { id = theirs.Id, name = "x", amount = 99999 },
                new { id = Guid.NewGuid(), name = "không tồn tại", amount = 1 },
                new { id = mine.Id, name = "âm", amount = -5 },
            },
            lines = new Dictionary<string, decimal> { ["a"] = 5000 },
            bill = 0,
        });
        var (outJson, total) = await PosPromotionsController.SanitizeForStoreAsync(db, store, json);
        Assert.Equal(5000, total);
        var applied = JsonDocument.Parse(outJson!).RootElement.GetProperty("applied");
        Assert.Equal(1, applied.GetArrayLength());
        Assert.Equal("Giảm 10%", applied[0].GetProperty("name").GetString()); // tên theo máy chủ
    }

    [Fact]
    public async Task Khong_co_chuong_trinh_hop_le_thi_khong_luu()
    {
        await using var db = NewDb();
        var (json, total) = await PosPromotionsController.SanitizeForStoreAsync(
            db, Guid.NewGuid(), """{"applied":[{"id":"00000000-0000-0000-0000-000000000001","name":"x","amount":10}]}""");
        Assert.Null(json);
        Assert.Equal(0, total);
        Assert.Null((await PosPromotionsController.SanitizeForStoreAsync(db, Guid.NewGuid(), null)).Json);
        Assert.Null((await PosPromotionsController.SanitizeForStoreAsync(db, Guid.NewGuid(), "không phải json")).Json);
    }

    [Fact]
    public void Khuyen_mai_theo_chi_nhanh_rong_la_moi_chi_nhanh()
    {
        var a = Guid.NewGuid();
        var b = Guid.NewGuid();
        var all = new PosPromotion { BranchIdsJson = null };
        var none = new PosPromotion { BranchIdsJson = "[]" };
        var onlyA = new PosPromotion { BranchIdsJson = JsonSerializer.Serialize(new[] { a.ToString() }) };
        var broken = new PosPromotion { BranchIdsJson = "không phải json" };
        Assert.True(PosPromotionsController.AppliesToBranch(all, a));
        Assert.True(PosPromotionsController.AppliesToBranch(none, b));
        Assert.True(PosPromotionsController.AppliesToBranch(broken, b)); // hỏng → coi như mọi chi nhánh
        Assert.True(PosPromotionsController.AppliesToBranch(onlyA, a));
        Assert.False(PosPromotionsController.AppliesToBranch(onlyA, b));
        Assert.False(PosPromotionsController.AppliesToBranch(onlyA, null));
        Assert.Equal([a], PosPromotionsController.ParseBranchIds(onlyA.BranchIdsJson));
    }
}
