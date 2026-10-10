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
    [Fact]
    public void Quyen_mac_dinh_khi_thieu_dong_theo_mau_khong_theo_bang_cu()
    {
        var pos = new HashSet<string>(["PosSell", "PosProducts", "PosReportProfit", "PosReportCashbook", "PosSalesReport"],
            StringComparer.OrdinalIgnoreCase);
        // Bảng cũ cho thu ngân xem báo cáo lợi nhuận / sổ quỹ, sửa giá, hủy hóa đơn đã thu — mẫu thì không.
        Assert.False(PermissionPresetCatalog.DefaultFlags("Cashier", "PosReportProfit", pos).Any);
        Assert.False(PermissionPresetCatalog.DefaultFlags("Cashier", "PosReportCashbook", pos).Any);
        Assert.False(PermissionPresetCatalog.DefaultFlags("Cashier", "PosSellCancelPaid", pos).Any);
        Assert.True(PermissionPresetCatalog.DefaultFlags("Cashier", "PosSell", pos).A);
        Assert.True(PermissionPresetCatalog.DefaultFlags("Admin", "PosReportProfit", pos).D);
        Assert.False(PermissionPresetCatalog.DefaultFlags("ThuKhoTuDat", "PosProducts", pos).Any);
        // Nhân viên (HRM): tự phục vụ, không xem bảng lương cửa hàng.
        var hrm = new HashSet<string>(["Attendance", "Leave", "Payroll", "SalarySettings"], StringComparer.OrdinalIgnoreCase);
        Assert.False(PermissionPresetCatalog.DefaultFlags("Employee", "Payroll", hrm).Any);
        Assert.False(PermissionPresetCatalog.DefaultFlags("Employee", "SalarySettings", hrm).Any);
        Assert.True(PermissionPresetCatalog.DefaultFlags("Employee", "Leave", hrm).C);
    }

    [Fact]
    public void Giam_doc_theo_bang_quyen_va_chot_luong_can_quyen_duyet()
    {
        Assert.False(ModulePermissionDefaults.IsSuperRole("Director"));
        Assert.True(ModulePermissionDefaults.IsSuperRole("Admin"));
        foreach (var id in new[] { "hrm.director", "hrm.manager", "hrm.accountant", "full.director", "full.manager", "full.accountant" })
            Assert.True(PermissionPresetCatalog.Build(id)["Payroll"].A, id);
        Assert.False(PermissionPresetCatalog.Build("hrm.depthead").TryGetValue("Payroll", out var f) && f.A);
    }
}
