using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>
/// DbContext của app mặc định NoTracking: sửa / xóa phải đọc bản ghi bằng AsTracking, nếu không SaveChanges không ghi gì
/// mà API vẫn báo thành công (voucher, nhóm topping trước đây bị lỗi này).
/// </summary>
public class PosUntrackedUpdateTests
{
    static readonly Guid Store = Guid.NewGuid();

    // Cùng cấu hình theo dõi như production (Infrastructure/DependencyInjectionExtensions.cs).
    static ZKTecoDbContext NewDb(string name) => new(new DbContextOptionsBuilder<ZKTecoDbContext>()
        .UseInMemoryDatabase(name)
        .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking)
        .Options);

    static T WithUser<T>(T controller) where T : ControllerBase
    {
        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                User = new ClaimsPrincipal(new ClaimsIdentity(
                [
                    new Claim("id", Guid.NewGuid().ToString()), new Claim(ClaimTypes.Role, "Admin"),
                    new Claim("storeId", Store.ToString()), new Claim(ClaimTypes.Email, "owner@test.local"),
                ], "test")),
            },
        };
        return controller;
    }

    static async Task<Guid> SeedVoucherAsync(string db)
    {
        await using var ctx = NewDb(db);
        var v = new PosVoucher
        {
            Id = Guid.NewGuid(), StoreId = Store, Code = "TET", Name = "Tết", DiscountType = PosVoucherDiscountType.Percent,
            DiscountValue = 10, IsActive = true,
        };
        ctx.PosVouchers.Add(v);
        await ctx.SaveChangesAsync();
        return v.Id;
    }

    [Fact]
    public async Task Sua_voucher_luu_that_vao_csdl()
    {
        var name = Guid.NewGuid().ToString();
        var id = await SeedVoucherAsync(name);
        await using (var ctx = NewDb(name))
        {
            await WithUser(new PosVouchersController(ctx)).Update(id, new PosVouchersController.VoucherSaveDto(
                "TET2027", "Tết 2027", PosVoucherDiscountType.Fixed, 50000, 200000, null, null, null, 100, null));
        }
        await using var check = NewDb(name);
        var v = await check.PosVouchers.SingleAsync(x => x.Id == id);
        Assert.Equal("TET2027", v.Code);
        Assert.Equal(50000, v.DiscountValue);
        Assert.Equal(PosVoucherDiscountType.Fixed, v.DiscountType);
        Assert.Equal(100, v.MaxUses);
    }

    [Fact]
    public async Task Xoa_voucher_an_khoi_danh_sach()
    {
        var name = Guid.NewGuid().ToString();
        var id = await SeedVoucherAsync(name);
        await using (var ctx = NewDb(name))
        {
            await WithUser(new PosVouchersController(ctx)).Delete(id);
        }
        await using var check = NewDb(name);
        // Bộ lọc xóa mềm toàn cục: voucher đã xóa không còn đọc ra.
        Assert.False(await check.PosVouchers.AnyAsync(x => x.Id == id));
        Assert.True(await check.PosVouchers.IgnoreQueryFilters().AnyAsync(x => x.Id == id && x.Deleted != null && !x.IsActive));
    }

    [Fact]
    public async Task Doi_ten_va_xoa_nhom_topping_luu_that()
    {
        var name = Guid.NewGuid().ToString();
        var groupId = Guid.NewGuid();
        var toppingId = Guid.NewGuid();
        await using (var ctx = NewDb(name))
        {
            ctx.PosToppingGroups.Add(new PosToppingGroup { Id = groupId, StoreId = Store, Name = "Topping trà", IsActive = true });
            ctx.PosToppingGroupItems.Add(new PosToppingGroupItem
            {
                Id = Guid.NewGuid(), StoreId = Store, GroupId = groupId, ToppingProductId = toppingId, IsActive = true,
            });
            await ctx.SaveChangesAsync();
        }

        await using (var ctx = NewDb(name))
        {
            // Đổi tên và bỏ hết topping trong nhóm.
            await WithUser(new PosToppingGroupsController(ctx)).Update(groupId,
                new PosToppingGroupsController.ToppingGroupUpsertDto("Topping trà sữa", 2, []));
        }
        await using (var check = NewDb(name))
        {
            var g = await check.PosToppingGroups.SingleAsync(x => x.Id == groupId);
            Assert.Equal("Topping trà sữa", g.Name);
            Assert.Equal(2, g.SortOrder);
            Assert.False(await check.PosToppingGroupItems.AnyAsync(i => i.GroupId == groupId));
        }

        await using (var ctx = NewDb(name))
        {
            await WithUser(new PosToppingGroupsController(ctx)).Delete(groupId);
        }
        await using var after = NewDb(name);
        Assert.False(await after.PosToppingGroups.AnyAsync(x => x.Id == groupId));
    }
}
