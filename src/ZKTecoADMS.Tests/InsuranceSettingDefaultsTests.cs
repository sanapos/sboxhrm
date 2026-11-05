using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Queries.Settings;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Repositories;

namespace ZKTecoADMS.Tests;

/// <summary>Mức bảo hiểm mặc định chỉ dùng khi cửa hàng chưa lưu thiết lập; mức đã lưu không bị đổi theo.</summary>
public class InsuranceSettingDefaultsTests
{
    sealed class NoTenant : ITenantProvider
    {
        public Guid? StoreId => null;
        public bool IsSuperAccess => true;
    }

    static ZKTecoDbContext Db() => new(new DbContextOptionsBuilder<ZKTecoDbContext>()
        .UseInMemoryDatabase(Guid.NewGuid().ToString())
        .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking)
        .Options);

    static GetInsuranceSettingsHandler Handler(ZKTecoDbContext db) => new(
        new EfRepository<InsuranceSetting>(db, NullLogger<EfRepository<InsuranceSetting>>.Instance, new NoTenant()));

    [Fact]
    public void Mac_dinh_theo_luong_co_so_tu_01_07_2026()
    {
        var s = new InsuranceSetting();
        Assert.Equal(2_530_000m, s.BaseSalary);
        Assert.Equal(s.BaseSalary * 20, s.MaxInsuranceSalary);
    }

    [Fact]
    public async Task Cua_hang_chua_luu_thiet_lap_nhan_mac_dinh_moi_va_khong_tao_ban_ghi()
    {
        using var db = Db();
        var r = await Handler(db).Handle(new GetInsuranceSettingsQuery(Guid.NewGuid()), default);
        Assert.Equal(50_600_000m, r.Data!.MaxInsuranceSalary);
        Assert.Equal(0, await db.InsuranceSettings.CountAsync());
    }

    [Fact]
    public async Task Cua_hang_da_luu_muc_cu_van_giu_muc_cua_minh()
    {
        using var db = Db();
        var store = Guid.NewGuid();
        db.InsuranceSettings.Add(new InsuranceSetting
        {
            Id = Guid.NewGuid(), StoreId = store, BaseSalary = 2_340_000, MaxInsuranceSalary = 46_800_000,
        });
        await db.SaveChangesAsync();

        var r = await Handler(db).Handle(new GetInsuranceSettingsQuery(store), default);

        Assert.Equal(2_340_000m, r.Data!.BaseSalary);
        Assert.Equal(46_800_000m, r.Data.MaxInsuranceSalary);
    }
}
