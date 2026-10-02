using Xunit;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Middlewares;

namespace ZKTecoADMS.Tests;

/// <summary>Bộ chọn chi nhánh trên đầu app = chi nhánh đang xem: server tự lọc khi màn hình không gửi ?branchId.</summary>
public class BranchViewFilterTests
{
    private static readonly Guid A = Guid.NewGuid(), B = Guid.NewGuid(), Other = Guid.NewGuid();
    private static bool Allowed(Guid id) => id == A || id == B;

    [Fact]
    public void Header_branch_becomes_view_filter()
        => Assert.Equal(A, BranchContextMiddleware.ResolveViewFilter(A.ToString(), null, Allowed));

    [Fact]
    public void Query_branch_overrides_header()
        => Assert.Equal(B, BranchContextMiddleware.ResolveViewFilter(A.ToString(), B.ToString(), Allowed));

    [Fact]
    public void All_or_empty_header_means_no_filter()
    {
        Assert.Null(BranchContextMiddleware.ResolveViewFilter("all", null, Allowed));
        Assert.Null(BranchContextMiddleware.ResolveViewFilter("ALL", null, Allowed));
        Assert.Null(BranchContextMiddleware.ResolveViewFilter(null, null, Allowed));
        Assert.Equal(A, BranchContextMiddleware.ResolveViewFilter("all", A.ToString(), Allowed));
    }

    [Fact]
    public void Disallowed_branch_is_ignored()
    {
        Assert.Null(BranchContextMiddleware.ResolveViewFilter(Other.ToString(), null, Allowed));
        Assert.Equal(A, BranchContextMiddleware.ResolveViewFilter(A.ToString(), Other.ToString(), Allowed));
    }

    [Fact]
    public void In_view_treats_unassigned_employee_as_headquarter()
    {
        var view = new HashSet<Guid> { A };
        Assert.True(BranchViewHelper.InView(null, B, A));       // không lọc
        Assert.True(BranchViewHelper.InView(view, A, B));
        Assert.False(BranchViewHelper.InView(view, B, A));
        Assert.True(BranchViewHelper.InView(view, null, A));    // chưa gán → trụ sở
        Assert.False(BranchViewHelper.InView(view, null, B));
    }
}
