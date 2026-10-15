using Xunit;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure.Helpers;

namespace ZKTecoADMS.Tests;

/// <summary>Giới hạn đang áp dụng = riêng cửa hàng ?? gói ?? giá trị trên cửa hàng.</summary>
public class StoreLimitsTests
{
    private static Store StoreWith(ServicePackage? pkg, string? overrides = null) => new()
    {
        Name = "S", Code = "s", MaxBranches = 9, MaxUsers = 9, MaxDevices = 9, AllowFcm = true,
        ServicePackage = pkg, ServicePackageId = pkg?.Id, LimitOverridesJson = overrides,
    };

    private static ServicePackage Pkg(int branches = 1, int users = 5, int devices = 2, bool fcm = true, string cats = "[\"pos\"]") => new()
    {
        Name = "P", MaxBranches = branches, MaxUsers = users, MaxDevices = devices, AllowFcm = fcm, AllowedFcmCategories = cats,
    };

    [Fact]
    public void NoOverride_FollowsPackage_NotStoreColumns()
    {
        var l = StorePackageHelper.ResolveLimits(StoreWith(Pkg(branches: 1)));
        Assert.Equal(1, l.MaxBranches);
        Assert.Equal(5, l.MaxUsers);
        Assert.False(l.BranchesOverridden);
        Assert.Equal(["pos"], l.FcmCategories);
    }

    [Fact]
    public void Override_WinsOverPackage_AndZeroMeansUnlimited()
    {
        var s = StoreWith(Pkg(branches: 1), StorePackageHelper.SerializeLimitOverrides(new StorePackageHelper.StoreLimitOverrides(MaxBranches: 5, MaxUsers: 0)));
        var l = StorePackageHelper.ResolveLimits(s);
        Assert.Equal(5, l.MaxBranches);
        Assert.True(l.BranchesOverridden);
        Assert.Equal(0, l.MaxUsers);       // 0 = không giới hạn
        Assert.Equal(2, l.MaxDevices);     // không đặt riêng → theo gói
    }

    [Fact]
    public void Override_Notifications_OffAndCategories()
    {
        var off = StorePackageHelper.ResolveLimits(StoreWith(Pkg(), StorePackageHelper.SerializeLimitOverrides(new(AllowFcm: false))));
        Assert.False(off.AllowFcm);
        var cats = StorePackageHelper.ResolveLimits(StoreWith(Pkg(), StorePackageHelper.SerializeLimitOverrides(new(FcmCategories: ["hr", "payroll"]))));
        Assert.True(cats.AllowFcm);
        Assert.Equal(2, cats.FcmCategories.Count);
        Assert.Contains("hr", cats.FcmCategories);
    }

    [Fact]
    public void NoPackage_FallsBackToStoreColumns()
    {
        var l = StorePackageHelper.ResolveLimits(StoreWith(null));
        Assert.Equal(9, l.MaxBranches);
        Assert.Equal(9, l.MaxUsers);
    }

    [Fact]
    public void EmptyOverrides_AreStoredAsNull_AndCorruptJsonIsIgnored()
    {
        Assert.Null(StorePackageHelper.SerializeLimitOverrides(new StorePackageHelper.StoreLimitOverrides()));
        var l = StorePackageHelper.ResolveLimits(StoreWith(Pkg(branches: 2), "{không phải json"));
        Assert.Equal(2, l.MaxBranches);
    }

    [Fact]
    public void Override_SurvivesRoundTrip()
    {
        var json = StorePackageHelper.SerializeLimitOverrides(new StorePackageHelper.StoreLimitOverrides(MaxBranches: 3, AllowFcm: true));
        var o = StorePackageHelper.ParseLimitOverrides(json);
        Assert.Equal(3, o.MaxBranches);
        Assert.True(o.AllowFcm);
        Assert.Null(o.MaxUsers);
    }
}
