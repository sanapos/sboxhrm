using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Application.Exceptions;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Interceptors;

namespace ZKTecoADMS.Tests;

/// <summary>
/// Người dùng bị giới hạn chi nhánh: chỉ ghi chứng từ trong chi nhánh được phép,
/// và theo cờ Thêm / Sửa / Xóa của phân quyền chi nhánh (nếu có).
/// </summary>
public class BranchWriteGuardTests
{
    private readonly Guid _store = Guid.NewGuid();
    private readonly Guid _hq = Guid.NewGuid();
    private readonly Guid _a = Guid.NewGuid();
    private readonly Guid _user = Guid.NewGuid();
    private readonly BranchContext _ctx = new();

    private ZKTecoDbContext NewDb(string name) => new(new DbContextOptionsBuilder<ZKTecoDbContext>()
        .UseInMemoryDatabase(name)
        .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking)
        .AddInterceptors(new BranchStockInterceptor(_ctx))
        .Options);

    private async Task<string> SeedAsync(bool? canCreateAtA = null)
    {
        var name = Guid.NewGuid().ToString();
        await using var db = NewDb(name);
        db.Branches.AddRange(
            new Branch { Id = _hq, StoreId = _store, Code = "HQ", Name = "Trụ sở", IsHeadquarter = true, IsActive = true },
            new Branch { Id = _a, StoreId = _store, Code = "A", Name = "Chi nhánh A", IsActive = true });
        if (canCreateAtA is bool c)
            db.BranchPermissions.Add(new BranchPermission
            {
                Id = Guid.NewGuid(), UserId = _user, BranchId = _a, StoreId = _store,
                CanView = true, CanCreate = c, CanEdit = true, CanDelete = false, IsActive = true,
            });
        await db.SaveChangesAsync();
        return name;
    }

    private void RestrictTo(params Guid[] branches)
    {
        _ctx.StoreUsesBranches = true;
        _ctx.HeadquarterBranchId = _hq;
        _ctx.UserId = _user;
        _ctx.RestrictWrites = true;
        _ctx.AllowedBranchIds = branches;
        _ctx.CurrentBranchId = branches.FirstOrDefault();
    }

    [Fact]
    public async Task Ghi_trong_chi_nhanh_duoc_phep()
    {
        var name = await SeedAsync();
        RestrictTo(_a);
        await using var db = NewDb(name);
        db.CashTransactions.Add(new CashTransaction { Id = Guid.NewGuid(), StoreId = _store, Amount = 50 });
        await db.SaveChangesAsync();
        Assert.Equal(_a, (await db.CashTransactions.FirstAsync()).BranchId);
    }

    [Fact]
    public async Task Chan_ghi_chung_tu_chi_nhanh_khac()
    {
        var name = await SeedAsync();
        RestrictTo(_a);
        await using var db = NewDb(name);
        db.PosSaleOrders.Add(new PosSaleOrder { Id = Guid.NewGuid(), StoreId = _store, OrderNo = "HD1", BranchId = _hq });
        await Assert.ThrowsAsync<ForbiddenException>(() => db.SaveChangesAsync());
    }

    [Fact]
    public async Task Co_phan_quyen_chi_nhanh_khong_tick_Them_thi_chan()
    {
        var name = await SeedAsync(canCreateAtA: false);
        RestrictTo(_a);
        await using var db = NewDb(name);
        db.CashTransactions.Add(new CashTransaction { Id = Guid.NewGuid(), StoreId = _store, Amount = 50 });
        await Assert.ThrowsAsync<ForbiddenException>(() => db.SaveChangesAsync());
    }

    [Fact]
    public async Task Chu_cua_hang_khong_bi_gioi_han()
    {
        var name = await SeedAsync(canCreateAtA: false);
        _ctx.StoreUsesBranches = true;
        _ctx.UserId = _user;
        _ctx.RestrictWrites = false; // chủ / quản trị / kế toán
        _ctx.CurrentBranchId = _hq;
        await using var db = NewDb(name);
        db.PosSaleOrders.Add(new PosSaleOrder { Id = Guid.NewGuid(), StoreId = _store, OrderNo = "HD2", BranchId = _a });
        await db.SaveChangesAsync();
        Assert.Single(await db.PosSaleOrders.ToListAsync());
    }
}
