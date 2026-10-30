using Xunit;
using ZKTecoADMS.Api.Services;

namespace ZKTecoADMS.Tests.Notifications;

public class VnMoneyTextTests
{
    [Theory]
    [InlineData("Ứng lương 300,000đ", "Ứng lương 300.000đ")]
    [InlineData("Lương tháng - 6,000,000đ", "Lương tháng - 6.000.000đ")]
    [InlineData("Đã chi 150,000 ₫ (Tiền mặt)", "Đã chi 150.000 ₫ (Tiền mặt)")]
    [InlineData("Thiếu 1,234,567 VND", "Thiếu 1.234.567 VND")]
    [InlineData("Đã duyệt 500đ", "Đã duyệt 500đ")]
    [InlineData("Mã 1,234 cần xử lý", "Mã 1,234 cần xử lý")]
    [InlineData("Tỷ lệ 12,5%", "Tỷ lệ 12,5%")]
    [InlineData("", "")]
    public void Normalizes_only_money_amounts(string input, string expected) =>
        Assert.Equal(expected, VnMoneyText.Normalize(input));
}
