using System.Net;
using System.Text;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Api.Services.EInvoice;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Tests;

/// <summary>HĐĐT MISA meInvoice + VNPT Invoice: phân tích phản hồi, ký hiệu, URL.</summary>
public class EInvoiceProviderTests
{
    [Theory]
    [InlineData("OK:1/001;C25TAA-abc_123", "123", "1/001", "C25TAA")]
    [InlineData("OK:1/001;C25TAA-5f1e2d3c-aaaa-bbbb-cccc-1234567890ab_45", "45", "1/001", "C25TAA")]
    [InlineData("OK:", null, "1/001", "C25TAA")]
    public void Vnpt_publish_ok_parses_number(string raw, string? no, string pattern, string serial)
    {
        var r = VnptInvoiceClient.ParsePublishText(raw, "1/001", "C25TAA");
        Assert.True(r.Ok);
        Assert.Equal(no, r.InvoiceNo);
        Assert.Equal(pattern, r.Pattern);
        Assert.Equal(serial, r.Serial);
    }

    [Theory]
    [InlineData("ERR:1", "Sai tài khoản")]
    [InlineData("ERR:20", "Mẫu số")]
    [InlineData("ERR:13", "Fkey đã tồn tại")]
    public void Vnpt_errors_are_explained(string raw, string contains)
    {
        var r = VnptInvoiceClient.ParsePublishText(raw, "1/001", "C25TAA");
        Assert.False(r.Ok);
        Assert.Equal(raw, r.ErrorCode);
        Assert.Contains(contains, r.Error);
    }

    [Theory]
    [InlineData("https://0101234567-tt78admin.vnpt-invoice.com.vn/PublishService.asmx?op=ImportAndPublishInv",
        "https://0101234567-tt78admin.vnpt-invoice.com.vn", "https://0101234567-tt78.vnpt-invoice.com.vn/Portal/Index/")]
    [InlineData("0101234567-tt78admindemo.vnpt-invoice.com.vn/",
        "https://0101234567-tt78admindemo.vnpt-invoice.com.vn", "https://0101234567-tt78demo.vnpt-invoice.com.vn/Portal/Index/")]
    public void Vnpt_urls_normalize(string raw, string root, string lookup)
    {
        Assert.Equal(root, VnptInvoiceClient.NormalizeBaseUrl(raw));
        Assert.Equal(lookup, VnptInvoiceClient.PortalLookupUrl(raw));
    }

    [Theory]
    [InlineData("", "https://api.meinvoice.vn/api/integration")]
    [InlineData("https://testapi.meinvoice.vn/api/integration/invoice", "https://testapi.meinvoice.vn/api/integration")]
    [InlineData("https://api-vinvoice.viettel.vn", "https://api.meinvoice.vn/api/integration")]
    public void Misa_base_url_normalizes(string raw, string expected) =>
        Assert.Equal(expected, MisaMeInvoiceClient.NormalizeBaseUrl(raw));

    [Theory]
    [InlineData("1", "C25TAA", "1C25TAA")]
    [InlineData("", "1c25taa", "1C25TAA")]
    [InlineData("1/001", "1C25MAA", "1C25MAA")]
    public void Misa_series_combines_template_and_symbol(string template, string series, string expected)
    {
        var s = new PosEInvoiceSetting { TemplateCode = template, InvoiceSeries = series };
        Assert.Equal(expected, PosEInvoiceService.ResolveMisaSeries(s));
    }

    [Fact]
    public async Task Misa_publish_reads_stringified_result_array()
    {
        const string body = """
            {"success":true,"errorCode":null,"descriptionErrorCode":null,"createInvoiceResult":null,
             "publishInvoiceResult":"[{\"RefID\":\"r1\",\"TransactionID\":\"11CRTPWJG5\",\"InvSeries\":\"1C25TAA\",\"InvNo\":\"00000033\",\"InvCode\":null,\"InvDate\":\"2025-09-25T00:00:00+07:00\",\"ErrorCode\":\"\"}]"}
            """;
        var client = NewMisa(body);
        var r = await client.PublishAsync("", "tok", "0101243150", 2, new { RefID = "r1" });
        Assert.True(r.Ok);
        Assert.Equal("11CRTPWJG5", r.TransactionId);
        Assert.Equal("00000033", r.InvoiceNo);
        Assert.Equal("1C25TAA", r.InvoiceSeries);
    }

    [Fact]
    public async Task Misa_publish_item_error_is_failure()
    {
        const string body = """
            {"success":true,"errorCode":null,
             "publishInvoiceResult":"[{\"RefID\":\"r1\",\"TransactionID\":null,\"InvNo\":null,\"ErrorCode\":\"InvoiceDuplicated\"}]"}
            """;
        var r = await NewMisa(body).PublishAsync("", "tok", "0101243150", 2, new { RefID = "r1" });
        Assert.False(r.Ok);
        Assert.Equal("InvoiceDuplicated", r.ErrorCode);
        Assert.Contains("trùng", r.Error);
    }

    [Fact]
    public async Task Misa_status_marks_deleted()
    {
        const string body = """
            {"success":true,"data":"[{\"TransactionID\":\"M9CKT_180J\",\"PublishStatus\":1,\"ReferenceType\":0,\"InvoiceCode\":\"ABC\",\"SendTaxStatus\":2,\"IsSentEmail\":true,\"IsDelete\":true,\"DeletedReason\":\"Sai\"}]"}
            """;
        var list = await NewMisa(body).GetStatusAsync("", "tok", "0101243150", ["r1"], true, true, false);
        var st = Assert.Single(list);
        Assert.True(st.IsDeleted);
        Assert.True(st.IsSentEmail);
        Assert.Equal("ABC", st.InvoiceCode);
    }

    static MisaMeInvoiceClient NewMisa(string responseBody) =>
        new(new StubFactory(responseBody),
            new MemoryCache(new MemoryCacheOptions()),
            NullLogger<MisaMeInvoiceClient>.Instance);

    sealed class StubFactory(string body) : IHttpClientFactory
    {
        public HttpClient CreateClient(string name) => new(new StubHandler(body));
    }

    sealed class StubHandler(string body) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct) =>
            Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(body, Encoding.UTF8, "application/json"),
            });
    }
}
