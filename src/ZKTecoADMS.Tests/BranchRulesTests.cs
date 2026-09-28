using Xunit;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Tests;

/// <summary>Chọn trụ sở (tồn trụ sở tính ngầm) + kiểm quyền chi nhánh.</summary>
public class BranchRulesTests
{
    private static BranchStockService.BranchInfo B(string code, bool hq = false, bool active = true, Guid? parent = null, int sort = 0)
        => new(Guid.NewGuid(), code, code, parent, hq, active, sort);

    [Fact]
    public void Tru_so_uu_tien_co_danh_dau()
    {
        var a = B("A"); var hq = B("HQ", hq: true); var c = B("C");
        Assert.Equal(hq.Id, BranchStockService.ResolveHeadquarter([a, hq, c]));
    }

    [Fact]
    public void Khong_danh_dau_thi_lay_chi_nhanh_goc_dang_hoat_dong()
    {
        var root = B("ROOT", active: false);
        var child = B("CHILD", parent: Guid.NewGuid());
        var root2 = B("ROOT2");
        Assert.Equal(root2.Id, BranchStockService.ResolveHeadquarter([root, child, root2]));
    }

    [Fact]
    public void Chua_co_chi_nhanh_thi_khong_co_tru_so() =>
        Assert.Null(BranchStockService.ResolveHeadquarter([]));

    [Fact]
    public void Kiem_quyen_truy_cap_chi_nhanh()
    {
        var a = Guid.NewGuid();
        var b = Guid.NewGuid();
        IBranchContext none = new BranchContext { StoreUsesBranches = false };
        Assert.True(none.CanAccess(b)); // chưa dùng chi nhánh → không chặn

        IBranchContext all = new BranchContext { StoreUsesBranches = true, AllowedBranchIds = null };
        Assert.True(all.CanAccess(b));

        IBranchContext scoped = new BranchContext { StoreUsesBranches = true, AllowedBranchIds = [a] };
        Assert.True(scoped.CanAccess(a));
        Assert.False(scoped.CanAccess(b));
        Assert.False(scoped.CanAccess(null));
    }
}
