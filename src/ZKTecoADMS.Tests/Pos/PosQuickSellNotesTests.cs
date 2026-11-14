using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Sổ tay bán hàng nhanh: tạo mục, sửa danh sách món, xóa mềm, không lẫn cửa hàng.</summary>
[Collection("pos-pg")]
public class PosQuickSellNotesTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    static PosQuickSellNotesController Ctl(ZKTecoADMS.Infrastructure.ZKTecoDbContext db, Guid store) =>
        PosPgFixture.As(new PosQuickSellNotesController(db), store);

    [Fact]
    public async Task Tao_sua_xoa_so_tay()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var bun = await Fx.AddProductAsync(store, "Bún chả", PosProductType.Goods, 100, 0, 40000);
        var tra = await Fx.AddProductAsync(store, "Trà đá", PosProductType.Goods, 100, 0, 5000);
        var nem = await Fx.AddProductAsync(store, "Nem rán", PosProductType.Goods, 100, 0, 30000);

        Guid noteId;
        await using (var db = Fx.NewDb())
        {
            var created = Data(await Ctl(db, store).Create(new(
                "Mâm 4 người", "Khách quen", 0,
                [new(bun.Id, 2), new(tra.Id, 4)])));
            noteId = created.Id;
            Assert.Equal("Mâm 4 người", created.Name);
            Assert.Equal(2, created.Items.Count);
            // Giá lấy theo hàng hóa để màn bán hiện tạm tính mà không phải gọi thêm API.
            Assert.Equal(40000m, created.Items.Single(i => i.ProductId == bun.Id).Price);
            Assert.Equal(4m, created.Items.Single(i => i.ProductId == tra.Id).Qty);
        }

        // Sửa: bỏ trà đá, đổi số phần bún chả, thêm nem rán.
        await using (var db = Fx.NewDb())
        {
            var updated = Data(await Ctl(db, store).Update(noteId, new(
                "Mâm 4 người (mới)", null, 1,
                [new(bun.Id, 3), new(nem.Id, 1)])));
            Assert.Equal("Mâm 4 người (mới)", updated.Name);
            Assert.Null(updated.Description);
            Assert.Equal(2, updated.Items.Count);
            Assert.Equal(3m, updated.Items.Single(i => i.ProductId == bun.Id).Qty);
            Assert.DoesNotContain(updated.Items, i => i.ProductId == tra.Id);
        }

        await using (var db = Fx.NewDb())
        {
            var list = Data(await Ctl(db, store).List());
            var note = Assert.Single(list);
            Assert.Equal(2, note.Items.Count);
            // Thứ tự giữ đúng như lúc lưu — thu ngân thấy danh sách như đã sắp.
            Assert.Equal(bun.Id, note.Items[0].ProductId);
            Assert.Equal(nem.Id, note.Items[1].ProductId);
        }

        await using (var db = Fx.NewDb())
        {
            Data(await Ctl(db, store).Delete(noteId));
        }
        await using (var db = Fx.NewDb())
        {
            Assert.Empty(Data(await Ctl(db, store).List()));
            // Xóa mềm: dòng món cũng phải tắt, không còn sót trong bảng con.
            Assert.False(await db.PosQuickSellNoteItems
                .AnyAsync(i => i.NoteId == noteId && i.Deleted == null));
        }
    }

    [Fact]
    public async Task Mon_da_xoa_khong_lam_hong_so_tay()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var pho = await Fx.AddProductAsync(store, "Phở", PosProductType.Goods, 50, 0, 50000);
        var quay = await Fx.AddProductAsync(store, "Quẩy", PosProductType.Goods, 50, 0, 10000);

        await using (var db = Fx.NewDb())
        {
            Data(await Ctl(db, store).Create(new("Sáng", null, 0, [new(pho.Id, 1), new(quay.Id, 2)])));
        }
        // Quẩy bị xóa khỏi danh mục.
        await using (var db = Fx.NewDb())
        {
            var p = await db.PosProducts.AsTracking().FirstAsync(x => x.Id == quay.Id);
            p.Deleted = DateTime.UtcNow;
            p.IsActive = false;
            await db.SaveChangesAsync();
        }
        await using (var db = Fx.NewDb())
        {
            var note = Assert.Single(Data(await Ctl(db, store).List()));
            var item = Assert.Single(note.Items);
            Assert.Equal(pho.Id, item.ProductId);
        }
    }

    [Fact]
    public async Task So_tay_khong_lan_giua_cac_cua_hang()
    {
        if (NoDb) return;
        var storeA = await Fx.NewStoreAsync();
        var storeB = await Fx.NewStoreAsync();
        var sp = await Fx.AddProductAsync(storeA, "Cơm gà", PosProductType.Goods, 10, 0, 45000);

        Guid noteId;
        await using (var db = Fx.NewDb())
        {
            noteId = Data(await Ctl(db, storeA).Create(new("Trưa", null, 0, [new(sp.Id, 1)]))).Id;
        }
        await using (var db = Fx.NewDb())
        {
            Assert.Empty(Data(await Ctl(db, storeB).List()));
            // Cửa hàng khác không xóa được sổ của cửa hàng này.
            Assert.NotNull(Error(await Ctl(db, storeB).Delete(noteId)));
        }
        await using (var db = Fx.NewDb())
        {
            Assert.Single(Data(await Ctl(db, storeA).List()));
        }
    }
}
