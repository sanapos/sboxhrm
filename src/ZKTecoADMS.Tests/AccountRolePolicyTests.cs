using Xunit;
using ZKTecoADMS.Application.Authorization;

namespace ZKTecoADMS.Tests;

/// <summary>Phân cấp vai trò: không ai tự nâng quyền hoặc chiếm tài khoản cấp cao hơn.</summary>
public class AccountRolePolicyTests
{
    [Theory]
    [InlineData("Admin", true, "SuperAdmin", false)]
    [InlineData("Admin", true, "Agent", false)]
    [InlineData("Director", false, "SuperAdmin", false)]
    [InlineData("Director", false, "Admin", false)]
    [InlineData("Director", false, "Director", false)]
    [InlineData("Director", false, "Manager", true)]
    [InlineData("Manager", false, "Manager", false)]
    [InlineData("Manager", false, "Accountant", true)]
    [InlineData("Manager", false, "Cashier", true)]
    [InlineData("Admin", false, "Admin", false)]   // Admin không phải chủ
    [InlineData("Admin", false, "Director", true)]
    [InlineData("Admin", true, "Admin", true)]     // chủ cửa hàng
    [InlineData("SuperAdmin", false, "Agent", true)]
    [InlineData("Manager", false, "Bogus", false)]
    public void Assign(string actor, bool owner, string role, bool ok) =>
        Assert.Equal(ok, AccountRolePolicy.CanAssign(actor, owner, role) == null);

    [Theory]
    [InlineData("Manager", false, "Admin", false, false)]   // quản lý không đặt lại mật khẩu chủ / admin
    [InlineData("Manager", false, "Director", false, false)]
    [InlineData("Manager", false, "Manager", false, false)]
    [InlineData("Manager", false, "Employee", false, true)]
    [InlineData("Admin", false, "Admin", true, false)]      // admin khác không đụng được chủ
    [InlineData("Admin", true, "Admin", false, true)]       // chủ quản lý admin khác
    [InlineData("Admin", true, "SuperAdmin", false, false)]
    [InlineData("SuperAdmin", false, "Admin", true, true)]
    public void Manage(string actor, bool actorOwner, string target, bool targetOwner, bool ok) =>
        Assert.Equal(ok, AccountRolePolicy.CanManage(actor, actorOwner, target, targetOwner) == null);

    [Theory]
    [InlineData("Director", false, "Director", false)]  // không tự nâng quyền vai trò mình
    [InlineData("Director", false, "Manager", true)]
    [InlineData("Director", false, "Admin", false)]
    [InlineData("Admin", true, "Director", true)]
    [InlineData("Admin", true, "Admin", false)]
    [InlineData("Manager", false, "Thủ kho ca đêm", true)] // chức danh tự đặt
    public void EditRole(string actor, bool owner, string role, bool ok) =>
        Assert.Equal(ok, AccountRolePolicy.CanEditRole(actor, owner, role) == null);

    [Fact]
    public void Assignable_list_never_contains_platform_roles_for_store_owner()
    {
        var roles = AccountRolePolicy.AssignableRoles("Admin", true);
        Assert.DoesNotContain("SuperAdmin", roles);
        Assert.DoesNotContain("Agent", roles);
        Assert.Contains("Admin", roles);
        Assert.Contains("Cashier", roles);
    }
}
