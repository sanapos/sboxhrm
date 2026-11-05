using Xunit;
using ZKTecoADMS.Application.Commands.Accounts;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests;

/// <summary>Hồ sơ nhân viên chỉ gắn được vào tài khoản cùng cửa hàng, khi hồ sơ còn làm việc và chưa thuộc tài khoản khác.</summary>
public class EmployeeAccountLinkTests
{
    static readonly Guid Store = Guid.NewGuid();
    static readonly Guid User = Guid.NewGuid();

    static Employee Emp(Guid? store = null, Guid? owner = null, EmployeeWorkStatus status = EmployeeWorkStatus.Active, DateTime? deleted = null) => new()
    {
        Id = Guid.NewGuid(),
        StoreId = store ?? Store,
        ApplicationUserId = owner,
        WorkStatus = status,
        Deleted = deleted,
    };

    [Fact]
    public void Free_employee_in_same_store_can_link() => Assert.Null(EmployeeAccountLink.Deny(Emp(), Store, User));

    [Fact]
    public void Relinking_the_same_account_is_allowed() => Assert.Null(EmployeeAccountLink.Deny(Emp(owner: User), Store, User));

    [Fact]
    public void Missing_employee_is_denied() => Assert.NotNull(EmployeeAccountLink.Deny(null, Store, User));

    [Fact]
    public void Employee_of_another_store_is_denied() => Assert.NotNull(EmployeeAccountLink.Deny(Emp(store: Guid.NewGuid()), Store, User));

    [Fact]
    public void Deleted_employee_is_denied() => Assert.NotNull(EmployeeAccountLink.Deny(Emp(deleted: DateTime.UtcNow), Store, User));

    [Fact]
    public void Resigned_employee_is_denied() => Assert.NotNull(EmployeeAccountLink.Deny(Emp(status: EmployeeWorkStatus.Resigned), Store, User));

    [Fact]
    public void Employee_owned_by_another_account_is_denied() => Assert.NotNull(EmployeeAccountLink.Deny(Emp(owner: Guid.NewGuid()), Store, User));

    [Fact]
    public void New_account_cannot_take_an_owned_employee() => Assert.NotNull(EmployeeAccountLink.Deny(Emp(owner: Guid.NewGuid()), Store));
}
