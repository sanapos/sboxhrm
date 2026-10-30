using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Application.DTOs.ShiftSalaryLevels;

namespace ZKTecoADMS.Tests.Authorization;

public class ShiftSalaryLevelScopeTests
{
    private static readonly Guid Me = Guid.NewGuid();

    private static ShiftSalaryLevelDto Level(string? ids) => new() { EmployeeIds = ids };

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("[]")]
    public void Level_for_everyone_is_visible(string? ids) =>
        Assert.True(ShiftSalaryLevelsController.AppliesTo(Level(ids), Me));

    [Fact]
    public void Own_level_is_visible() =>
        Assert.True(ShiftSalaryLevelsController.AppliesTo(Level($"[\"{Guid.NewGuid()}\",\"{Me}\"]"), Me));

    [Fact]
    public void Other_staff_level_is_hidden() =>
        // Nhân viên không được thấy mức lương ca áp riêng cho người khác.
        Assert.False(ShiftSalaryLevelsController.AppliesTo(Level($"[\"{Guid.NewGuid()}\"]"), Me));

    [Fact]
    public void Account_without_employee_sees_only_shared_levels() =>
        Assert.False(ShiftSalaryLevelsController.AppliesTo(Level($"[\"{Me}\"]"), null));
}
