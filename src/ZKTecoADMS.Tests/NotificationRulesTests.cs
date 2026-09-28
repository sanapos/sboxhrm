using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Application.Services;

namespace ZKTecoADMS.Tests;

/// <summary>Giờ yên lặng thông báo đẩy + thay biến trong mẫu thông báo.</summary>
public class NotificationRulesTests
{
    [Theory]
    [InlineData(23 * 60, 22 * 60, 7 * 60, true)]    // 23:00 trong 22:00-07:00
    [InlineData(3 * 60, 22 * 60, 7 * 60, true)]     // 03:00 qua đêm
    [InlineData(7 * 60, 22 * 60, 7 * 60, false)]    // 07:00 hết yên lặng
    [InlineData(12 * 60, 22 * 60, 7 * 60, false)]
    [InlineData(12 * 60 + 30, 12 * 60, 13 * 60 + 30, true)] // trưa trong ngày
    [InlineData(14 * 60, 12 * 60, 13 * 60 + 30, false)]
    [InlineData(10 * 60, 8 * 60, 8 * 60, false)]    // khoảng rỗng
    public void Gio_yen_lang(int minute, int start, int end, bool expected) =>
        Assert.Equal(expected, NotificationQuietRules.IsInQuiet(minute, start, end));

    [Fact]
    public void Gio_VN_tu_UTC() =>
        Assert.Equal(1 * 60 + 15, NotificationQuietRules.VnMinuteOfDay(new DateTime(2026, 9, 28, 18, 15, 0, DateTimeKind.Utc)));

    [Theory]
    [InlineData("22:00", 1320)]
    [InlineData("7:05", 425)]
    [InlineData("24:00", null)]
    [InlineData("abc", null)]
    public void Doc_gio(string hm, int? expected) => Assert.Equal(expected, NotificationQuietRules.Parse(hm));

    [Theory]
    [InlineData("Error", null, true)]
    [InlineData("ApprovalRequired", null, true)]
    [InlineData("Info", "approval", true)]
    [InlineData("Info", "attendance", false)]
    public void Thong_bao_khan(string type, string? cat, bool expected) =>
        Assert.Equal(expected, NotificationQuietRules.IsUrgent(type, cat));

    [Fact]
    public void Thay_bien_mau()
    {
        var now = new DateTime(2026, 9, 28, 8, 5, 0);
        var s = NotificationCenterController.Render("Chào {ten} ({hoten}) - {cuahang} {ngay} {thang} {gio} {khac}",
            "Nguyễn Văn An", "SBOX", now);
        Assert.Equal("Chào An (Nguyễn Văn An) - SBOX 28/09/2026 09/2026 08:05 {khac}", s);
        Assert.Equal("Chào bạn", NotificationCenterController.Render("Chào {TEN}", "", "SBOX", now));
    }
}
