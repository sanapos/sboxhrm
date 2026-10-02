using Xunit;
using ZKTecoADMS.Application.Authorization;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure.Helpers;

namespace ZKTecoADMS.Tests;

/// <summary>Quản trị Super Admin v2: danh mục chức năng, phụ thuộc, mẫu gói, chức năng riêng theo cửa hàng.</summary>
public class SuperAdminV2Tests
{
    [Fact]
    public void Catalog_codes_unique_and_categories_known()
    {
        var codes = FeatureModuleCatalog.All.Select(m => m.Code).ToList();
        Assert.Equal(codes.Count, codes.Distinct(StringComparer.OrdinalIgnoreCase).Count());
        foreach (var m in FeatureModuleCatalog.PackageSelectable)
            Assert.Contains(m.Category, FeatureModuleCatalog.CategoryOrder);
        // Thứ tự trong gói không trùng
        var orders = FeatureModuleCatalog.PackageSelectable.Select(m => m.Order).ToList();
        Assert.Equal(orders.Count, orders.Distinct().Count());
        // Chức năng mới có trong danh mục
        Assert.Contains("AIAssistant", codes);
        Assert.Contains("PosHub", codes);
        Assert.False(FeatureModuleCatalog.IsSelfService("MobileAttendance"));
        Assert.True(FeatureModuleCatalog.IsSelfService("Payslip"));
    }

    [Fact]
    public void Requires_point_to_existing_selectable_codes()
    {
        var all = FeatureModuleCatalog.AllCodes;
        var selectable = FeatureModuleCatalog.PackageSelectable.Select(m => m.Code).ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var (code, reqs) in FeatureModuleCatalog.Requires)
        {
            Assert.Contains(code, all);
            foreach (var r in reqs) Assert.Contains(r, selectable);
        }
    }

    [Fact]
    public void Presets_are_complete_and_dependency_closed()
    {
        var keys = FeatureModuleCatalog.Presets.Select(p => p.Key).ToList();
        Assert.Equal(new[] { "pos_basic", "pos_warehouse", "pos_full", "hrm_basic", "hrm_full", "all" }, keys);
        foreach (var p in FeatureModuleCatalog.Presets)
        {
            Assert.Empty(FeatureModuleCatalog.MissingDependencies(p.Modules));
            Assert.All(p.Modules, m => Assert.Contains(m, FeatureModuleCatalog.AllCodes));
        }
        var full = FeatureModuleCatalog.Presets.First(p => p.Key == "pos_full").Modules;
        var wh = FeatureModuleCatalog.Presets.First(p => p.Key == "pos_warehouse").Modules;
        Assert.Contains("PosKds", full);
        Assert.DoesNotContain("PosKds", wh);           // «đầy đủ» khác «bán + kho»
        Assert.True(full.Count > wh.Count);
        Assert.DoesNotContain(FeatureModuleCatalog.Presets.First(p => p.Key == "pos_basic").Modules, m => m == "Payroll");
        Assert.Contains("Payroll", FeatureModuleCatalog.Presets.First(p => p.Key == "hrm_basic").Modules);
    }

    [Fact]
    public void Missing_dependencies_and_auto_fix()
    {
        var missing = FeatureModuleCatalog.MissingDependencies(["PenaltyReport", "Payroll"]);
        Assert.Contains(missing, m => m.Code == "PenaltyReport" && m.Missing == "PenaltyTickets");
        Assert.Contains(missing, m => m.Code == "Payroll" && m.Missing == "AttendanceSummary");
        var fixedSet = FeatureModuleCatalog.WithDependencies(["Payroll"]);
        Assert.Contains("AttendanceSummary", fixedSet);
        Assert.Contains("Attendance", fixedSet);
        Assert.Contains("Employee", fixedSet);
        Assert.Empty(FeatureModuleCatalog.MissingDependencies(fixedSet));
    }

    [Fact]
    public void Store_overrides_add_and_block_modules()
    {
        var store = new Store { ExtraModules = "[\"PosKds\",\"Payroll\"]", BlockedModules = "[\"PosQrOrder\",\"Payroll\"]" };
        var eff = StorePackageHelper.ApplyStoreOverrides(store, ["PosSell", "PosQrOrder"]);
        Assert.Contains("PosSell", eff);
        Assert.Contains("PosKds", eff);
        Assert.DoesNotContain("PosQrOrder", eff);
        Assert.DoesNotContain("Payroll", eff); // chặn thắng nếu cùng có trong 2 danh sách
        Assert.Equal(new List<string> { "A" }, StorePackageHelper.ApplyStoreOverrides(new Store(), ["A"]));
    }
}
