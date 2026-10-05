using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using ZKTecoADMS.Application.Authorization;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Helpers;

namespace ZKTecoADMS.Tests;

/// <summary>Tick thêm chức năng vào gói → vai trò được cấp quyền theo mẫu (trước đây không ai thấy menu).</summary>
public class StorePermissionSyncTests
{
    static ZKTecoDbContext NewDb()
    {
        var services = new ServiceCollection();
        services.AddDbContext<ZKTecoDbContext>(o => o.UseInMemoryDatabase(Guid.NewGuid().ToString())
            .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking));
        return services.BuildServiceProvider().CreateScope().ServiceProvider.GetRequiredService<ZKTecoDbContext>();
    }

    static readonly string[] BasePos = ["Home", "PosSell", "PosProducts", "PosSaleOrders", "PosCustomers", "PosSalesReport"];

    [Fact]
    public async Task Them_khuyen_mai_hop_dong_vao_goi_cap_quyen_theo_mau_vai_tro()
    {
        var db = NewDb();
        var pkg = new ServicePackage { Id = Guid.NewGuid(), Name = "POS bán hàng", AllowedModules = JsonSerializer.Serialize(BasePos) };
        var store = new Store { Id = Guid.NewGuid(), Name = "Demo", Code = "demo", ServicePackageId = pkg.Id };
        db.AddRange(pkg, store);
        var perms = new[] { "PosPromotions", "PosQuotes", "PosContracts", "PosSell" }
            .ToDictionary(m => m, m => new Permission { Id = Guid.NewGuid(), Module = m, ModuleDisplayName = m });
        db.AddRange(perms.Values);

        RolePermission Row(string role, string module, bool view = false) => new()
        {
            Id = Guid.NewGuid(), StoreId = store.Id, RoleName = role, RoleDisplayName = role,
            PermissionId = perms[module].Id, CanView = view, IsActive = true,
        };
        // Lúc tạo cửa hàng gói chưa có các chức năng này → dòng quyền trống.
        db.AddRange(Row("Manager", "PosPromotions"), Row("Manager", "PosQuotes"), Row("Manager", "PosSell", view: true),
            Row("Cashier", "PosPromotions"), Row("Cashier", "PosSell", view: true));
        await db.SaveChangesAsync();

        Assert.Equal(1, await StorePermissionSyncHelper.EnsureBaselineAsync(db));

        // Super Admin tick thêm Khuyến mãi + Hợp đồng (Báo giá tự kéo theo).
        var p = await db.ServicePackages.AsTracking().FirstAsync();
        p.AllowedModules = JsonSerializer.Serialize(
            FeatureModuleCatalog.WithDependencies(BasePos.Concat(["PosPromotions", "PosContracts"])));
        await db.SaveChangesAsync();
        Assert.True(await StorePermissionSyncHelper.SyncAsync(db, store.Id) > 0);

        var rows = await db.RolePermissions.Include(r => r.Permission).ToListAsync();
        RolePermission? Get(string role, string module) =>
            rows.FirstOrDefault(r => r.RoleName == role && r.Permission.Module == module);

        Assert.True(Get("Manager", "PosPromotions")!.CanEdit);
        Assert.True(Get("Manager", "PosQuotes")!.CanView);
        Assert.True(Get("Manager", "PosContracts")!.CanView);   // dòng mới
        Assert.False(Get("Cashier", "PosPromotions")!.CanView); // mẫu thu ngân không có khuyến mãi
        Assert.Null(Get("Cashier", "PosContracts"));

        // Lần sau không có gì mới → không đổi gì (giữ chỉnh tay của chủ cửa hàng).
        var editedId = Get("Manager", "PosPromotions")!.Id;
        var edited = await db.RolePermissions.AsTracking().FirstAsync(r => r.Id == editedId);
        edited.CanEdit = false;
        await db.SaveChangesAsync();
        Assert.Equal(0, await StorePermissionSyncHelper.SyncAsync(db, store.Id));
        Assert.False((await db.RolePermissions.FirstAsync(r => r.Id == edited.Id)).CanEdit);
    }

    [Fact]
    public async Task Lan_dau_chua_co_moc_khong_ghi_de_dong_quyen_dang_co()
    {
        var db = NewDb();
        var pkg = new ServicePackage { Id = Guid.NewGuid(), Name = "Gói", AllowedModules = JsonSerializer.Serialize(BasePos.Append("PosPromotions")) };
        var store = new Store { Id = Guid.NewGuid(), Name = "Demo", Code = "demo", ServicePackageId = pkg.Id };
        var promo = new Permission { Id = Guid.NewGuid(), Module = "PosPromotions", ModuleDisplayName = "KM" };
        db.AddRange(pkg, store, promo, new RolePermission
        {
            Id = Guid.NewGuid(), StoreId = store.Id, RoleName = "Manager", RoleDisplayName = "Quản lý",
            PermissionId = promo.Id, IsActive = true, // chủ cửa hàng đã bỏ tick
        });
        await db.SaveChangesAsync();

        Assert.Equal(0, await StorePermissionSyncHelper.SyncAsync(db, store.Id));
        Assert.False((await db.RolePermissions.FirstAsync()).CanView);
    }

    [Fact]
    public void Chuc_nang_ban_hang_moi_keo_theo_quyen_con()
    {
        var added = StorePermissionSyncHelper.AddedModules(
            new HashSet<string>(["Home"]), new HashSet<string>(["Home", "PosSell", "PosProducts"]));
        Assert.Contains("PosSellDiscount", added);
        Assert.Contains("PosViewCost", added);
        Assert.DoesNotContain("Home", added);
    }
}
