using Xunit;
using ZKTecoADMS.Api.Services.PaymentGateway;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Webhook Tingee: giao dịch ghi nợ (tiền ra) không được coi là khoản thu.</summary>
public class TingeeWebhookParseTests
{
    static string Body(string? type) =>
        "{\"clientId\":\"c1\",\"transactionCode\":\"FT123\",\"amount\":5000000," +
        "\"content\":\"HD0001 thanh toan\",\"accountNumber\":\"0123456789\"," +
        "\"transactionDate\":\"20261028101500\"" +
        (type == null ? "" : $",\"type\":\"{type}\"") + "}";

    [Theory]
    [InlineData(null, false)]
    [InlineData("credit", false)]
    [InlineData("debit", true)]
    [InlineData("DEBIT", true)]
    public void Nhan_dien_chieu_giao_dich(string? type, bool expectedDebit)
    {
        var p = new TingeePaymentWebhookProvider().Parse(Body(type));
        Assert.Equal(expectedDebit, p.IsDebit);
        Assert.Equal("FT123", p.TransactionCode);
    }
}
