using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Xml.Linq;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Api.Services.EInvoice;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>
/// Hợp đồng API HĐĐT với từng hãng — giả lập phản hồi theo tài liệu (không gọi máy chủ thật).
/// MISA: đối chiếu doc.meinvoice.vn/itg (tài liệu chính thức của hãng).
/// VNPT / Viettel / Easy: chưa có tài liệu chính thức công khai — kiểm theo nguồn thứ cấp / giả định, ghi rõ ở từng test.
/// Dữ liệu mẫu: 2 dòng hàng, chiết khấu dòng + chiết khấu đơn, người mua doanh nghiệp có MST.
/// </summary>
public class EInvoiceVendorContractTests
{
    static readonly Guid StoreId = Guid.Parse("7d1c2a4e-0000-4000-8000-000000000001");
    const string BuyerMst = "0312345678";
    const string BuyerCompany = "Công ty TNHH Thương mại Sao Việt";
    const string BuyerPerson = "Trần Thị Mai";
    const string BuyerAddress = "12 Nguyễn Huệ, Phường Bến Nghé, Quận 1, TP. Hồ Chí Minh";
    static readonly DateTime SaleUtc = new(2026, 10, 20, 3, 0, 0, DateTimeKind.Utc); // 10:00 20/10/2026 giờ VN

    static readonly EInvoiceBuyerInput Buyer =
        new(BuyerPerson, BuyerMst, BuyerCompany, BuyerAddress, null, "0909123456");

    // ───────────────────────────── MISA (tài liệu chính thức) ─────────────────────────────

    [Fact]
    public async Task Misa_login_sends_documented_body_and_reads_Data_token()
    {
        var http = new FakeVendor().OnPath("/auth/token", MisaTokenOk);
        var client = new MisaMeInvoiceClient(http, new MemoryCache(new MemoryCacheOptions()),
            NullLogger<MisaMeInvoiceClient>.Instance);

        var r = await client.LoginAsync("https://testapi.meinvoice.vn/api/integration", "APPID-TEST", "0101243150",
            "test@sbox.vn", "test-pass");

        Assert.True(r.Ok);
        Assert.Equal("eyJhbGciOiJIUzI1NiJ9.test.sig", r.Token);
        var req = Assert.Single(http.Requests);
        Assert.Equal(HttpMethod.Post, req.Method);
        Assert.Equal("https://testapi.meinvoice.vn/api/integration/auth/token", req.Uri.ToString());
        var body = Json(req.Body);
        Assert.Equal("APPID-TEST", body.GetProperty("appid").GetString());
        Assert.Equal("0101243150", body.GetProperty("taxcode").GetString());
        Assert.Equal("test@sbox.vn", body.GetProperty("username").GetString());
        Assert.Equal("test-pass", body.GetProperty("password").GetString());
    }

    [Theory]
    [InlineData("InvalidAppID", "AppID")]
    [InlineData("InactiveAppID", "ngừng")]
    [InlineData("UnAuthorize", "Sai tài khoản")]
    public async Task Misa_login_documented_error_codes_are_explained(string code, string contains)
    {
        var body = $$"""{"Success":false,"ErrorCode":"{{code}}","Errors":[],"Data":null,"CustomData":null}""";
        var http = new FakeVendor().OnPath("/auth/token", body);
        var client = new MisaMeInvoiceClient(http, new MemoryCache(new MemoryCacheOptions()),
            NullLogger<MisaMeInvoiceClient>.Instance);

        var r = await client.LoginAsync("", "a", "b", "c", "d");

        Assert.False(r.Ok);
        Assert.Contains(contains, r.Error);
    }

    [Fact]
    public async Task Misa_publish_8pct_payload_matches_InvoiceData_contract()
    {
        var (svc, db, http) = NewService();
        http.OnPath("/auth/token", MisaTokenOk)
            .OnPath("/api/integration/invoice", MisaPublishOk("11CRTPWJG5", "00000033"));
        var settings = MisaSettings();
        var order = Order8Pct();
        await Seed(db, settings, order);

        await svc.IssueNowAsync(order, Buyer);

        Assert.Equal("Issued", order.EInvoiceStatus);
        Assert.Equal("00000033", order.EInvoiceNo);
        Assert.Equal("11CRTPWJG5", order.EInvoiceReservationCode);
        Assert.Equal("1C26TAA", order.EInvoiceSeries); // ví dụ MISA trả InvSeries=null → giữ ký hiệu cấu hình

        var req = http.Requests.Single(r => r.Uri.AbsolutePath.EndsWith("/integration/invoice"));
        Assert.Equal(HttpMethod.Post, req.Method);
        Assert.Equal("Bearer eyJhbGciOiJIUzI1NiJ9.test.sig", req.Headers["Authorization"]);
        Assert.StartsWith("application/json", req.ContentType);

        var root = Json(req.Body);
        Assert.Equal(2, root.GetProperty("SignType").GetInt32());
        var inv = Assert.Single(root.GetProperty("InvoiceData").EnumerateArray().ToList());

        // Thông tin chung bắt buộc
        Assert.Equal(order.EInvoiceTransactionUuid, inv.GetProperty("RefID").GetString());
        Assert.Equal("1C26TAA", inv.GetProperty("InvSeries").GetString());
        Assert.Equal("2026-10-20", inv.GetProperty("InvDate").GetString());
        Assert.Equal("VND", inv.GetProperty("CurrencyCode").GetString());
        Assert.Equal(1m, inv.GetProperty("ExchangeRate").GetDecimal());
        Assert.Equal("TM", inv.GetProperty("PaymentMethodName").GetString());
        Assert.False(inv.GetProperty("IsInvoiceCalculatingMachine").GetBoolean());

        // Người mua có MST → BuyerLegalName + BuyerAddress bắt buộc
        Assert.Equal(BuyerMst, inv.GetProperty("BuyerTaxCode").GetString());
        Assert.Equal(BuyerCompany, inv.GetProperty("BuyerLegalName").GetString());
        Assert.Equal(BuyerAddress, inv.GetProperty("BuyerAddress").GetString());
        Assert.Equal(BuyerPerson, inv.GetProperty("BuyerFullName").GetString());

        // Tổng tiền: chiết khấu đơn 5.000 đã phân bổ vào dòng → TotalDiscount = 0, DiscountRate (bắt buộc) = 0
        Assert.Equal(0m, inv.GetProperty("DiscountRate").GetDecimal());
        Assert.Equal(0m, inv.GetProperty("TotalDiscountAmountOC").GetDecimal());
        Assert.Equal(150000m, inv.GetProperty("TotalSaleAmountOC").GetDecimal());
        Assert.Equal(150000m, inv.GetProperty("TotalSaleAmount").GetDecimal());
        Assert.Equal(150000m, inv.GetProperty("TotalAmountWithoutVATOC").GetDecimal());
        Assert.Equal(150000m, inv.GetProperty("TotalAmountWithoutVAT").GetDecimal());
        Assert.Equal(12000m, inv.GetProperty("TotalVATAmountOC").GetDecimal());
        Assert.Equal(12000m, inv.GetProperty("TotalVATAmount").GetDecimal());
        Assert.Equal(162000m, inv.GetProperty("TotalAmountOC").GetDecimal());
        Assert.Equal(162000m, inv.GetProperty("TotalAmount").GetDecimal());
        Assert.Equal("Một trăm sáu mươi hai nghìn đồng.", inv.GetProperty("TotalAmountInWords").GetString());

        // Dòng hàng (InvoiceDetail)
        var lines = inv.GetProperty("OriginalInvoiceDetail").EnumerateArray().ToList();
        Assert.Equal(2, lines.Count);
        foreach (var l in lines)
        {
            Assert.Equal(1, l.GetProperty("ItemType").GetInt32());
            Assert.Equal("8%", l.GetProperty("VATRateName").GetString());
            Assert.Equal(l.GetProperty("AmountOC").GetDecimal(), l.GetProperty("AmountWithoutVATOC").GetDecimal());
            Assert.Equal(l.GetProperty("VATAmountOC").GetDecimal(), l.GetProperty("VATAmount").GetDecimal());
            // Đơn giá × SL = thành tiền (đơn giá sau chiết khấu)
            Assert.Equal(l.GetProperty("AmountOC").GetDecimal(),
                Math.Round(l.GetProperty("UnitPrice").GetDecimal() * l.GetProperty("Quantity").GetDecimal(), 0));
        }
        Assert.Equal("Cà phê sữa đá", lines[0].GetProperty("ItemName").GetString());
        Assert.Equal("Ly", lines[0].GetProperty("UnitName").GetString());
        Assert.Equal(96774m, lines[0].GetProperty("AmountOC").GetDecimal());
        Assert.Equal(7742m, lines[0].GetProperty("VATAmountOC").GetDecimal());
        Assert.Equal(53226m, lines[1].GetProperty("AmountOC").GetDecimal());
        Assert.Equal(4258m, lines[1].GetProperty("VATAmountOC").GetDecimal());
        Assert.Equal(inv.GetProperty("TotalAmountWithoutVATOC").GetDecimal(),
            lines.Sum(l => l.GetProperty("AmountWithoutVATOC").GetDecimal()));
        Assert.Equal(inv.GetProperty("TotalVATAmountOC").GetDecimal(),
            lines.Sum(l => l.GetProperty("VATAmountOC").GetDecimal()));

        // Mỗi thuế suất 1 TaxRateInfo
        var tax = Assert.Single(inv.GetProperty("TaxRateInfo").EnumerateArray().ToList());
        Assert.Equal("8%", tax.GetProperty("VATRateName").GetString());
        Assert.Equal(150000m, tax.GetProperty("AmountWithoutVATOC").GetDecimal());
        Assert.Equal(12000m, tax.GetProperty("VATAmountOC").GetDecimal());
        Assert.Equal("VND", inv.GetProperty("OptionUserDefined").GetProperty("MainCurrency").GetString());
    }

    [Fact]
    public async Task Misa_publish_10pct_price_included_splits_vat()
    {
        var (svc, db, http) = NewService();
        http.OnPath("/auth/token", MisaTokenOk)
            .OnPath("/api/integration/invoice", MisaPublishOk("TX10", "00000040"));
        var settings = MisaSettings();
        settings.TaxMode = "included";
        settings.DefaultTaxPercent = 10;
        var order = Order10PctIncluded();
        await Seed(db, settings, order);

        await svc.IssueNowAsync(order, Buyer);

        Assert.Equal("Issued", order.EInvoiceStatus);
        var inv = Json(http.Requests.Single(r => r.Uri.AbsolutePath.EndsWith("/integration/invoice")).Body)
            .GetProperty("InvoiceData")[0];
        Assert.Equal(100000m, inv.GetProperty("TotalAmountWithoutVATOC").GetDecimal());
        Assert.Equal(10000m, inv.GetProperty("TotalVATAmountOC").GetDecimal());
        Assert.Equal(110000m, inv.GetProperty("TotalAmountOC").GetDecimal());
        Assert.Equal("10%", inv.GetProperty("OriginalInvoiceDetail")[0].GetProperty("VATRateName").GetString());
        Assert.Equal("10%", inv.GetProperty("TaxRateInfo")[0].GetProperty("VATRateName").GetString());
    }

    [Fact]
    public async Task Misa_publish_top_level_error_marks_failed()
    {
        var (svc, db, http) = NewService();
        http.OnPath("/auth/token", MisaTokenOk)
            .OnPath("/api/integration/invoice",
                """{"success":false,"errorCode":"InvalidTaxCode","descriptionErrorCode":"MST không hợp lệ","createInvoiceResult":null,"publishInvoiceResult":null}""");
        var settings = MisaSettings();
        var order = Order8Pct();
        await Seed(db, settings, order);

        await svc.IssueNowAsync(order, Buyer);

        Assert.Equal("Failed", order.EInvoiceStatus);
        Assert.Contains("MST người bán", order.EInvoiceError);
    }

    [Fact]
    public async Task Misa_replace_sends_documented_reference_fields()
    {
        var (svc, db, http) = NewService();
        http.OnPath("/auth/token", MisaTokenOk)
            .OnPath("/api/integration/invoice", MisaPublishOk("TXNEW", "00000034"));
        var settings = MisaSettings();
        var order = Order8Pct();
        order.EInvoiceStatus = "Issued";
        order.EInvoiceProvider = "Misa";
        order.EInvoiceNo = "00000033";
        order.EInvoiceSeries = "1C26TAA";
        order.EInvoiceReservationCode = "11CRTPWJG5";
        order.EInvoiceTransactionUuid = Guid.NewGuid().ToString();
        order.EInvoiceIssuedAt = SaleUtc;
        await Seed(db, settings, order);

        await svc.ReplaceAsync(order, "Sai tên đơn vị mua hàng", Buyer);

        var inv = Json(http.Requests.Single(r => r.Uri.AbsolutePath.EndsWith("/integration/invoice")).Body)
            .GetProperty("InvoiceData")[0];
        Assert.Equal(1, inv.GetProperty("ReferenceType").GetInt32());   // 1 = thay thế
        Assert.Equal(1, inv.GetProperty("OrgInvoiceType").GetInt32());  // 1 = HĐ NĐ123
        Assert.Equal("1", inv.GetProperty("OrgInvTemplateNo").GetString());
        Assert.Equal("C26TAA", inv.GetProperty("OrgInvSeries").GetString());
        Assert.Equal("00000033", inv.GetProperty("OrgInvNo").GetString());
        Assert.Equal("2026-10-20", inv.GetProperty("OrgInvDate").GetString());
        Assert.Equal("Sai tên đơn vị mua hàng", inv.GetProperty("InvoiceNote").GetString());

        Assert.Equal("Replacement", order.EInvoiceKind);
        Assert.Equal("00000033", order.EInvoiceOriginalNo);
        Assert.Equal("00000034", order.EInvoiceNo);
    }

    [Fact]
    public async Task Misa_cancel_sends_documented_body()
    {
        var (svc, db, http) = NewService();
        http.OnPath("/auth/token", MisaTokenOk)
            .OnPath("/invoice/cancel",
                """{"success":true,"errorCode":null,"descriptionErrorCode":null,"errors":[],"data":""}""");
        var settings = MisaSettings();
        var order = Order8Pct();
        order.EInvoiceStatus = "Issued";
        order.EInvoiceNo = "00000033";
        order.EInvoiceSeries = "1C26TAA";
        order.EInvoiceReservationCode = "DBCAULR0K21";
        order.EInvoiceTransactionUuid = Guid.NewGuid().ToString();
        await Seed(db, settings, order);

        await svc.CancelAsync(order, "HĐ bị sai nên hủy", null);

        Assert.Equal("Cancelled", order.EInvoiceStatus);
        var req = http.Requests.Single(r => r.Uri.AbsolutePath.EndsWith("/invoice/cancel"));
        Assert.Equal("https://testapi.meinvoice.vn/api/integration/invoice/cancel", req.Uri.ToString());
        var body = Json(req.Body);
        Assert.Equal("DBCAULR0K21", body.GetProperty("TransactionID").GetString());
        Assert.Equal("1C26TAA", body.GetProperty("InvSeries").GetString());
        Assert.Equal("HĐ bị sai nên hủy", body.GetProperty("CancelReason").GetString());
    }

    [Fact]
    public async Task Misa_status_uses_documented_query_and_list_body()
    {
        var http = new FakeVendor().OnPath("/invoice/status",
            """{"success":true,"errorCode":null,"descriptionErrorCode":null,"errors":[],"data":"[{\"TransactionID\":\"M9CKT_180J\",\"PublishStatus\":1,\"ReferenceType\":0,\"InvoiceCode\":\"21B02D9C84A1BC4019A8BFC1AB2F686709\",\"SendTaxStatus\":2,\"IsSentEmail\":false,\"IsDelete\":false,\"DeletedDate\":null,\"DeletedReason\":null,\"ReceivedStatus\":0}]","customData":""}""");
        var client = NewMisaClient(http);

        var list = await client.GetStatusAsync(MisaTestUrl, "tok", "0101243150", ["M9CKT_180J"],
            byRefId: false, invoiceWithCode: true, cashRegister: false);

        var st = Assert.Single(list);
        Assert.Equal("M9CKT_180J", st.TransactionId);
        Assert.Equal(2, st.SendTaxStatus);
        Assert.False(st.IsDeleted);
        Assert.Equal("21B02D9C84A1BC4019A8BFC1AB2F686709", st.InvoiceCode);
        var req = Assert.Single(http.Requests);
        Assert.Equal("?invoiceWithCode=true&invoiceCalcu=false&inputType=1", req.Uri.Query);
        Assert.Equal("[\"M9CKT_180J\"]", req.Body);
    }

    [Fact]
    public async Task Misa_sendemail_documented_example_response_is_success()
    {
        // Ví dụ trong tài liệu SendEmail: success=false nhưng dòng SendEmailStatus=3 (Đã gửi), ErrorCode rỗng.
        var http = new FakeVendor().OnPath("/invoice/sendemail",
            """{"success":false,"errorCode":null,"descriptionErrorCode":null,"errors":[],"data":"[{\"TransactionID\":\"_8CKUJ52_Z\",\"RefID\":\"21E34AFA-38F3-4506-A222-7C3AFC55B8E2\",\"RefDetailID\":\"00000000-0000-0000-0000-000000000000\",\"SendEmailStatus\":3,\"ErrorCode\":\"\"}]","customData":""}""");
        var client = NewMisaClient(http);

        var r = await client.SendEmailAsync(MisaTestUrl, "tok", "0101243150", "_8CKUJ52_Z",
            BuyerPerson, "ketoan@saoviet.vn", invoiceWithCode: true, cashRegister: false);

        Assert.True(r.Ok, r.Error);
        var body = Json(Assert.Single(http.Requests).Body);
        var item = body.GetProperty("SendEmailDatas")[0];
        Assert.Equal("_8CKUJ52_Z", item.GetProperty("TransactionID").GetString());
        Assert.Equal(BuyerPerson, item.GetProperty("ReceiverName").GetString());
        Assert.Equal("ketoan@saoviet.vn", item.GetProperty("ReceiverEmail").GetString());
        Assert.True(body.GetProperty("IsInvoiceCode").GetBoolean());
        Assert.False(body.GetProperty("IsInvoiceCalculatingMachine").GetBoolean());
    }

    [Fact]
    public async Task Misa_sendemail_status_2_is_failure()
    {
        var http = new FakeVendor().OnPath("/invoice/sendemail",
            """{"success":true,"errorCode":null,"errors":[],"data":"[{\"TransactionID\":\"X\",\"SendEmailStatus\":2,\"ErrorCode\":\"\"}]"}""");
        var r = await NewMisaClient(http).SendEmailAsync(MisaTestUrl, "tok", "0101243150", "X", "A", "a@b.vn", true, false);
        Assert.False(r.Ok);
    }

    [Fact]
    public async Task Misa_download_documented_link_response()
    {
        const string link = "https://www.test.meinvoice.vn/tra-cuu/downloadhandler.ashx?type=pdf&code=c014c26b&Viewer=1&SearchType=2";
        var http = new FakeVendor().OnPath("/invoice/Download",
            $$"""{"success":true,"errorCode":null,"descriptionErrorCode":null,"errors":[],"data":"{{link}}","customData":""}""");

        var r = await NewMisaClient(http).DownloadPdfAsync(MisaTestUrl, "tok", "0101243150", "L4CXU6X0W0", true, false);

        Assert.True(r.Ok);
        Assert.Equal(link, r.Url);
        var req = Assert.Single(http.Requests);
        Assert.Equal("?invoiceWithCode=true&invoiceCalcu=false&downloadDataType=Pdf", req.Uri.Query);
        Assert.Equal("[\"L4CXU6X0W0\"]", req.Body);
    }

    // ───────────────────────────── VNPT (nguồn thứ cấp) ─────────────────────────────

    [Fact]
    public async Task Vnpt_publish_soap_envelope_and_tt78_xml()
    {
        var (svc, db, http) = NewService();
        var settings = VnptSettings();
        var order = Order8Pct();
        order.EInvoiceTransactionUuid = "5f1e2d3c-aaaa-bbbb-cccc-1234567890ab";
        http.OnSoap("ImportAndPublishInv", Soap("ImportAndPublishInv", $"OK:1/001;C26TAA-{order.EInvoiceTransactionUuid}_123"));
        await Seed(db, settings, order);

        await svc.IssueNowAsync(order, Buyer);

        Assert.Equal("Issued", order.EInvoiceStatus);
        Assert.Equal("123", order.EInvoiceNo);
        Assert.Equal("C26TAA", order.EInvoiceSeries);

        var req = Assert.Single(http.Requests);
        Assert.Equal("https://0312345678-tt78admindemo.vnpt-invoice.com.vn/PublishService.asmx", req.Uri.ToString());
        Assert.Equal("\"http://tempuri.org/ImportAndPublishInv\"", req.Headers["SOAPAction"]);
        Assert.StartsWith("text/xml", req.ContentType);

        var op = SoapOp(req.Body, "ImportAndPublishInv");
        // Thứ tự tham số theo chữ ký web service (asmx nhạy thứ tự).
        Assert.Equal(new[] { "Account", "ACpass", "xmlInvData", "username", "pass", "pattern", "serial", "convert" },
            op.Elements().Select(e => e.Name.LocalName).ToArray());
        Assert.Equal("admin-test", op.Elements().First(e => e.Name.LocalName == "Account").Value);
        Assert.Equal("service-test", op.Elements().First(e => e.Name.LocalName == "username").Value);
        Assert.Equal("1/001", op.Elements().First(e => e.Name.LocalName == "pattern").Value);
        Assert.Equal("C26TAA", op.Elements().First(e => e.Name.LocalName == "serial").Value);
        Assert.Equal("0", op.Elements().First(e => e.Name.LocalName == "convert").Value);

        var inv = XElement.Parse(op.Elements().First(e => e.Name.LocalName == "xmlInvData").Value);
        Assert.Equal("DSHDon", inv.Name.LocalName);
        var hd = inv.Element("HDon")!;
        Assert.Equal(order.EInvoiceTransactionUuid, hd.Element("key")!.Value);
        var tt = hd.Element("DLHDon")!.Element("TTChung")!;
        Assert.Equal("2026-10-20", tt.Element("NLap")!.Value);
        Assert.Equal("VND", tt.Element("DVTTe")!.Value);
        var nd = hd.Element("DLHDon")!.Element("NDHDon")!;
        var nm = nd.Element("NMua")!;
        Assert.Equal(BuyerCompany, nm.Element("Ten")!.Value);
        Assert.Equal(BuyerMst, nm.Element("MST")!.Value);
        Assert.Equal(BuyerAddress, nm.Element("DChi")!.Value);
        Assert.Equal(BuyerPerson, nm.Element("HVTNMHang")!.Value);
        var items = nd.Element("DSHHDVu")!.Elements("HHDVu").ToList();
        Assert.Equal(2, items.Count);
        Assert.All(items, i => Assert.Equal("8%", i.Element("TSuat")!.Value));
        Assert.All(items, i => Assert.Equal("1", i.Element("TChat")!.Value));
        Assert.Equal("96774", items[0].Element("ThTien")!.Value);
        Assert.Equal("7742", items[0].Element("TThue")!.Value);
        Assert.Equal("32258", items[0].Element("DGia")!.Value);
        Assert.Equal("3", items[0].Element("SLuong")!.Value);
        var tot = nd.Element("TToan")!;
        var lt = tot.Element("THTTLTSuat")!.Element("LTSuat")!;
        Assert.Equal("8%", lt.Element("TSuat")!.Value);
        Assert.Equal("150000", lt.Element("ThTien")!.Value);
        Assert.Equal("12000", lt.Element("TThue")!.Value);
        Assert.Equal("150000", tot.Element("TgTCThue")!.Value);
        Assert.Equal("12000", tot.Element("TgTThue")!.Value);
        Assert.Equal("162000", tot.Element("TgTTTBSo")!.Value);
        Assert.Equal("Một trăm sáu mươi hai nghìn đồng", tot.Element("TgTTTBChu")!.Value);
    }

    [Fact]
    public async Task Vnpt_publish_err20_marks_failed_with_explanation()
    {
        var (svc, db, http) = NewService();
        http.OnSoap("ImportAndPublishInv", Soap("ImportAndPublishInv", "ERR:20"));
        var settings = VnptSettings();
        var order = Order10PctIncluded();
        await Seed(db, settings, order);

        await svc.IssueNowAsync(order, Buyer);

        Assert.Equal("Failed", order.EInvoiceStatus);
        Assert.Contains("Mẫu số", order.EInvoiceError);
        Assert.Contains("ERR:20", order.EInvoiceError);
    }

    [Fact]
    public async Task Vnpt_cancel_envelope_and_err9()
    {
        var http = new FakeVendor().OnSoap("cancelInv", Soap("cancelInv", "ERR:9"));
        var client = new VnptInvoiceClient(http, NullLogger<VnptInvoiceClient>.Instance);

        var r = await client.CancelAsync("0312345678-tt78admindemo.vnpt-invoice.com.vn", "admin-test", "x",
            "service-test", "y", "fkey-1");

        Assert.False(r.Ok);
        Assert.Equal("ERR:9", r.ErrorCode);
        Assert.Contains("Trạng thái hóa đơn", r.Error);
        var req = Assert.Single(http.Requests);
        Assert.EndsWith("/BusinessService.asmx", req.Uri.AbsolutePath);
        var op = SoapOp(req.Body, "cancelInv");
        Assert.Equal(new[] { "Account", "ACpass", "fkey", "userName", "userPass" },
            op.Elements().Select(e => e.Name.LocalName).ToArray());
    }

    [Fact]
    public async Task Vnpt_list_by_fkey_reads_OK_prefixed_xml()
    {
        // Tài liệu VNPT: listInvByCusFkey thành công = «OK:» + <Data><Item>…</Item></Data>.
        const string data = "OK:<Data><Item><index>1</index><cusCode>KH01</cusCode><name>Công ty TNHH Thương mại Sao Việt</name>" +
                            "<publishDate>20/10/2026</publishDate><signStatus>1</signStatus><pattern>1/001</pattern>" +
                            "<serial>C26TAA</serial><invNum>123</invNum><payment>1</payment><amount>162000</amount>" +
                            "<status>1</status></Item></Data>";
        var http = new FakeVendor().OnSoap("listInvByCusFkey", Soap("listInvByCusFkey", data));
        var client = new VnptInvoiceClient(http, NullLogger<VnptInvoiceClient>.Instance);

        var r = await client.ListByFkeyAsync("https://0312345678-tt78admindemo.vnpt-invoice.com.vn", "service-test", "y",
            "fkey-1", new DateTime(2026, 10, 17), new DateTime(2026, 10, 21));

        Assert.True(r.Ok);
        var it = Assert.Single(r.Items);
        Assert.Equal("123", it.InvoiceNo);
        Assert.Equal("C26TAA", it.Serial);
        Assert.Equal(162000m, it.Amount);
        Assert.Equal(new DateTime(2026, 10, 20), it.PublishDate);
        Assert.Equal(BuyerCompany, it.CustomerName);
        Assert.Equal(1, it.Status);
        var op = SoapOp(Assert.Single(http.Requests).Body, "listInvByCusFkey");
        Assert.Equal("17/10/2026", op.Elements().First(e => e.Name.LocalName == "fromDate").Value);
        Assert.Equal("21/10/2026", op.Elements().First(e => e.Name.LocalName == "toDate").Value);
    }

    [Fact]
    public async Task Vnpt_view_err6_means_not_found()
    {
        var http = new FakeVendor().OnSoap("getInvViewFkeyNoPay", Soap("getInvViewFkeyNoPay", "ERR:6"));
        var client = new VnptInvoiceClient(http, NullLogger<VnptInvoiceClient>.Instance);

        var r = await client.ViewHtmlAsync("https://x-tt78admin.vnpt-invoice.com.vn", "u", "p", "fkey-1");

        Assert.False(r.Ok);
        Assert.Contains("Không tìm thấy hóa đơn", r.Error);
        Assert.DoesNotContain("hết số", r.Error);
    }

    [Fact]
    public async Task Vnpt_soap_fault_is_reported()
    {
        const string fault = """<?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"><soap:Body><soap:Fault><faultcode>soap:Client</faultcode><faultstring>Server was unable to read request.</faultstring></soap:Fault></soap:Body></soap:Envelope>""";
        var http = new FakeVendor().OnSoap("ImportAndPublishInv", fault, HttpStatusCode.InternalServerError);
        var client = new VnptInvoiceClient(http, NullLogger<VnptInvoiceClient>.Instance);

        var r = await client.ImportAndPublishAsync("https://x-tt78admin.vnpt-invoice.com.vn", "a", "b", "c", "d",
            "<DSHDon/>", "1/001", "C26TAA");

        Assert.False(r.Ok);
        Assert.Contains("lỗi SOAP", r.Error);
    }

    // ───────────────────────────── Viettel SInvoice v2 (nguồn thứ cấp) ─────────────────────────────

    [Fact]
    public async Task Viettel_create_invoice_8pct_payload_and_result()
    {
        var (svc, db, http) = NewService();
        http.OnPath("/auth/login", ViettelLoginOk)
            .OnPath("/InvoiceWS/createInvoice/0100109106-215",
                """{"errorCode":null,"description":null,"result":{"supplierTaxCode":"0100109106-215","invoiceNo":"C26TAA12","transactionID":"157241595858700001","reservationCode":"S4LVA6XBYA3A2PZ","codeOfTax":null}}""");
        var settings = ViettelSettings();
        var order = Order8Pct();
        await Seed(db, settings, order);

        await svc.IssueNowAsync(order, Buyer);

        Assert.Equal("Issued", order.EInvoiceStatus);
        Assert.Equal("C26TAA12", order.EInvoiceNo);
        Assert.Equal("S4LVA6XBYA3A2PZ", order.EInvoiceReservationCode);

        var login = http.Requests.Single(r => r.Uri.AbsolutePath == "/auth/login");
        Assert.Equal("https://api-vinvoice.viettel.vn/auth/login", login.Uri.ToString());
        var lb = Json(login.Body);
        Assert.Equal("0100109106-215", lb.GetProperty("username").GetString());
        Assert.Equal("test-pass", lb.GetProperty("password").GetString());

        var req = http.Requests.Single(r => r.Uri.AbsolutePath.Contains("/createInvoice/"));
        Assert.Equal(
            "https://api-vinvoice.viettel.vn/services/einvoiceapplication/api/InvoiceAPI/InvoiceWS/createInvoice/0100109106-215",
            req.Uri.ToString());
        Assert.Equal("access_token=vt-token", req.Headers["Cookie"]);

        var root = Json(req.Body);
        var gi = root.GetProperty("generalInvoiceInfo");
        Assert.Equal(order.EInvoiceTransactionUuid, gi.GetProperty("transactionUuid").GetString());
        Assert.Equal("1", gi.GetProperty("invoiceType").GetString());
        Assert.Equal("1/001", gi.GetProperty("templateCode").GetString());
        Assert.Equal("C26TAA", gi.GetProperty("invoiceSeries").GetString());
        Assert.Equal("VND", gi.GetProperty("currencyCode").GetString());
        Assert.Equal("1", gi.GetProperty("adjustmentType").GetString());
        Assert.True(gi.GetProperty("paymentStatus").GetBoolean());
        Assert.Equal(new DateTimeOffset(SaleUtc).ToUnixTimeMilliseconds(), gi.GetProperty("invoiceIssuedDate").GetInt64());

        var b = root.GetProperty("buyerInfo");
        Assert.Equal(BuyerPerson, b.GetProperty("buyerName").GetString());
        Assert.Equal(BuyerCompany, b.GetProperty("buyerLegalName").GetString());
        Assert.Equal(BuyerMst, b.GetProperty("buyerTaxCode").GetString());
        Assert.Equal(BuyerAddress, b.GetProperty("buyerAddressLine").GetString());

        var items = root.GetProperty("itemInfo").EnumerateArray().ToList();
        Assert.Equal(2, items.Count);
        Assert.All(items, i => Assert.Equal(8d, i.GetProperty("taxPercentage").GetDouble()));
        Assert.Equal(96774d, items[0].GetProperty("itemTotalAmountWithoutTax").GetDouble());
        Assert.Equal(7742d, items[0].GetProperty("taxAmount").GetDouble());
        Assert.Equal(104516d, items[0].GetProperty("itemTotalAmountWithTax").GetDouble());
        Assert.Equal("Ly", items[0].GetProperty("unitName").GetString());

        var sum = root.GetProperty("summarizeInfo");
        Assert.Equal(150000d, sum.GetProperty("sumOfTotalLineAmountWithoutTax").GetDouble());
        Assert.Equal(150000d, sum.GetProperty("totalAmountWithoutTax").GetDouble());
        Assert.Equal(12000d, sum.GetProperty("totalTaxAmount").GetDouble());
        Assert.Equal(162000d, sum.GetProperty("totalAmountWithTax").GetDouble());
        Assert.Equal(sum.GetProperty("totalTaxAmount").GetDouble(),
            items.Sum(i => i.GetProperty("taxAmount").GetDouble()));

        var tb = Assert.Single(root.GetProperty("taxBreakdowns").EnumerateArray().ToList());
        Assert.Equal(8d, tb.GetProperty("taxPercentage").GetDouble());
        Assert.Equal(150000d, tb.GetProperty("taxableAmount").GetDouble());
        Assert.Equal(12000d, tb.GetProperty("taxAmount").GetDouble());
        Assert.Equal("1", root.GetProperty("payments")[0].GetProperty("paymentMethod").GetString());
    }

    [Fact]
    public async Task Viettel_error_code_marks_failed()
    {
        var (svc, db, http) = NewService();
        http.OnPath("/auth/login", ViettelLoginOk)
            .OnPath("/InvoiceWS/createInvoice/0100109106-215",
                """{"errorCode":"INVOICE_SERIES_NOT_FOUND","description":"Ký hiệu hóa đơn không tồn tại","result":null}""",
                HttpStatusCode.BadRequest);
        var settings = ViettelSettings();
        var order = Order10PctIncluded();
        await Seed(db, settings, order);

        await svc.IssueNowAsync(order, Buyer);

        Assert.Equal("Failed", order.EInvoiceStatus);
        Assert.Contains("Ký hiệu hóa đơn không tồn tại", order.EInvoiceError);
    }

    [Fact]
    public async Task Viettel_signature_not_found_falls_back_to_draft()
    {
        var (svc, db, http) = NewService();
        http.OnPath("/auth/login", ViettelLoginOk)
            .OnPath("/InvoiceWS/createInvoice/0100109106-215",
                """{"code":400,"message":"SIGNATURE_NOT_FOUND","data":null}""", HttpStatusCode.InternalServerError)
            .OnPath("/InvoiceWS/createOrUpdateInvoiceDraft/0100109106-215",
                """{"errorCode":null,"description":null,"result":{"supplierTaxCode":"0100109106-215","invoiceNo":null,"transactionID":"T1","reservationCode":"R1"}}""");
        var settings = ViettelSettings();
        var order = Order8Pct();
        await Seed(db, settings, order);

        await svc.IssueNowAsync(order, Buyer);

        Assert.Equal("Pending", order.EInvoiceStatus);
        Assert.Equal("R1", order.EInvoiceReservationCode);
        Assert.Contains("chờ ký số", order.EInvoiceError);
    }

    [Fact]
    public async Task Viettel_get_invoices_reads_totalRows()
    {
        var http = new FakeVendor().OnPath("/InvoiceUtilsWS/getInvoices/0100109106-215",
            """{"errorCode":null,"description":null,"totalRows":57,"invoices":[{"invoiceNo":"C26TAA12","templateCode":"1/001","invoiceSeri":"C26TAA","issueDate":1792465200000,"total":162000,"taxAmount":12000,"buyerName":"Trần Thị Mai","buyerTaxCode":"0312345678","adjustmentType":"1"}]}""");
        var client = new ViettelSInvoiceClient(http, new MemoryCache(new MemoryCacheOptions()),
            NullLogger<ViettelSInvoiceClient>.Instance);

        var r = await client.GetInvoicesAsync("", "vt-token", "0100109106-215",
            new DateTime(2026, 10, 1), new DateTime(2026, 10, 31), 1, 50);

        Assert.True(r.Ok);
        Assert.Equal(57, r.Total);
        var it = Assert.Single(r.Items);
        Assert.Equal(162000m, it.Total);
        Assert.Equal(12000m, it.TaxAmount);
    }

    [Fact]
    public async Task Viettel_cancel_sends_form_with_ms_issue_date()
    {
        var http = new FakeVendor().OnPath("/InvoiceWS/cancelTransactionInvoice",
            """{"errorCode":null,"description":"SUCCESS","result":null}""");
        var client = new ViettelSInvoiceClient(http, new MemoryCache(new MemoryCacheOptions()),
            NullLogger<ViettelSInvoiceClient>.Instance);

        var r = await client.CancelInvoiceAsync("", "vt-token", "0100109106-215", "C26TAA12", SaleUtc,
            "Biên bản thỏa thuận hủy số 01", new DateTime(2026, 10, 21, 2, 0, 0, DateTimeKind.Utc), "Sai thông tin");

        Assert.True(r.Ok);
        var req = Assert.Single(http.Requests);
        Assert.StartsWith("application/x-www-form-urlencoded", req.ContentType);
        var form = req.Body.Split('&').Select(p => p.Split('=', 2))
            .ToDictionary(p => p[0], p => Uri.UnescapeDataString(p[1].Replace('+', ' ')));
        Assert.Equal("0100109106-215", form["supplierTaxCode"]);
        Assert.Equal("C26TAA12", form["invoiceNo"]);
        Assert.Equal(new DateTimeOffset(SaleUtc).ToUnixTimeMilliseconds().ToString(), form["strIssueDate"]);
        Assert.Equal("20261021090000", form["additionalReferenceDate"]);
        Assert.Equal("Biên bản thỏa thuận hủy số 01", form["additionalReferenceDesc"]);
    }

    // ───────────────────────────── Easy Invoice (giả định — chưa có tài liệu công khai) ─────────────────────────────

    [Fact]
    public void Easy_token_is_md5_signature_nonce_timestamp_credentials()
    {
        var token = EasyInvoiceClient.GenerateToken("post", "testapi", "pw", "0312345678");
        var parts = token.Split(':');
        Assert.Equal(6, parts.Length);
        var (sig, nonce, ts) = (parts[0], parts[1], parts[2]);
        Assert.Matches("^[0-9a-f]{32}$", nonce);
        Assert.True(long.TryParse(ts, out var sec));
        Assert.InRange(sec, DateTimeOffset.UtcNow.ToUnixTimeSeconds() - 60, DateTimeOffset.UtcNow.ToUnixTimeSeconds() + 1);
        Assert.Equal(Convert.ToBase64String(MD5.HashData(Encoding.UTF8.GetBytes($"POST{ts}{nonce}"))), sig);
        Assert.Equal(new[] { "testapi", "pw", "0312345678" }, parts[3..]);
    }

    [Fact]
    public async Task Easy_import_and_issue_xml_and_result()
    {
        var (svc, db, http) = NewService();
        var settings = EasySettings();
        var order = Order8Pct();
        order.EInvoiceTransactionUuid = Guid.NewGuid().ToString();
        http.OnPath("/api/publish/importAndIssueInvoice",
            """{"Status":2,"Message":"","Data":{"Pattern":"1C26MAA","Serial":"","KeyInvoiceNo":{"IKEY":"12"},"Invoices":[{"Ikey":"IKEY","No":"12","LookupCode":"LK8X2Q","Pattern":"1C26MAA","Serial":"","TaxAuthorityCode":"M1-26-ABCDE-00000000012"}]}}"""
                .Replace("IKEY", order.EInvoiceTransactionUuid));
        await Seed(db, settings, order);

        await svc.IssueNowAsync(order, Buyer);

        Assert.Equal("Issued", order.EInvoiceStatus);
        Assert.Equal("12", order.EInvoiceNo);
        Assert.Equal("LK8X2Q", order.EInvoiceReservationCode);
        Assert.Equal("M1-26-ABCDE-00000000012", order.EInvoiceCode);

        var req = Assert.Single(http.Requests);
        Assert.Equal("https://api.softdreams.vn/api/publish/importAndIssueInvoice", req.Uri.ToString());
        Assert.EndsWith(":testapi:test-pass:0101243150", req.Headers["Authentication"]);
        var body = Json(req.Body);
        Assert.Equal("1C26MAA", body.GetProperty("Pattern").GetString());
        Assert.Equal("", body.GetProperty("Serial").GetString());

        var inv = XElement.Parse(body.GetProperty("XmlData").GetString()!).Element("Inv")!.Element("Invoice")!;
        Assert.Equal(order.EInvoiceTransactionUuid, inv.Element("Ikey")!.Value);
        Assert.Equal(BuyerMst, inv.Element("CusTaxCode")!.Value);
        Assert.Equal(BuyerCompany, inv.Element("CusName")!.Value);
        Assert.Equal(BuyerPerson, inv.Element("Buyer")!.Value);
        Assert.Equal("20/10/2026", inv.Element("ArisingDate")!.Value);
        Assert.Equal("8", inv.Element("VATRate")!.Value);
        Assert.Equal("150000", inv.Element("Total")!.Value);
        Assert.Equal("12000", inv.Element("VATAmount")!.Value);
        Assert.Equal("162000", inv.Element("Amount")!.Value);
        Assert.Equal("150000", inv.Element("GrossValue8")!.Value);
        Assert.Equal("12000", inv.Element("VatAmount8")!.Value);
        Assert.Equal("162000", inv.Element("Amount8")!.Value);
        var products = inv.Element("Products")!.Elements("Product").ToList();
        Assert.Equal(2, products.Count);
        Assert.Equal("96774", products[0].Element("Total")!.Value);
        Assert.Equal("7742", products[0].Element("VATAmount")!.Value);
        Assert.Equal("8", products[0].Element("VATRate")!.Value);
    }

    [Fact]
    public async Task Easy_error_117_is_explained()
    {
        var (svc, db, http) = NewService();
        http.OnPath("/api/publish/importAndIssueInvoice",
            """{"Status":1,"ErrorCode":"117","Message":"Mẫu hóa đơn không khả dụng","Data":null}""");
        var settings = EasySettings();
        var order = Order10PctIncluded();
        await Seed(db, settings, order);

        await svc.IssueNowAsync(order, Buyer);

        Assert.Equal("Failed", order.EInvoiceStatus);
        Assert.Contains("Error 117", order.EInvoiceError);
    }

    // ───────────────────────────── Dữ liệu mẫu ─────────────────────────────

    const string MisaTestUrl = "https://testapi.meinvoice.vn/api/integration";

    const string MisaTokenOk =
        """{"Success":true,"ErrorCode":null,"Errors":[],"Data":"eyJhbGciOiJIUzI1NiJ9.test.sig","CustomData":null}""";

    const string ViettelLoginOk =
        """{"access_token":"vt-token","token_type":"bearer","refresh_token":"r","expires_in":599,"scope":"openid","iat":1792465200,"invoice_cluster":"cluster2","type":1,"jti":"j"}""";

    static string MisaPublishOk(string transactionId, string invNo) =>
        $$"""{"success":true,"errorCode":null,"descriptionErrorCode":null,"createInvoiceResult":null,"publishInvoiceResult":"[{\"RefID\":\"r\",\"TransactionID\":\"{{transactionId}}\",\"InvTemplateNo\":null,\"InvSeries\":null,\"InvNo\":\"{{invNo}}\",\"InvCode\":null,\"InvDate\":\"2026-10-20T00:00:00+07:00\",\"ErrorCode\":\"\",\"CustomData\":null}]"}""";

    static PosEInvoiceSetting BaseSettings(string provider) => new()
    {
        Id = Guid.NewGuid(),
        StoreId = StoreId,
        Enabled = true,
        Provider = provider,
        Username = "test-user",
        Password = "test-pass",
        SupplierTaxCode = "0101243150",
        InvoiceType = "1",
        TaxMode = "added",
        DefaultTaxPercent = 8,
        IsActive = true,
    };

    static PosEInvoiceSetting MisaSettings()
    {
        var s = BaseSettings("Misa");
        s.ApiBaseUrl = MisaTestUrl;
        s.AppId = "APPID-TEST";
        s.TemplateCode = "1";
        s.InvoiceSeries = "C26TAA";
        s.SignType = 2;
        return s;
    }

    static PosEInvoiceSetting VnptSettings()
    {
        var s = BaseSettings("Vnpt");
        s.ApiBaseUrl = "https://0312345678-tt78admindemo.vnpt-invoice.com.vn";
        s.ServiceAccount = "admin-test";
        s.ServicePassword = "admin-pass";
        s.Username = "service-test";
        s.TemplateCode = "1/001";
        s.InvoiceSeries = "C26TAA";
        return s;
    }

    static PosEInvoiceSetting ViettelSettings()
    {
        var s = BaseSettings("Viettel");
        s.ApiBaseUrl = "https://api-vinvoice.viettel.vn";
        s.Username = "0100109106-215";
        s.SupplierTaxCode = "0100109106-215";
        s.TemplateCode = "1/001";
        s.InvoiceSeries = "C26TAA";
        return s;
    }

    static PosEInvoiceSetting EasySettings()
    {
        var s = BaseSettings("Easy");
        s.ApiBaseUrl = "https://api.softdreams.vn";
        s.Username = "testapi";
        s.TemplateCode = "1C26MAA";
        s.InvoiceSeries = "";
        return s;
    }

    /// <summary>
    /// 3 ly cà phê 35.000 (CK dòng 5.000) + 2 bánh mì 27.500; CK đơn 5.000; VAT 8% cộng thêm = 12.000.
    /// Phân bổ CK đơn: 3.226 / 1.774 → thành tiền 96.774 / 53.226; thuế 7.742 / 4.258.
    /// </summary>
    static PosSaleOrder Order8Pct()
    {
        var o = NewOrder(total: 150000m, vat: 12000m);
        o.Discount = 5000m;
        o.SubTotal = 155000m;
        o.Lines =
        [
            Line(o, "Cà phê sữa đá", "Ly", 3, 35000m, 5000m, 100000m),
            Line(o, "Bánh mì thịt nướng", "Ổ", 2, 27500m, 0m, 55000m),
        ];
        return o;
    }

    /// <summary>2 ly trà sữa 55.000 — giá đã gồm VAT 10% → 100.000 + 10.000.</summary>
    static PosSaleOrder Order10PctIncluded()
    {
        var o = NewOrder(total: 110000m, vat: 0m);
        o.SubTotal = 110000m;
        o.Lines = [Line(o, "Trà sữa trân châu", "Ly", 2, 55000m, 0m, 110000m)];
        return o;
    }

    static PosSaleOrder NewOrder(decimal total, decimal vat) => new()
    {
        Id = Guid.NewGuid(),
        StoreId = StoreId,
        OrderNo = "HD" + Random.Shared.Next(100000, 999999),
        Total = total,
        VatAmount = vat,
        PaidAmount = total + vat,
        PaymentMethod = "Tiền mặt",
        CustomerName = BuyerPerson,
        SaleDate = SaleUtc,
        IsActive = true,
    };

    static PosSaleOrderLine Line(PosSaleOrder o, string name, string unit, decimal qty, decimal price,
        decimal discount, decimal lineTotal) => new()
    {
        Id = Guid.NewGuid(),
        StoreId = o.StoreId,
        SaleOrderId = o.Id,
        ProductId = Guid.NewGuid(),
        ProductName = name,
        UnitName = unit,
        Qty = qty,
        UnitPrice = price,
        DiscountAmount = discount,
        LineTotal = lineTotal,
        IsActive = true,
    };

    static (PosEInvoiceService Svc, ZKTecoDbContext Db, FakeVendor Http) NewService()
    {
        var db = new ZKTecoDbContext(new DbContextOptionsBuilder<ZKTecoDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options);
        var http = new FakeVendor();
        var cache = new MemoryCache(new MemoryCacheOptions());
        var svc = new PosEInvoiceService(
            db,
            new ViettelSInvoiceClient(http, cache, NullLogger<ViettelSInvoiceClient>.Instance),
            new EasyInvoiceClient(http, NullLogger<EasyInvoiceClient>.Instance),
            new MisaMeInvoiceClient(http, cache, NullLogger<MisaMeInvoiceClient>.Instance),
            new VnptInvoiceClient(http, NullLogger<VnptInvoiceClient>.Instance),
            NullLogger<PosEInvoiceService>.Instance);
        return (svc, db, http);
    }

    static MisaMeInvoiceClient NewMisaClient(FakeVendor http) =>
        new(http, new MemoryCache(new MemoryCacheOptions()), NullLogger<MisaMeInvoiceClient>.Instance);

    static async Task Seed(ZKTecoDbContext db, PosEInvoiceSetting s, PosSaleOrder o)
    {
        db.PosEInvoiceSettings.Add(s);
        db.PosSaleOrders.Add(o);
        await db.SaveChangesAsync();
    }

    static JsonElement Json(string body)
    {
        using var doc = JsonDocument.Parse(body);
        return doc.RootElement.Clone();
    }

    static readonly XNamespace SoapNs = "http://schemas.xmlsoap.org/soap/envelope/";
    static readonly XNamespace Tempuri = "http://tempuri.org/";

    /// <summary>Phản hồi SOAP asmx chuẩn: &lt;{op}Response&gt;&lt;{op}Result&gt;…</summary>
    static string Soap(string op, string result) =>
        new XDocument(new XDeclaration("1.0", "utf-8", null),
            new XElement(SoapNs + "Envelope", new XAttribute(XNamespace.Xmlns + "soap", SoapNs),
                new XElement(SoapNs + "Body",
                    new XElement(Tempuri + (op + "Response"),
                        new XElement(Tempuri + (op + "Result"), result))))).ToString();

    static XElement SoapOp(string envelope, string op)
    {
        var doc = XDocument.Parse(envelope);
        var el = doc.Root!.Element(SoapNs + "Body")!.Element(Tempuri + op);
        Assert.NotNull(el);
        return el!;
    }

    sealed record Captured(HttpMethod Method, Uri Uri, Dictionary<string, string> Headers, string? ContentType, string Body);

    /// <summary>Máy chủ hãng giả: ghi lại request, trả phản hồi theo đường dẫn / SOAPAction.</summary>
    sealed class FakeVendor : HttpMessageHandler, IHttpClientFactory
    {
        readonly List<(Func<Captured, bool> Match, HttpStatusCode Code, string Body, string Type)> _routes = [];
        public List<Captured> Requests { get; } = [];

        public FakeVendor OnPath(string pathEndsWith, string body, HttpStatusCode code = HttpStatusCode.OK)
        {
            _routes.Add((c => c.Uri.AbsolutePath.EndsWith(pathEndsWith, StringComparison.OrdinalIgnoreCase),
                code, body, "application/json"));
            return this;
        }

        public FakeVendor OnSoap(string operation, string body, HttpStatusCode code = HttpStatusCode.OK)
        {
            _routes.Add((c => c.Headers.TryGetValue("SOAPAction", out var a) &&
                              a.Trim('"').EndsWith("/" + operation, StringComparison.Ordinal),
                code, body, "text/xml"));
            return this;
        }

        public HttpClient CreateClient(string name) => new(this, disposeHandler: false);

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            var headers = request.Headers.ToDictionary(h => h.Key, h => string.Join(",", h.Value));
            var body = request.Content == null ? "" : await request.Content.ReadAsStringAsync(ct);
            var cap = new Captured(request.Method, request.RequestUri!, headers,
                request.Content?.Headers.ContentType?.ToString(), body);
            Requests.Add(cap);
            foreach (var r in _routes)
            {
                if (!r.Match(cap)) continue;
                return new HttpResponseMessage(r.Code)
                {
                    Content = new StringContent(r.Body, Encoding.UTF8, r.Type),
                };
            }
            return new HttpResponseMessage(HttpStatusCode.NotFound) { Content = new StringContent("") };
        }
    }
}
