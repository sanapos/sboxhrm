using Xunit;
using ZKTecoADMS.Api.Controllers.Filters;

namespace ZKTecoADMS.Tests;

public class ActivityLabelsTests
{
    [Theory]
    [InlineData("ScheduleRegistration", "Đăng ký lịch làm việc")]
    [InlineData("IdentityUserRole`1", "Vai trò tài khoản")]
    [InlineData("Cài đặt", "Cài đặt")]
    public void Entity_is_vietnamese(string type, string expected) => Assert.Equal(expected, ActivityLabels.Entity(type));

    [Theory]
    [InlineData("MaxLateMinutes", "Phút trễ tối đa")]
    [InlineData("EmployeeId", "Nhân viên")]
    [InlineData("ScheduleRegistrationId", "Đăng ký lịch làm việc")]
    public void Field_is_translated(string field, string expected) => Assert.Equal(expected, ActivityLabels.Field(field));

    [Fact]
    public void Values_are_localized()
    {
        Assert.Equal("Chờ duyệt", ActivityLabels.Value("Pending"));
        Assert.Equal("29/09/2026", ActivityLabels.Value("2026-09-29 00:00"));
        Assert.Equal("08:30 29/09/2026", ActivityLabels.Value("2026-09-29 08:30"));
        Assert.StartsWith("#", ActivityLabels.Value(Guid.NewGuid().ToString()));
        Assert.Equal("Quản lý", ActivityLabels.Role("Manager"));
    }
}
