using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Api.Middlewares;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Permissions;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>
/// Chức năng mới gắn gói / phân quyền: Check-in gym là chức năng gói riêng; «Điều chỉnh công nợ & hạn mức»
/// là quyền con của Khách hàng chỉ chủ / quản lý / kế toán có.
/// </summary>
[Collection("pos-pg")]
public class PosPackagePermissionTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    [Theory]
    [InlineData("/api/pos/gym/visits", "PosGymCheckIn")]
    [InlineData("/api/pos/gym/balances/1/freeze", "PosGymCheckIn")]
    [InlineData("/api/pos/customers/1/debt-adjust", "PosCustomers")]
    [InlineData("/api/pos/sales", "PosSell")]
    public void Api_gym_thuoc_chuc_nang_goi_rieng(string path, string module) =>
        Assert.Equal(module, StorePackageModuleMiddleware.ResolveModule(path));

    [Fact]
    public void Danh_muc_goi_co_gym_va_quyen_con_no()
    {
        var gym = FeatureModuleCatalog.All.Single(m => m.Code == "PosGymCheckIn");
        Assert.True(gym.SelectableForPackage);
        Assert.Equal(["PosSell"], FeatureModuleCatalog.Requires["PosGymCheckIn"]);
        // Quyền con không chọn theo gói — đi theo Khách hàng.
        Assert.False(FeatureModuleCatalog.All.Single(m => m.Code == "PosDebtAdjust").SelectableForPackage);
        Assert.Contains("PosGymCheckIn", FeatureModuleCatalog.Presets.Single(p => p.Key == "pos_full").Modules);
        Assert.DoesNotContain("PosGymCheckIn", FeatureModuleCatalog.Presets.Single(p => p.Key == "pos_basic").Modules);
    }

    [Fact]
    public void Mau_vai_tro_gym_va_dieu_chinh_no()
    {
        // Gói bán lẻ không có gym → không ai được cấp mặc định.
        var retail = new HashSet<string>(["PosSell", "PosCustomers", "PosProducts", "PosPurchaseReceipts"]);
        Assert.False(PermissionPresetCatalog.DefaultFlags("Manager", "PosGymCheckIn", retail).V);
        // Quyền con theo cha: gói có Khách hàng là có PosDebtAdjust.
        Assert.True(PermissionPresetCatalog.DefaultFlags("Manager", "PosDebtAdjust", retail).E);
        Assert.True(PermissionPresetCatalog.DefaultFlags("Accountant", "PosDebtAdjust", retail).E);
        Assert.False(PermissionPresetCatalog.DefaultFlags("Cashier", "PosDebtAdjust", retail).E);
        Assert.False(PermissionPresetCatalog.DefaultFlags("DepartmentHead", "PosDebtAdjust", retail).E); // thủ kho

        var gymPkg = new HashSet<string>(retail) { "PosGymCheckIn" };
        var cashier = PermissionPresetCatalog.DefaultFlags("Cashier", "PosGymCheckIn", gymPkg);
        Assert.True(cashier.V && cashier.C);   // check-in, mở cửa, thêm hội viên lên máy
        Assert.False(cashier.E);                    // không bảo lưu / sửa khung giờ / gỡ hội viên
        Assert.True(PermissionPresetCatalog.DefaultFlags("Manager", "PosGymCheckIn", gymPkg).E);
        Assert.True(PermissionPresetCatalog.DefaultFlags("Director", "PosGymCheckIn", gymPkg).E);
    }

    [Fact]
    public void Api_gym_va_dieu_chinh_no_dung_ma_quyen()
    {
        static string Perm(Type t, string method) => t.GetMethod(method)!
            .GetCustomAttributes(typeof(RequireModulePermissionAttribute), false).Cast<RequireModulePermissionAttribute>()
            .Select(a => $"{a.Arguments[0]}:{a.Arguments[1]}").Single();

        var gym = typeof(PosGymController);
        Assert.Equal("PosGymCheckIn:Create", Perm(gym, nameof(PosGymController.CheckIn)));
        Assert.Equal("PosGymCheckIn:Create", Perm(gym, nameof(PosGymController.OpenDoor)));
        Assert.Equal("PosGymCheckIn:Create", Perm(gym, nameof(PosGymController.AddMember)));
        Assert.Equal("PosGymCheckIn:Edit", Perm(gym, nameof(PosGymController.RemoveMember)));
        Assert.Equal("PosGymCheckIn:Edit", Perm(gym, nameof(PosGymController.Freeze)));
        Assert.Equal("PosGymCheckIn:Edit", Perm(gym, nameof(PosGymController.SetAccessHours)));
        Assert.Equal("Device:Edit", Perm(gym, nameof(PosGymController.SetDoorMode)));
        Assert.Equal("PosDebtAdjust:Edit", Perm(typeof(PosCustomersController), nameof(PosCustomersController.AdjustDebt)));
        Assert.Equal("PosDebtAdjust:Edit", Perm(typeof(PosPurchaseSuppliersController), nameof(PosPurchaseSuppliersController.AdjustDebt)));
    }

    sealed class FakePerms(bool allow) : IModulePermissionService
    {
        public Task<IReadOnlyDictionary<string, ModulePermissionDto>> GetEffectivePermissionsAsync(
            Guid userId, string role, Guid? storeId, CancellationToken cancellationToken = default) =>
            Task.FromResult<IReadOnlyDictionary<string, ModulePermissionDto>>(new Dictionary<string, ModulePermissionDto>());

        public Task<bool> HasPermissionAsync(Guid userId, string role, Guid? storeId, string module,
            ModulePermissionAction action, CancellationToken cancellationToken = default) =>
            Task.FromResult(allow || module != "PosDebtAdjust");
    }

    static PosCustomersController Customers(ZKTecoADMS.Infrastructure.ZKTecoDbContext db, Guid store, bool canAdjust)
    {
        var ctl = PosPgFixture.As(new PosCustomersController(db), store, "Cashier");
        var sc = new ServiceCollection();
        sc.AddSingleton<IModulePermissionService>(new FakePerms(canAdjust));
        ctl.HttpContext.RequestServices = sc.BuildServiceProvider();
        return ctl;
    }

    static PosCustomersController.CustomerSaveDto Save(string name, decimal? limit, int? term) =>
        new(name, null, null, null, null, null, null, null, null, null, null, null, null, limit, term, true);

    [Fact]
    public async Task Thu_ngan_khong_doi_duoc_han_muc_no()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        Guid id;
        // Quản lý (có quyền) đặt hạn mức 5tr / 30 ngày.
        await using (var db = Fx.NewDb())
            id = Data(await Customers(db, store, true).Create(Save("Anh Tư", 5_000_000, 30))).Id;

        await using (var db = Fx.NewDb())
        {
            var ctl = Customers(db, store, false);
            // Thu ngân sửa tên, form gửi lại số cũ → được.
            Data(await ctl.Update(id, Save("Anh Tư (Q7)", 5_000_000, 30)));
            // Đổi hạn mức → 403.
            var r = await ctl.Update(id, Save("Anh Tư (Q7)", 50_000_000, 30));
            Assert.Equal(403, (r.Result as ObjectResult)?.StatusCode);
            // Tạo khách mới kèm hạn mức → 403; không kèm → được.
            Assert.Equal(403, ((await ctl.Create(Save("Chị Năm", 1_000_000, null))).Result as ObjectResult)?.StatusCode);
            Data(await ctl.Create(Save("Chị Năm", null, null)));
        }
        await using (var db = Fx.NewDb())
        {
            var c = await db.Set<PosCustomer>().FindAsync(id);
            Assert.Equal("Anh Tư (Q7)", c!.Name);
            Assert.Equal(5_000_000, c.DebtLimit);
            Assert.Equal(30, c.PaymentTermDays);
        }
    }
}
