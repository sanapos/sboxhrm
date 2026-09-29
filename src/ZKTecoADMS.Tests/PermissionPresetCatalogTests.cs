using Xunit;
using ZKTecoADMS.Application.Authorization;

namespace ZKTecoADMS.Tests;

public class PermissionPresetCatalogTests
{
    static readonly HashSet<string> CatalogCodes =
        FeatureModuleCatalog.All.Select(m => m.Code).ToHashSet(StringComparer.OrdinalIgnoreCase);

    [Fact]
    public void Moi_mau_chi_dung_ma_chuc_nang_co_that()
    {
        foreach (var preset in PermissionPresetCatalog.List())
        {
            var unknown = PermissionPresetCatalog.Build(preset.Id).Keys.Where(k => !CatalogCodes.Contains(k)).ToList();
            Assert.True(unknown.Count == 0, $"{preset.Id}: mã không có trong danh mục: {string.Join(", ", unknown)}");
        }
    }

    [Theory]
    [InlineData(PermissionPresetPackage.Hrm)]
    [InlineData(PermissionPresetPackage.Pos)]
    [InlineData(PermissionPresetPackage.Full)]
    public void Bo_mac_dinh_tro_dung_mau_cua_vai_tro(PermissionPresetPackage package)
    {
        foreach (var (role, id) in PermissionPresetCatalog.Defaults(package))
        {
            var preset = PermissionPresetCatalog.Find(id);
            Assert.NotNull(preset);
            Assert.True(preset!.FitsRole(role), $"{id} không áp được cho {role}");
        }
    }

    [Fact]
    public void Nhan_dien_goi()
    {
        Assert.Equal(PermissionPresetPackage.Hrm, PermissionPresetCatalog.Detect(["Home", "Attendance", "Leave", "Payslip"]));
        Assert.Equal(PermissionPresetPackage.Pos, PermissionPresetCatalog.Detect(["Home", "PosSell", "PosProducts", "Payslip"]));
        Assert.Equal(PermissionPresetPackage.Full, PermissionPresetCatalog.Detect(["Attendance", "PosSell"]));
        Assert.Equal(PermissionPresetPackage.Full, PermissionPresetCatalog.Detect(null));
    }

    [Fact]
    public void Thu_ngan_thanh_toan_duoc_nhung_khong_sua_gia_huy_don_xem_gia_von()
    {
        var p = PermissionPresetCatalog.Build("pos.cashier");
        Assert.True(p["PosSell"].A);
        Assert.True(p["PosSellDiscount"].E);
        Assert.False(p.ContainsKey("PosSellPriceEdit"));
        Assert.False(p.ContainsKey("PosSellCancelPaid"));
        Assert.False(p.ContainsKey("PosViewCost"));
    }

    [Fact]
    public void Nhan_vien_chi_tu_phuc_vu()
    {
        var p = PermissionPresetCatalog.Build("hrm.employee");
        Assert.False(p.ContainsKey("Payroll"));
        Assert.False(p["Employee"].E);
        Assert.False(p["Leave"].A);
        Assert.True(p["Leave"].C);
    }

    [Fact]
    public void Chuc_nang_ngoai_goi_khong_duoc_cap()
    {
        var p = PermissionPresetCatalog.Build("full.cashier");
        var posOnly = new HashSet<string>(["PosSell", "PosProducts"], StringComparer.OrdinalIgnoreCase);
        Assert.False(PermissionPresetCatalog.FlagsFor(p, "Leave", posOnly).Any);          // gói không có nghỉ phép
        Assert.True(PermissionPresetCatalog.FlagsFor(p, "PosSellDiscount", posOnly).E);   // quyền con đi theo Bán hàng
        Assert.True(PermissionPresetCatalog.FlagsFor(p, "Payslip", posOnly).V);           // tự phục vụ luôn có
    }
}
