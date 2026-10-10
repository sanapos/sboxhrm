using Xunit;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Phương thức thanh toán trên chứng từ → phương thức phiếu quỹ (quyết định tiền vào quỹ nào).</summary>
public class PosPaymentMethodParseTests
{
    [Theory]
    [InlineData(null, PaymentMethodType.Cash)]
    [InlineData("Tiền mặt", PaymentMethodType.Cash)]
    [InlineData("Cash", PaymentMethodType.Cash)]
    [InlineData("COD", PaymentMethodType.Cash)]
    [InlineData("Chuyển khoản", PaymentMethodType.BankTransfer)]
    [InlineData("Tingee", PaymentMethodType.BankTransfer)]
    [InlineData("Ngân hàng TMCP Ngoại thương Việt Nam 9935364556", PaymentMethodType.BankTransfer)]
    [InlineData("CK", PaymentMethodType.BankTransfer)]
    [InlineData("Bank", PaymentMethodType.BankTransfer)]
    [InlineData("VietQR", PaymentMethodType.VietQR)]
    [InlineData("Thẻ", PaymentMethodType.Card)]
    [InlineData("MoMo", PaymentMethodType.EWallet)]
    [InlineData("Ví điện tử", PaymentMethodType.EWallet)]
    public void Nhan_dien_phuong_thuc(string? method, PaymentMethodType expected) =>
        Assert.Equal(expected, PosFinanceSyncHelper.ParsePaymentMethod(method));

    [Fact]
    public void Tien_da_vao_tai_khoan_ngan_hang_thi_khong_phai_tien_mat()
    {
        var bank = Guid.NewGuid();
        Assert.Equal(PaymentMethodType.BankTransfer, PosFinanceSyncHelper.ParsePaymentMethod("Tiền mặt", bank));
        Assert.Equal(PaymentMethodType.VietQR, PosFinanceSyncHelper.ParsePaymentMethod("VietQR", bank));
        Assert.Equal(PaymentMethodType.Cash, PosFinanceSyncHelper.ParsePaymentMethod("Tiền mặt", null));
    }
}
