using Xunit;
using ZKTecoADMS.Api.Controllers;

namespace ZKTecoADMS.Tests;

public class StaffReadableSettingsTests
{
    [Theory]
    [InlineData("day_end_time")]
    [InlineData("min_hours_for_work_day")]
    [InlineData("DECIMAL_WORK_DAY_ENABLED")]
    [InlineData("mobile_bottom_nav_main_v3")]
    public void Work_rules_are_readable_by_staff(string key) =>
        Assert.Contains(key, SettingsController.StaffReadableAppSettingKeys);

    [Fact]
    public void Money_settings_stay_private()
    {
        foreach (var key in SettingsController.StaffReadableAppSettingKeys)
        {
            Assert.DoesNotContain("salary", key, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("penalty", key, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("tax", key, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("insurance", key, StringComparison.OrdinalIgnoreCase);
        }
    }
}
