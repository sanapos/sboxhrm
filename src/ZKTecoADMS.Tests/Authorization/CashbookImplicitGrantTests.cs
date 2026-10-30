using Xunit;
using ZKTecoADMS.Application.Authorization;
using ZKTecoADMS.Application.DTOs.Permissions;
using ZKTecoADMS.Application.Constants;

namespace ZKTecoADMS.Tests.Authorization;

public class CashbookImplicitGrantTests
{
    private static Dictionary<string, ModulePermissionDto> Map(params string[] viewModules) =>
        viewModules.ToDictionary(m => m, m => new ModulePermissionDto { Module = m, CanView = true });

    [Theory]
    [InlineData("BonusPenalty")]
    [InlineData("Transaction")]
    public void Viewing_own_rewards_does_not_open_cashbook(string granted) =>
        // Nhân viên xem thưởng/phạt của mình không được thấy sổ quỹ cả cửa hàng.
        Assert.False(ModulePermissionImplicitGrants.TryGrant("CashTransaction", ModulePermissionAction.View, Map(granted)));

    [Fact]
    public void Cashbook_still_implies_rewards() =>
        Assert.True(ModulePermissionImplicitGrants.TryGrant("BonusPenalty", ModulePermissionAction.View, Map("CashTransaction")));
}
