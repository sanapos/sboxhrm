using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Tìm kiếm không dấu: thu ngân gõ «binh», «banh mi» vẫn ra «Bình», «Bánh mì».</summary>
[Collection("pos-pg")]
public class PosSearchTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    [Theory]
    [InlineData("Bình", "binh")]
    [InlineData("Bánh mì que", "banh mi")]
    [InlineData("ĐẬU PHỘNG", "dau phong")]
    [InlineData("Nước giải khát", "NUOC GIAI")]
    public void Fold_trong_bo_nho(string text, string query) =>
        Assert.Contains(VnSearch.FoldText(query), VnSearch.Fold(text));

    [Fact]
    public void Fold_bo_dau_to_hop()
    {
        // «Bình» gõ kiểu tách dấu: i + dấu huyền rời (U+0300).
        Assert.Equal("binh", VnSearch.Fold("Bình"));
    }

    [Fact]
    public async Task Tim_khach_va_hang_khong_dau_tren_db()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        await Fx.AddProductAsync(store, "Bánh mì que pate", PosProductType.Goods, 10, 6000, 15000);
        await using (var db = Fx.NewDb())
        {
            db.PosCustomers.Add(new PosCustomer { Id = Guid.NewGuid(), StoreId = store, CustomerCode = "KH000001", Name = "Trần Thị Bình", IsActive = true });
            await db.SaveChangesAsync();
        }
        await using var db2 = Fx.NewDb();
        var s1 = VnSearch.FoldText("binh");
        Assert.Equal(1, await db2.PosCustomers.CountAsync(c => c.StoreId == store && VnSearch.Fold(c.Name).Contains(s1)));
        var s2 = VnSearch.FoldText("BANH MI");
        Assert.Equal(1, await db2.PosProducts.CountAsync(p => p.StoreId == store && VnSearch.Fold(p.Name).Contains(s2)));
        var s3 = VnSearch.FoldText("Bình");
        Assert.Equal(1, await db2.PosCustomers.CountAsync(c => c.StoreId == store && VnSearch.Fold(c.Name).Contains(s3)));
    }
}
