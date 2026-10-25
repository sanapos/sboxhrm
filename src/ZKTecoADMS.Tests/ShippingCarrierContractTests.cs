using System.Net;
using System.Text;
using System.Text.Json;
using System.Web;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Api.Services.Shipping;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>
/// Hợp đồng API từng hãng giao vận, đối chiếu tài liệu chính thức (không gọi API thật — HttpMessageHandler giả):
/// GHN developer.ghn.vn · GHTK api.ghtk.vn/docs + pro-docs.ghtk.vn · Viettel Post partner2.viettelpost.vn ·
/// SPX spx.vn/integration (SPX Open Service) · AhaMove developers.ahamove.com (v3).
/// </summary>
public class ShippingCarrierContractTests
{
    // ── Hạ tầng HTTP giả ─────────────────────────────────────────────

    sealed record Captured(string Method, Uri Uri, Dictionary<string, string> Headers, string? Body)
    {
        public JsonElement Json => JsonDocument.Parse(Body!).RootElement.Clone();
        public System.Collections.Specialized.NameValueCollection Query => HttpUtility.ParseQueryString(Uri.Query);
        public string? Header(string name) => Headers.TryGetValue(name, out var v) ? v : null;
    }

    sealed class FakeHttp : HttpMessageHandler
    {
        public readonly List<Captured> Requests = [];
        readonly List<(string Method, string Path, HttpStatusCode Status, string Body, bool Once)> _routes = [];

        public FakeHttp On(string method, string pathEndsWith, string body,
            HttpStatusCode status = HttpStatusCode.OK, bool once = false)
        {
            _routes.Add((method, pathEndsWith, status, body, once));
            return this;
        }

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage req, CancellationToken ct)
        {
            var body = req.Content == null ? null : await req.Content.ReadAsStringAsync(ct);
            Requests.Add(new Captured(req.Method.Method, req.RequestUri!,
                req.Headers.ToDictionary(h => h.Key, h => string.Join(",", h.Value), StringComparer.OrdinalIgnoreCase),
                body));
            for (var i = 0; i < _routes.Count; i++)
            {
                var r = _routes[i];
                if (!string.Equals(r.Method, req.Method.Method, StringComparison.OrdinalIgnoreCase)) continue;
                if (!req.RequestUri!.AbsolutePath.EndsWith(r.Path, StringComparison.OrdinalIgnoreCase)) continue;
                if (r.Once) _routes.RemoveAt(i);
                return new HttpResponseMessage(r.Status)
                {
                    Content = new StringContent(r.Body, Encoding.UTF8, "application/json"),
                };
            }
            return new HttpResponseMessage(HttpStatusCode.NotFound)
            {
                Content = new StringContent($"no fake route for {req.Method} {req.RequestUri}"),
            };
        }

        public Captured Single(string pathEndsWith) =>
            Assert.Single(Requests, r => r.Uri.AbsolutePath.EndsWith(pathEndsWith, StringComparison.OrdinalIgnoreCase));
    }

    sealed class FakeFactory(FakeHttp handler) : IHttpClientFactory
    {
        public HttpClient CreateClient(string name) => new(handler, disposeHandler: false);
    }

    static PosSaleOrder DaNangOrder(string? district = null, string? ward = "Phường Hải Châu") => new()
    {
        Id = Guid.NewGuid(),
        StoreId = Guid.NewGuid(),
        OrderNo = "HD000123",
        CustomerName = "Nguyễn Văn An",
        DeliveryPhone = "0912345678",
        DeliveryAddress = "45 Lê Duẩn",
        DeliveryProvince = "Thành phố Đà Nẵng",
        DeliveryDistrict = district,
        DeliveryWard = ward,
        IsDelivery = true,
        Total = 450_000,
        Lines =
        [
            new PosSaleOrderLine { ProductId = Guid.NewGuid(), ProductName = "Áo thun cotton", Qty = 1, UnitPrice = 150_000 },
            new PosSaleOrderLine { ProductId = Guid.NewGuid(), ProductName = "Quần jean", Qty = 2, UnitPrice = 150_000 },
        ],
    };

    static ShippingQuoteRequest DaNangQuote(string carrier, string? district = null, string? ward = "Phường Hải Châu") =>
        new(carrier, "Nguyễn Văn An", "0912345678", "45 Lê Duẩn", "Thành phố Đà Nẵng", district, ward,
            WeightGrams: 1200, CodAmount: 350_000, InsuranceValue: 450_000, LengthCm: 30, WidthCm: 20, HeightCm: 10);

    // ══ GHN — developer.ghn.vn ════════════════════════════════════════

    static PosShippingCarrierSetting GhnSettings() => new()
    {
        CarrierCode = ShippingCarrierCodes.Ghn,
        ApiToken = "ghn-test-token",
        ShopId = "885",
        FromDistrictId = "1442",
        FromWardCode = "20109",
        PickupName = "SBOX Quận 1",
        PickupPhone = "0905123456",
        PickupAddress = "15 Lê Lợi",
        FromProvinceName = "Thành phố Hồ Chí Minh",
        FromDistrictName = "Quận 1",
        FromWardName = "Phường Bến Nghé",
    };

    const string GhnFeeOk = """{"code":200,"message":"Success","data":{"total":36300,"service_fee":36300,"insurance_fee":0,"cod_fee":0}}""";

    [Fact]
    public async Task Ghn_fee_gui_dung_header_va_don_vi_theo_docs()
    {
        var http = new FakeHttp().On("POST", "/shiip/public-api/v2/shipping-order/fee", GhnFeeOk);
        var client = new GhnShippingClient(new FakeFactory(http), NullLogger<GhnShippingClient>.Instance);

        var req = DaNangQuote("Ghn", district: "1526", ward: "40101") with { InsuranceValue = 8_000_000 };
        var r = await client.QuoteAsync(GhnSettings(), req);

        Assert.True(r.Success, r.Message);
        Assert.Equal(36300m, r.Fee);
        var call = http.Single("/v2/shipping-order/fee");
        Assert.Equal("POST", call.Method);
        Assert.Equal("ghn-test-token", call.Header("Token"));
        Assert.Equal("885", call.Header("ShopId"));
        var b = call.Json;
        Assert.Equal(1200, b.GetProperty("weight").GetInt32());                 // gram
        Assert.Equal(2, b.GetProperty("service_type_id").GetInt32());
        Assert.Equal(1442, b.GetProperty("from_district_id").GetInt32());
        Assert.Equal(1526, b.GetProperty("to_district_id").GetInt32());
        Assert.Equal(JsonValueKind.String, b.GetProperty("to_ward_code").ValueKind); // WardCode là chuỗi
        Assert.Equal("40101", b.GetProperty("to_ward_code").GetString());
        Assert.Equal(350_000, b.GetProperty("cod_value").GetInt32());           // fee dùng cod_value
        Assert.Equal(5_000_000, b.GetProperty("insurance_value").GetInt32());   // trần bảo hiểm 5tr
    }

    [Fact]
    public async Task Ghn_master_data_quan_phuong_goi_GET_query_theo_docs()
    {
        var http = new FakeHttp()
            .On("GET", "/master-data/province",
                """{"code":200,"data":[{"ProvinceID":202,"ProvinceName":"Hồ Chí Minh"},{"ProvinceID":203,"ProvinceName":"Đà Nẵng"}]}""")
            .On("GET", "/master-data/district",
                """{"code":200,"data":[{"DistrictID":1526,"DistrictName":"Quận Hải Châu"},{"DistrictID":1527,"DistrictName":"Quận Thanh Khê"}]}""")
            .On("GET", "/master-data/ward", """{"code":200,"data":[{"WardCode":"40101","WardName":"Phường Thạch Thang"}]}""")
            .On("POST", "/v2/shipping-order/fee", GhnFeeOk);
        var client = new GhnShippingClient(new FakeFactory(http), NullLogger<GhnShippingClient>.Instance);

        var r = await client.QuoteAsync(GhnSettings(), DaNangQuote("Ghn", "Quận Hải Châu", "Phường Thạch Thang"));

        Assert.True(r.Success, r.Message);
        Assert.Equal("203", http.Single("/master-data/district").Query["province_id"]);
        Assert.Equal("1526", http.Single("/master-data/ward").Query["district_id"]);
        Assert.DoesNotContain(http.Requests, x => x.Method == "POST" && x.Uri.AbsolutePath.Contains("master-data"));
        Assert.Equal("40101", http.Single("/v2/shipping-order/fee").Json.GetProperty("to_ward_code").GetString());
    }

    [Fact]
    public async Task Ghn_nhieu_goi_gui_service_type_id_cho_fee_va_leadtime()
    {
        var lead = DateTimeOffset.UtcNow.AddDays(2).ToUnixTimeSeconds();
        var http = new FakeHttp()
            .On("POST", "/v2/shipping-order/available-services",
                """{"code":200,"data":[{"service_id":53320,"short_name":"Hàng nhẹ","service_type_id":2}]}""")
            .On("POST", "/v2/shipping-order/fee", GhnFeeOk)
            .On("POST", "/v2/shipping-order/leadtime", $$$"""{"code":200,"data":{"leadtime":{{{lead}}}}}""");
        var client = new GhnShippingClient(new FakeFactory(http), NullLogger<GhnShippingClient>.Instance);

        var list = await client.QuoteOptionsAsync(GhnSettings(), DaNangQuote("Ghn", "1526", "40101"));

        var opt = Assert.Single(list);
        Assert.True(opt.Success, opt.Message);
        Assert.True(opt.EtaMinutes > 0);
        Assert.Equal(885, http.Single("/available-services").Json.GetProperty("shop_id").GetInt32());
        var fee = http.Single("/v2/shipping-order/fee").Json;
        Assert.Equal(2, fee.GetProperty("service_type_id").GetInt32());
        var lt = http.Single("/v2/shipping-order/leadtime").Json;
        Assert.Equal(2, lt.GetProperty("service_type_id").GetInt32());
        Assert.False(lt.TryGetProperty("service_id", out _)); // docs: service_id không có tác dụng
    }

    [Fact]
    public async Task Ghn_tao_don_dia_chi_2_cap_gui_is_new_to_address()
    {
        var http = new FakeHttp().On("POST", "/v2/shipping-order/create",
            """{"code":200,"message":"Success","data":{"order_code":"LDFKQ8","total_fee":36300,"expected_delivery_time":"2026-10-27T16:59:59Z","fee":{"main_service":33000,"insurance":3300}}}""");
        var client = new GhnShippingClient(new FakeFactory(http), NullLogger<GhnShippingClient>.Instance);
        var order = DaNangOrder();

        var r = await client.CreateAsync(GhnSettings(), order,
            new ShippingCreateRequest("Ghn", order.Id, CodAmount: 450_000, WeightGrams: 800));

        Assert.True(r.Success, r.Message);
        Assert.Equal("LDFKQ8", r.TrackingCode);
        Assert.Equal(36300m, r.Fee);   // tổng ở data.total_fee, không phải fee.main_service
        // Không quét master-data cũ để đoán quận — chỉ 1 request tạo đơn.
        var call = Assert.Single(http.Requests);
        var b = call.Json;
        Assert.True(b.GetProperty("is_new_to_address").GetBoolean());
        Assert.False(b.GetProperty("is_new_from_address").GetBoolean());
        Assert.Equal("", b.GetProperty("to_district_name").GetString());
        Assert.Equal("Phường Hải Châu", b.GetProperty("to_ward_name").GetString());
        Assert.Equal("Thành phố Đà Nẵng", b.GetProperty("to_province_name").GetString());
        Assert.False(b.TryGetProperty("to_district_id", out _));
        Assert.Equal(450_000, b.GetProperty("cod_amount").GetInt32());
        Assert.Equal(450_000, b.GetProperty("insurance_value").GetInt32());
        Assert.Equal(800, b.GetProperty("weight").GetInt32());
        Assert.Equal(1, b.GetProperty("payment_type_id").GetInt32());
        Assert.Equal("KHONGCHOXEMHANG", b.GetProperty("required_note").GetString());
        Assert.Equal("HD000123", b.GetProperty("client_order_code").GetString());
    }

    [Fact]
    public async Task Ghn_tao_don_dia_chi_3_cap_giu_ma_quan_phuong()
    {
        var http = new FakeHttp().On("POST", "/v2/shipping-order/create",
            """{"code":200,"message":"Success","data":{"order_code":"LDFKQ9","total_fee":22000}}""");
        var client = new GhnShippingClient(new FakeFactory(http), NullLogger<GhnShippingClient>.Instance);
        var order = DaNangOrder(district: "1526", ward: "40101");

        var r = await client.CreateAsync(GhnSettings(), order,
            new ShippingCreateRequest("Ghn", order.Id, CodAmount: 0, WeightGrams: 500, ShipFeePayer: "customer"));

        Assert.True(r.Success, r.Message);
        var b = http.Single("/v2/shipping-order/create").Json;
        Assert.False(b.GetProperty("is_new_to_address").GetBoolean());
        Assert.Equal(1526, b.GetProperty("to_district_id").GetInt32());
        Assert.Equal("40101", b.GetProperty("to_ward_code").GetString());
        Assert.Equal(2, b.GetProperty("payment_type_id").GetInt32()); // người nhận trả cước
    }

    [Fact]
    public async Task Ghn_loi_tao_don_doc_message()
    {
        var http = new FakeHttp().On("POST", "/v2/shipping-order/create",
            """{"code":400,"message":"Số điện thoại người nhận không hợp lệ","data":null,"code_message":"PHONE_INVALID"}""",
            HttpStatusCode.BadRequest);
        var client = new GhnShippingClient(new FakeFactory(http), NullLogger<GhnShippingClient>.Instance);
        var order = DaNangOrder();

        var r = await client.CreateAsync(GhnSettings(), order, new ShippingCreateRequest("Ghn", order.Id));

        Assert.False(r.Success);
        Assert.Contains("không hợp lệ", r.Message);
    }

    [Fact]
    public async Task Ghn_tra_cuu_GET_order_code_va_huy_that_bai_theo_result()
    {
        var http = new FakeHttp()
            .On("GET", "/v2/shipping-order/detail",
                """{"code":200,"message":"Success","data":{"order_code":"LDFKQ8","status":"delivering","log":[{"status":"picked","updated_date":"2026-10-26T03:00:00Z"}]}}""")
            .On("POST", "/v2/switch-status/cancel",
                """{"code":200,"message":"Success","data":[{"order_code":"LDFKQ8","result":false,"message":"Đơn hàng không thể hủy"}]}""");
        var client = new GhnShippingClient(new FakeFactory(http), NullLogger<GhnShippingClient>.Instance);

        var t = await client.GetTrackingAsync(GhnSettings(), "LDFKQ8");
        Assert.True(t.Success, t.Message);
        Assert.Equal("delivering", t.StatusName);
        Assert.Equal("LDFKQ8", http.Single("/v2/shipping-order/detail").Query["order_code"]);
        Assert.Equal(ShipmentStatus.Delivering, ShipmentStatus.FromGhn(t.StatusName));

        var c = await client.CancelOrderAsync(GhnSettings(), "LDFKQ8");
        Assert.False(c.Success);
        Assert.Equal("Đơn hàng không thể hủy", c.Message);
        Assert.Equal("LDFKQ8", http.Single("/switch-status/cancel").Json.GetProperty("order_codes")[0].GetString());
    }

    [Theory]
    // Toàn bộ bảng trạng thái GHN (developer.ghn.vn/master-data/order-status).
    [InlineData("ready_to_pick", ShipmentStatus.Created)]
    [InlineData("picking", ShipmentStatus.Picking)]
    [InlineData("money_collect_picking", ShipmentStatus.Picking)]
    [InlineData("picked", ShipmentStatus.InTransit)]
    [InlineData("storing", ShipmentStatus.InTransit)]
    [InlineData("sorting", ShipmentStatus.InTransit)]
    [InlineData("transporting", ShipmentStatus.InTransit)]
    [InlineData("delivering", ShipmentStatus.Delivering)]
    [InlineData("money_collect_delivering", ShipmentStatus.Delivering)]
    [InlineData("delivered", ShipmentStatus.Delivered)]
    [InlineData("delivery_fail", ShipmentStatus.DeliveryFailed)]
    [InlineData("waiting_to_return", ShipmentStatus.Returning)]
    [InlineData("return", ShipmentStatus.Returning)]
    [InlineData("return_transporting", ShipmentStatus.Returning)]
    [InlineData("return_sorting", ShipmentStatus.Returning)]
    [InlineData("returning", ShipmentStatus.Returning)]
    [InlineData("return_fail", ShipmentStatus.Returning)]
    [InlineData("returned", ShipmentStatus.Returned)]
    [InlineData("cancel", ShipmentStatus.Cancelled)]
    [InlineData("exception", ShipmentStatus.Issue)]
    [InlineData("lost", ShipmentStatus.Issue)]
    [InlineData("damage", ShipmentStatus.Issue)]
    [InlineData("scrap", ShipmentStatus.Issue)]
    public void Ghn_moi_trang_thai_docs_deu_quy_doi(string status, string expected) =>
        Assert.Equal(expected, ShipmentStatus.FromGhn(status));

    // ══ GHTK — api.ghtk.vn/docs ═══════════════════════════════════════

    static PosShippingCarrierSetting GhtkSettings() => new()
    {
        CarrierCode = ShippingCarrierCodes.Ghtk,
        ApiToken = "ghtk-test-token",
        ShopId = "S1234567",
        PickupName = "SBOX Quận 1",
        PickupPhone = "0281234567",
        PickupAddress = "15 Lê Lợi",
        FromProvinceName = "Thành phố Hồ Chí Minh",
        FromDistrictName = "Quận 1",
        FromWardName = "Phường Bến Nghé",
    };

    [Fact]
    public async Task Ghtk_fee_GET_query_gram_va_dia_chi_2_cap()
    {
        var http = new FakeHttp().On("GET", "/services/shipment/fee",
            """{"success":true,"message":"","fee":{"name":"area2","fee":30400,"insurance_fee":0,"delivery":true}}""");
        var client = new GhtkShippingClient(new FakeFactory(http), NullLogger<GhtkShippingClient>.Instance);

        var r = await client.QuoteAsync(GhtkSettings(), DaNangQuote("Ghtk"));

        Assert.True(r.Success, r.Message);
        Assert.Equal(30400m, r.Fee);
        var call = http.Single("/services/shipment/fee");
        Assert.Equal("ghtk-test-token", call.Header("Token"));
        Assert.Equal("S1234567", call.Header("X-Client-Source"));
        var q = call.Query;
        Assert.Equal("1200", q["weight"]);                      // fee dùng gram
        Assert.Equal("Thành phố Đà Nẵng", q["province"]);
        Assert.Equal("Phường Hải Châu", q["ward"]);
        Assert.Null(q["district"]);                              // không nhét phường vào district
        Assert.Equal("Quận 1", q["pick_district"]);
        Assert.Equal("450000", q["value"]);
        Assert.Equal("road", q["transport"]);
    }

    [Fact]
    public async Task Ghtk_fee_delivery_false_la_khong_ho_tro_tuyen()
    {
        var http = new FakeHttp().On("GET", "/services/shipment/fee",
            """{"success":true,"fee":{"name":"area3","fee":0,"delivery":false}}""");
        var client = new GhtkShippingClient(new FakeFactory(http), NullLogger<GhtkShippingClient>.Instance);

        var r = await client.QuoteAsync(GhtkSettings(), DaNangQuote("Ghtk", "Quận Hải Châu", "Phường Hải Châu"));

        Assert.False(r.Success);
        Assert.Equal("Quận Hải Châu", http.Single("/services/shipment/fee").Query["district"]);
    }

    [Fact]
    public async Task Ghtk_tao_don_theo_docs_va_doc_fee_chuoi()
    {
        var http = new FakeHttp().On("POST", "/services/shipment/order/",
            """{"success":true,"message":"","order":{"partner_id":"HD000123","label":"S1.A1.17373471","area":"1","fee":"30400","insurance_fee":"0","tracking_id":17373471,"status_id":2}}""");
        var client = new GhtkShippingClient(new FakeFactory(http), NullLogger<GhtkShippingClient>.Instance);
        var order = DaNangOrder();
        var longNote = new string('x', 200);

        var r = await client.CreateAsync(GhtkSettings(), order, new ShippingCreateRequest(
            "Ghtk", order.Id, Note: longNote, CodAmount: 350_000, WeightGrams: 1200,
            LengthCm: 30, WidthCm: 20, HeightCm: 10));

        Assert.True(r.Success, r.Message);
        Assert.Equal("S1.A1.17373471", r.TrackingCode);
        Assert.Equal(30400m, r.Fee);   // docs: order.fee là chuỗi
        var call = http.Single("/services/shipment/order/");
        Assert.Equal("1.5", call.Query["ver"]);
        var b = call.Json;
        var o = b.GetProperty("order");
        Assert.Equal("HD000123", o.GetProperty("id").GetString());
        Assert.Equal(350_000, o.GetProperty("pick_money").GetInt32());
        Assert.Equal(1, o.GetProperty("is_freeship").GetInt32());
        Assert.Equal(450_000, o.GetProperty("value").GetInt32());
        Assert.Equal("Phường Hải Châu", o.GetProperty("ward").GetString());
        Assert.Equal(30, o.GetProperty("length").GetInt32());   // docs: order.length/width/height
        Assert.Equal(20, o.GetProperty("width").GetInt32());
        Assert.Equal(10, o.GetProperty("height").GetInt32());
        Assert.False(o.TryGetProperty("total_length", out _));
        Assert.Equal(120, o.GetProperty("note").GetString()!.Length);
        var products = b.GetProperty("products");
        Assert.Equal(2, products.GetArrayLength());
        Assert.Equal(0.6, products[0].GetProperty("weight").GetDouble(), 3); // kg
        Assert.Equal(2, products[1].GetProperty("quantity").GetInt32());
    }

    [Fact]
    public async Task Ghtk_order_id_da_ton_tai_nhan_lai_ma_van_don_cu()
    {
        var http = new FakeHttp().On("POST", "/services/shipment/order/",
            """{"success":false,"message":"Mã đơn hàng của bạn đã tồn tại trên hệ thống GHTK","error":{"code":"ORDER_ID_EXIST","partner_id":"HD000123","ghtk_label":"S1.A1.1737345","created":"2026-10-25T12:18:39+07:00","status":2}}""");
        var client = new GhtkShippingClient(new FakeFactory(http), NullLogger<GhtkShippingClient>.Instance);
        var order = DaNangOrder();

        var r = await client.CreateAsync(GhtkSettings(), order, new ShippingCreateRequest("Ghtk", order.Id));

        Assert.True(r.Success, r.Message);
        Assert.Equal("S1.A1.1737345", r.TrackingCode);
    }

    [Theory]
    [InlineData("""{"success":false,"message":"Mã đơn hàng của bạn đã tồn tại trên hệ thống GHTK","error":{"code":"ORDER_ID_EXIST","ghtk_label":"S1.A1.1737345","status":-1}}""", "đã tồn tại")]
    [InlineData("""{"success":false,"message":"Tuyến đường tạm ngưng phục vụ","error_code":"30610","log_id":"abc"}""", "tạm ngưng")]
    public async Task Ghtk_loi_nghiep_vu_HTTP_200_success_false(string json, string expected)
    {
        var http = new FakeHttp().On("POST", "/services/shipment/order/", json);
        var client = new GhtkShippingClient(new FakeFactory(http), NullLogger<GhtkShippingClient>.Instance);
        var order = DaNangOrder();

        var r = await client.CreateAsync(GhtkSettings(), order, new ShippingCreateRequest("Ghtk", order.Id));

        Assert.False(r.Success);
        Assert.Contains(expected, r.Message);
    }

    [Fact]
    public async Task Ghtk_nhan_pdf_dung_tham_so_page_size()
    {
        var http = new FakeHttp().On("GET", "/services/label/S1.A1.17373471", "%PDF-1.4 test");
        var client = new GhtkShippingClient(new FakeFactory(http), NullLogger<GhtkShippingClient>.Instance);

        var (pdf, err) = await client.DownloadLabelAsync(GhtkSettings(), "S1.A1.17373471");

        Assert.Null(err);
        Assert.NotNull(pdf);
        var q = http.Single("/services/label/S1.A1.17373471").Query;
        Assert.Equal("A6", q["page_size"]);
        Assert.Equal("portrait", q["original"]);
    }

    [Theory]
    // Docs webhook GHTK: 123/127/128/45/49/410 là «shipper báo» — chỉ thông tin, không phải trạng thái cuối.
    [InlineData(123, ShipmentStatus.Picking)]
    [InlineData(127, ShipmentStatus.Picking)]
    [InlineData(45, ShipmentStatus.Delivering)]
    [InlineData(49, ShipmentStatus.DeliveryFailed)]
    [InlineData(410, ShipmentStatus.Delivering)]
    [InlineData(1, ShipmentStatus.Created)]
    [InlineData(2, ShipmentStatus.Created)]
    [InlineData(12, ShipmentStatus.Picking)]
    [InlineData(3, ShipmentStatus.InTransit)]
    [InlineData(4, ShipmentStatus.Delivering)]
    [InlineData(5, ShipmentStatus.Delivered)]
    [InlineData(6, ShipmentStatus.Delivered)]
    [InlineData(7, ShipmentStatus.Cancelled)]
    [InlineData(9, ShipmentStatus.DeliveryFailed)]
    [InlineData(11, ShipmentStatus.Returned)]
    [InlineData(13, ShipmentStatus.Issue)]
    [InlineData(20, ShipmentStatus.Returning)]
    [InlineData(21, ShipmentStatus.Returned)]
    [InlineData(-1, ShipmentStatus.Cancelled)]
    public void Ghtk_status_id_quy_doi(int statusId, string expected) =>
        Assert.Equal(expected, ShipmentStatus.FromGhtk(statusId));

    [Fact]
    public void Ghtk_shipper_bao_da_giao_roi_sua_thanh_that_bai_khong_bi_khoa()
    {
        // Trước đây 45 → «Đã giao» (trạng thái khóa) nên 49 đến sau bị bỏ qua.
        var after45 = ShipmentStatus.FromGhtk(45)!;
        Assert.True(ShipmentStatus.CanTransition(after45, ShipmentStatus.FromGhtk(49)!));
        Assert.True(ShipmentStatus.CanTransition(after45, ShipmentStatus.FromGhtk(5)!));
        Assert.Equal("shipping", GhtkWebhookHelper.MapOnlineStatus(45));
        // 123 rồi sửa 127 (không lấy được) — không bị chặn vì «lùi bước».
        Assert.True(ShipmentStatus.CanTransition(ShipmentStatus.FromGhtk(123), ShipmentStatus.FromGhtk(127)!));
    }

    // ══ Viettel Post — partner2.viettelpost.vn ════════════════════════

    const string VtpJwt = "eyJhbGciOiJFUzI1NiJ9.eyJzdWIiOiIwOTA1MTIzNDU2In0.c2lnbmF0dXJlLXRlc3Q";

    static PosShippingCarrierSetting VtpSettings(bool sandbox = false) => new()
    {
        CarrierCode = ShippingCarrierCodes.ViettelPost,
        ApiToken = VtpJwt,
        UseSandbox = sandbox,
        PickupName = "SBOX Hải Châu",
        PickupPhone = "0905123456",
        PickupAddress = "12 Bạch Đằng",
        FromProvinceName = "Thành phố Đà Nẵng",
        FromWardName = "Phường Hải Châu",
    };

    static FakeHttp VtpCreateHttp() => new FakeHttp()
        .On("POST", "/v2/order/createOrderNlp",
            """{"status":200,"error":false,"message":"OK","data":{"ORDER_NUMBER":"1756123456789","MONEY_COLLECTION":350000,"EXCHANGE_WEIGHT":1000,"MONEY_TOTAL":38500,"MONEY_TOTAL_FEE":35000,"MONEY_FEE":0,"KPI_HT":24.0}}""")
        .On("POST", "/v2/order/printing-code",
            """{"status":200,"error":false,"message":"ISJDgZ3NSiYMtPUk7vTzQK8ZWUDexvvDKIclc0NplOU="}""");

    [Theory]
    // Docs createOrder ORDER_PAYMENT: 1 không thu · 2 thu hàng+cước · 3 chỉ thu hàng · 4 chỉ thu cước.
    [InlineData(0, "shop", 1)]
    [InlineData(0, "customer", 4)]
    [InlineData(350000, "shop", 3)]
    [InlineData(350000, "customer", 2)]
    public async Task Vtp_order_payment_theo_docs(int cod, string payer, int expected)
    {
        var http = VtpCreateHttp();
        var client = new ViettelPostShippingClient(new FakeFactory(http), NullLogger<ViettelPostShippingClient>.Instance);
        var order = DaNangOrder();

        var r = await client.CreateAsync(VtpSettings(), order, new ShippingCreateRequest(
            "ViettelPost", order.Id, CodAmount: cod, WeightGrams: 1200, ServiceCode: "VCN", ShipFeePayer: payer));

        Assert.True(r.Success, r.Message);
        Assert.Equal("1756123456789", r.TrackingCode);
        Assert.Equal(38500m, r.Fee);
        var call = http.Single("/v2/order/createOrderNlp");
        Assert.Equal(VtpJwt, call.Header("Token"));
        var b = call.Json;
        Assert.Equal(expected, b.GetProperty("ORDER_PAYMENT").GetInt32());
        Assert.Equal(cod, b.GetProperty("MONEY_COLLECTION").GetInt32());
        Assert.Equal(1200, b.GetProperty("PRODUCT_WEIGHT").GetInt32()); // gram
        Assert.Equal("VCN", b.GetProperty("ORDER_SERVICE").GetString());
        Assert.Contains("Phường Hải Châu", b.GetProperty("RECEIVER_ADDRESS").GetString());
        Assert.Contains("Thành phố Đà Nẵng", b.GetProperty("RECEIVER_ADDRESS").GetString());
    }

    [Theory]
    [InlineData(false, "https://digitalize.viettelpost.vn/DigitalizePrint/report.do?type=1&bill=")]
    [InlineData(true, "https://dev-release-print.viettelpost.vn/DigitalizePrint/report.do?type=1&bill=")]
    public async Task Vtp_in_nhan_goi_printing_code_theo_docs(bool sandbox, string urlPrefix)
    {
        var http = VtpCreateHttp();
        var client = new ViettelPostShippingClient(new FakeFactory(http), NullLogger<ViettelPostShippingClient>.Instance);

        var r = await client.GetPrintLabelAsync(VtpSettings(sandbox), "1756123456789");

        Assert.True(r.Success, r.Message);
        Assert.StartsWith(urlPrefix, r.LabelUrl);
        Assert.Equal("ISJDgZ3NSiYMtPUk7vTzQK8ZWUDexvvDKIclc0NplOU=", r.PrintCode);
        var call = http.Single("/v2/order/printing-code");
        Assert.Equal("1756123456789", call.Json.GetProperty("ORDER_ARRAY")[0].GetString());
        Assert.True(call.Json.GetProperty("EXPIRY_TIME").GetInt64() > DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
        Assert.Single(http.Requests); // không cần thử path cũ
    }

    [Fact]
    public async Task Vtp_bang_gia_getPriceAllNlp_va_loi_tuyen()
    {
        var http = new FakeHttp().On("POST", "/v2/order/getPriceAllNlp",
            """{"SENDER_ADDRESS":{"PROVINCE_ID":32,"ADDRESS":"12 Bạch Đằng"},"RECEIVER_ADDRESS":{"PROVINCE_ID":32},"RESULT":[{"MA_DV_CHINH":"VCN","TEN_DICHVU":"Chuyển phát nhanh","GIA_CUOC":36000,"THOI_GIAN":"24 giờ","EXCHANGE_WEIGHT":1200},{"MA_DV_CHINH":"LCOD","TEN_DICHVU":"TMĐT tiết kiệm","GIA_CUOC":22000,"THOI_GIAN":"48 giờ"}]}""");
        var client = new ViettelPostShippingClient(new FakeFactory(http), NullLogger<ViettelPostShippingClient>.Instance);

        var list = await client.QuoteOptionsAsync(VtpSettings(), DaNangQuote("ViettelPost"));

        Assert.Equal(2, list.Count);
        Assert.Equal("LCOD", list[0].ServiceCode);
        Assert.Equal(22000m, list[0].Fee);
        Assert.Equal(48 * 60, list[0].EtaMinutes);
        var b = http.Single("/v2/order/getPriceAllNlp").Json;
        Assert.Equal(1, b.GetProperty("TYPE").GetInt32());
        Assert.Equal(1200, b.GetProperty("PRODUCT_WEIGHT").GetInt32());
        Assert.Equal(350_000, b.GetProperty("MONEY_COLLECTION").GetInt32());

        var bad = new FakeHttp().On("POST", "/v2/order/getPriceAllNlp",
            """{"status":204,"error":true,"message":"Price does not apply to this itinerary!","data":null}""");
        var c2 = new ViettelPostShippingClient(new FakeFactory(bad), NullLogger<ViettelPostShippingClient>.Instance);
        var err = Assert.Single(await c2.QuoteOptionsAsync(VtpSettings(), DaNangQuote("ViettelPost")));
        Assert.False(err.Success);
        Assert.Contains("itinerary", err.Message);
    }

    [Fact]
    public async Task Vtp_huy_don_UpdateOrder_TYPE_4()
    {
        var http = new FakeHttp().On("POST", "/v2/order/UpdateOrder",
            """{"status":200,"error":false,"message":"Huỷ đơn hàng thành công","data":null}""");
        var client = new ViettelPostShippingClient(new FakeFactory(http), NullLogger<ViettelPostShippingClient>.Instance);

        var r = await client.UpdateOrderStatusAsync(VtpSettings(), "1756123456789", 4, "Khách đổi ý");

        Assert.True(r.Success, r.Message);
        var b = http.Single("/v2/order/UpdateOrder").Json;
        Assert.Equal(4, b.GetProperty("TYPE").GetInt32());
        Assert.Equal("1756123456789", b.GetProperty("ORDER_NUMBER").GetString());
        Assert.Equal("Khách đổi ý", b.GetProperty("NOTE").GetString());
    }

    [Theory]
    [InlineData(100, ShipmentStatus.Created)]
    [InlineData(104, ShipmentStatus.Picking)]      // «Giao cho bưu tá đi nhận» (mẫu webhook docs)
    [InlineData(105, ShipmentStatus.InTransit)]
    [InlineData(200, ShipmentStatus.InTransit)]
    [InlineData(500, ShipmentStatus.Delivering)]
    [InlineData(501, ShipmentStatus.Delivered)]
    [InlineData(504, ShipmentStatus.Returned)]
    [InlineData(506, ShipmentStatus.DeliveryFailed)]
    [InlineData(101, ShipmentStatus.Cancelled)]
    [InlineData(107, ShipmentStatus.Cancelled)]
    [InlineData(201, ShipmentStatus.Cancelled)]
    [InlineData(503, ShipmentStatus.Cancelled)]
    public void Vtp_order_status_quy_doi(int code, string expected) =>
        Assert.Equal(expected, ShipmentStatus.FromViettelPost(code));

    [Fact]
    public void Vtp_webhook_xac_thuc_bang_TOKEN_trong_body()
    {
        const string secret = "5f2c0d8e9a1b4c7d8e9f0a1b2c3d4e5f";
        Assert.True(ViettelPostExtraJson.MatchesWebhookAuth(secret, null, secret));
        Assert.False(ViettelPostExtraJson.MatchesWebhookAuth(secret, null, "sai-ma"));
    }

    // ══ SPX Express — spx.vn/integration (SPX Open Service) ═══════════

    const string SpxAppId = "100000";
    const string SpxAppSecret = "H25HY53GO4BA2GQ";

    static PosShippingCarrierSetting SpxSettings(string? extra = null) => new()
    {
        CarrierCode = ShippingCarrierCodes.Spx,
        UseSandbox = true,
        ShopId = "239404781503925",
        ApiToken = "85f0d570-a265-4d9d-857e-b30aa57c4fbe",
        ExtraJson = extra ?? $$"""{"appId":"{{SpxAppId}}","appSecret":"{{SpxAppSecret}}"}""",
        PickupName = "SBOX Quận 1",
        PickupPhone = "0901234567",
        PickupAddress = "15 Lê Lợi",
        FromProvinceName = "TP. Hồ Chí Minh",
        FromDistrictName = "Quận 1",
        FromWardName = "Phường Bến Nghé",
    };

    static void AssertSpxSigned(Captured call)
    {
        Assert.Equal(SpxAppId, call.Header("app-id"));
        var ts = long.Parse(call.Header("timestamp")!);
        var rnd = long.Parse(call.Header("random-num")!);
        Assert.InRange(ts, DateTimeOffset.UtcNow.ToUnixTimeSeconds() - 60, DateTimeOffset.UtcNow.ToUnixTimeSeconds() + 5);
        Assert.Equal(SpxShippingClient.ComputeCheckSign(SpxAppId, SpxAppSecret, ts, rnd, call.Body!), call.Header("check-sign"));
        var b = call.Json;
        Assert.Equal(JsonValueKind.Number, b.GetProperty("user_id").ValueKind);
        Assert.Equal(239404781503925L, b.GetProperty("user_id").GetInt64());
        Assert.Equal("85f0d570-a265-4d9d-857e-b30aa57c4fbe", b.GetProperty("user_secret").GetString());
    }

    [Theory]
    // Hai bộ test vector chính thức trong «API authentication guide» SPX.
    [InlineData("100000", "H25HY53GO4BA2GQ", 1677918414L, 926611981L,
        """{"user_id":239404781503925,"user_secret":"85f0d570-a265-4d9d-857e-b30aa57c4fbe","service_type":1}""",
        "97e21b23940e4ddc96fb4d2474f02425353d2b0e23aee384f3f94c3d0b9ba17d")]
    [InlineData("100192", "106122402719a5800d92e8fc7eab16ac153fc9401299d69a37207914b3959997", 1699422945L, 564047L,
        """{"phone":"0826368193"}""",
        "7067c7ee76f82ee23c752339a2415ce2b7eb6c21c247ade1abe02273b5c26827")]
    public void Spx_check_sign_khop_test_vector_docs(string appId, string secret, long ts, long rnd, string payload, string expected) =>
        Assert.Equal(expected, SpxShippingClient.ComputeCheckSign(appId, secret, ts, rnd, payload));

    [Fact]
    public async Task Spx_bao_gia_batch_check_order_ky_header_va_kg()
    {
        var http = new FakeHttp().On("POST", "/open/api/v1/order/batch_check_order",
            """{"ret_code":0,"message":"success. ","data":{"orders":[{"order_id":"","estimated_shipping_fee":23200,"basic_shipping_fee":23200,"cod_service_fee":0,"high_value_processing_fee":0,"vat_fee":0}],"fail_list":[]}}""");
        var client = new SpxShippingClient(new FakeFactory(http), NullLogger<SpxShippingClient>.Instance);

        var r = await client.QuoteAsync(SpxSettings(), DaNangQuote("Spx"));

        Assert.True(r.Success, r.Message);
        Assert.Equal(23200m, r.Fee);
        var call = http.Single("/open/api/v1/order/batch_check_order");
        Assert.Equal("test-stable.spx.vn", call.Uri.Host);
        AssertSpxSigned(call);
        var o = call.Json.GetProperty("orders")[0];
        Assert.Equal(1, o.GetProperty("base_info").GetProperty("service_type").GetInt32());
        Assert.Equal(1.2, o.GetProperty("parcel_info").GetProperty("parcel_weight").GetDouble(), 3); // kg
        var d = o.GetProperty("deliver_info");
        Assert.Equal("Thành phố Đà Nẵng", d.GetProperty("deliver_state").GetString());
        Assert.Equal("Phường Hải Châu", d.GetProperty("deliver_city").GetString());   // 2 cấp: city = phường
        Assert.Equal(2, d.GetProperty("deliver_address_version").GetInt32());
        Assert.False(d.TryGetProperty("deliver_district", out _));
        var s = o.GetProperty("sender_info");
        Assert.Equal("Quận 1", s.GetProperty("sender_city").GetString());              // 3 cấp: city = quận
        Assert.Equal("Phường Bến Nghé", s.GetProperty("sender_district").GetString());
        Assert.Equal(0, s.GetProperty("sender_address_version").GetInt32());
        var f = o.GetProperty("fulfillment_info");
        Assert.Equal(1, f.GetProperty("cod_collection").GetInt32());
        Assert.Equal(350_000, f.GetProperty("cod_amount").GetInt64());
        Assert.False(o.TryGetProperty("order_id", out _)); // không gửi khóa null
    }

    [Theory]
    [InlineData("""{"ret_code":0,"message":"success.","data":{"orders":[],"fail_list":[{"ret_code":10018,"message":"Address not supported","debug_msg":"x","order_id":""}]}}""", "Address not supported (SPX 10018)")]
    [InlineData("""{"ret_code":1007,"message":"check-sign verification failed"}""", "check-sign verification failed (SPX 1007)")]
    public async Task Spx_loi_lo_va_loi_ky_tra_ve_message(string json, string expected)
    {
        var http = new FakeHttp().On("POST", "/open/api/v1/order/batch_check_order", json);
        var client = new SpxShippingClient(new FakeFactory(http), NullLogger<SpxShippingClient>.Instance);

        var r = await client.QuoteAsync(SpxSettings(), DaNangQuote("Spx"));

        Assert.False(r.Success);
        Assert.Equal(expected, r.Message);
    }

    [Fact]
    public async Task Spx_thieu_app_id_khong_goi_api()
    {
        var http = new FakeHttp();
        var client = new SpxShippingClient(new FakeFactory(http), NullLogger<SpxShippingClient>.Instance);

        var r = await client.QuoteAsync(SpxSettings(extra: "{}"), DaNangQuote("Spx"));

        Assert.False(r.Success);
        Assert.Contains("app-id", r.Message);
        Assert.Empty(http.Requests);
    }

    [Fact]
    public async Task Spx_tao_don_lay_khung_gio_roi_batch_create_order()
    {
        var http = new FakeHttp()
            .On("POST", "/open/api/v1/order/get_pickup_time",
                """{"ret_code":0,"message":"success. ","data":[{"date":"26-10-2026","pickup_time":1792962000,"slots":[{"pickup_time_range_id":1,"pickup_time_range":"10h đến trước 19h"}]}]}""")
            .On("POST", "/open/api/v1/order/batch_create_order",
                """{"ret_code":0,"message":"success. ","data":{"orders":[{"order_id":"HD000123","tracking_no":"SPXVN218816334070","tracking_link":"https://spx.vn/track?SPXVN218816334070","estimated_shipping_fee":25000,"basic_shipping_fee":25000}],"fail_list":[]}}""");
        var client = new SpxShippingClient(new FakeFactory(http), NullLogger<SpxShippingClient>.Instance);
        var order = DaNangOrder(district: "Quận Hải Châu", ward: "Phường Thạch Thang");

        var r = await client.CreateAsync(SpxSettings(), order, new ShippingCreateRequest(
            "Spx", order.Id, CodAmount: 450_000, WeightGrams: 800, ShipFeePayer: "customer"));

        Assert.True(r.Success, r.Message);
        Assert.Equal("SPXVN218816334070", r.TrackingCode);
        Assert.Equal(25000m, r.Fee);
        Assert.Equal("https://spx.vn/track?SPXVN218816334070", r.LabelUrl);
        AssertSpxSigned(http.Single("/order/get_pickup_time"));
        Assert.Equal(1, http.Single("/order/get_pickup_time").Json.GetProperty("service_type").GetInt32());
        var call = http.Single("/order/batch_create_order");
        AssertSpxSigned(call);
        var o = call.Json.GetProperty("orders")[0];
        Assert.Equal("HD000123", o.GetProperty("order_id").GetString());
        var f = o.GetProperty("fulfillment_info");
        Assert.Equal(2, f.GetProperty("payment_role").GetInt32());     // người nhận trả cước
        Assert.Equal(1, f.GetProperty("collect_type").GetInt32());
        Assert.Equal(1792962000, f.GetProperty("pickup_time").GetInt64());
        Assert.Equal(1, f.GetProperty("pickup_time_range_id").GetInt64());
        Assert.Equal(450_000, f.GetProperty("cod_amount").GetInt64());
        Assert.Equal(0, f.GetProperty("high_value_processing_collection").GetInt32()); // < 3tr
        var d = o.GetProperty("deliver_info");
        Assert.Equal("Quận Hải Châu", d.GetProperty("deliver_city").GetString());
        Assert.Equal("Phường Thạch Thang", d.GetProperty("deliver_district").GetString());
        Assert.Equal("Nguyễn Văn An", d.GetProperty("deliver_name").GetString());
        Assert.Equal("0912345678", d.GetProperty("deliver_phone").GetString());
        var p = o.GetProperty("parcel_info");
        Assert.Equal(0.8, p.GetProperty("parcel_weight").GetDouble(), 3);
        Assert.Contains("Áo thun cotton", p.GetProperty("parcel_item_name").GetString());
        Assert.Equal(450_000, p.GetProperty("express_insured_value").GetInt64());
    }

    [Fact]
    public async Task Spx_huy_don_doc_tracking_no_list_va_fail_list()
    {
        var fail = new FakeHttp().On("POST", "/open/api/v1/order/batch_cancel_order",
            """{"ret_code":0,"message":"success.","data":{"tracking_no_list":[],"fail_list":[{"ret_code":13002,"message":"Order can not be cancelled","tracking_no":"SPXVN218816334070"}]}}""");
        var c1 = new SpxShippingClient(new FakeFactory(fail), NullLogger<SpxShippingClient>.Instance);
        var r1 = await c1.CancelOrderAsync(SpxSettings(), "SPXVN218816334070", "Khách hủy");
        Assert.False(r1.Success);
        Assert.Contains("13002", r1.Message);
        var call = fail.Single("/order/batch_cancel_order");
        AssertSpxSigned(call);
        Assert.Equal("SPXVN218816334070", call.Json.GetProperty("tracking_no_list")[0].GetString());

        var ok = new FakeHttp().On("POST", "/open/api/v1/order/batch_cancel_order",
            """{"ret_code":0,"message":"success.","data":{"tracking_no_list":["SPXVN218816334070"],"fail_list":[]}}""");
        var c2 = new SpxShippingClient(new FakeFactory(ok), NullLogger<SpxShippingClient>.Instance);
        Assert.True((await c2.CancelOrderAsync(SpxSettings(), "SPXVN218816334070", null)).Success);
    }

    [Fact]
    public async Task Spx_nhan_awb_link_va_hanh_trinh_batch_search_order()
    {
        var http = new FakeHttp()
            .On("POST", "/open/api/v1/order/batch_get_shipping_label",
                """{"ret_code":0,"message":"success.","data":{"awb_link":"https://test-stable.spx.vn/shipment/order/open/order/batch_get_shipping_label?order_sn_list=VN1&access_token=abc","fail_list":[]}}""")
            .On("POST", "/open/api/v1/order/batch_search_order",
                """{"ret_code":0,"message":"success. ","data":{"orders":[{"tracking_no":"SPXVN218816334070","order_id":"HD000123","status":"Delivered","status_code":"4001","routes":[{"status":"Pending Pickup","status_code":"1001","message":"Người gửi đang chuẩn bị hàng","timestamp":1792900000},{"status":"Delivered","status_code":"4001","message":"Giao hàng thành công","timestamp":1793000000}]}],"fail_list":[]}}""");
        var client = new SpxShippingClient(new FakeFactory(http), NullLogger<SpxShippingClient>.Instance);

        var label = await client.GetPrintLabelAsync(SpxSettings(), "SPXVN218816334070");
        Assert.True(label.Success);
        Assert.Contains("batch_get_shipping_label", label.LabelUrl);

        var t = await client.GetTrackingAsync(SpxSettings(), "SPXVN218816334070");
        Assert.True(t.Success, t.Message);
        Assert.Equal(4001, t.StatusCode);
        Assert.Equal("Delivered", t.StatusName);
        Assert.Equal("Đã giao hàng", t.Message);
        Assert.Equal(2, t.Events!.Count);
        Assert.Equal(1001, t.Events[0].StatusCode);
        Assert.Equal(ShipmentStatus.Delivered, ShipmentStatus.FromSpx(t.StatusCode!.Value.ToString()));
        Assert.Equal(ShipmentStatus.Delivered, ShipmentStatus.FromSpx(t.StatusName));
    }

    [Theory]
    // Bảng «Order status code» SPX + chữ «status» tương ứng.
    [InlineData("1001", ShipmentStatus.Created)]
    [InlineData("Pending Pickup", ShipmentStatus.Created)]
    [InlineData("2001", ShipmentStatus.InTransit)]
    [InlineData("In Transit", ShipmentStatus.InTransit)]
    [InlineData("2006", ShipmentStatus.Delivering)]
    [InlineData("4001", ShipmentStatus.Delivered)]
    [InlineData("5001", ShipmentStatus.Picking)]
    [InlineData("Pickup Failed", ShipmentStatus.Picking)]
    [InlineData("5002", ShipmentStatus.Issue)]
    [InlineData("5003", ShipmentStatus.Issue)]
    [InlineData("6001", ShipmentStatus.Returning)]
    [InlineData("6002", ShipmentStatus.Returning)]
    [InlineData("Return Failed", ShipmentStatus.Returning)]
    [InlineData("6003", ShipmentStatus.Returned)]
    [InlineData("7001", ShipmentStatus.Cancelled)]
    [InlineData("3001", null)]
    [InlineData("On Hold", null)]
    public void Spx_status_code_quy_doi(string raw, string? expected) =>
        Assert.Equal(expected, ShipmentStatus.FromSpx(raw));

    const string SpxWebhookBody =
        """{"status":"Pending Pickup","status_code":"1001","message":"xxx","tracking_no":"SPXVN218816334070","tracking_link":"https://spx.vn/track?SPXVN218816334070","order_id":"HD000123","timestamp":1792900000,"id":"d4dcfea1-5286-4921-8fd3-7ded133f8579"}""";

    [Fact]
    public void Spx_webhook_check_sign_bang_app_secret()
    {
        var s = SpxSettings();
        var sign = SpxShippingClient.ComputeCheckSign(SpxAppId, SpxAppSecret, 1792900001, 12345, SpxWebhookBody);
        Assert.True(SpxShippingClient.VerifyWebhookSign(s, SpxWebhookBody, sign, "1792900001", "12345"));
        Assert.True(SpxShippingClient.VerifyWebhookSign(s, SpxWebhookBody, sign.ToUpperInvariant(), "1792900001", "12345"));
        Assert.False(SpxShippingClient.VerifyWebhookSign(s, SpxWebhookBody.Replace("1001", "4001"), sign, "1792900001", "12345"));
        Assert.False(SpxShippingClient.VerifyWebhookSign(s, SpxWebhookBody, sign, null, "12345"));
        Assert.False(SpxShippingClient.VerifyWebhookSign(SpxSettings(extra: "{}"), SpxWebhookBody, sign, "1792900001", "12345"));
    }

    static ZKTecoDbContext NewDb() =>
        new(new DbContextOptionsBuilder<ZKTecoDbContext>().UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);

    [Fact]
    public async Task Spx_webhook_chap_nhan_check_sign_cua_dung_cua_hang()
    {
        await using var db = NewDb();
        var store = Guid.NewGuid();
        var settings = SpxSettings();
        settings.StoreId = store;
        db.PosShippingCarrierSettings.Add(settings);
        db.PosSaleOrders.Add(new PosSaleOrder
        {
            Id = Guid.NewGuid(), StoreId = store, OrderNo = "HD000123", IsDelivery = true,
            DeliveryCarrierCode = ShippingCarrierCodes.Spx, DeliveryTrackingCode = "SPXVN218816334070",
        });
        await db.SaveChangesAsync();
        var svc = new PosShippingService(db, [], NullLogger<PosShippingService>.Instance);
        var sign = SpxShippingClient.ComputeCheckSign(SpxAppId, SpxAppSecret, 1792900001, 12345, SpxWebhookBody);

        Assert.True(await svc.ValidateSpxWebhookAsync(null, "SPXVN218816334070", SpxWebhookBody,
            sign, "1792900001", "12345", default));
        Assert.False(await svc.ValidateSpxWebhookAsync(null, "SPXVN218816334070", SpxWebhookBody,
            "deadbeef", "1792900001", "12345", default));
        Assert.False(await svc.ValidateSpxWebhookAsync(null, "SPXVN218816334070", SpxWebhookBody,
            null, null, null, default));
    }

    // ══ AhaMove — developers.ahamove.com (v3) ═════════════════════════

    // JWT giả, exp = 2100-01-01 → không cần gọi /v3/accounts/token.
    const string AhaJwt = "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjQxMDI0NDQ4MDB9.c2ln";

    static PosShippingCarrierSetting AhaSettings(string extra) => new()
    {
        CarrierCode = ShippingCarrierCodes.Ahamove,
        ApiToken = "aha-test-api-key",
        ShopId = "0905123456",
        Password = AhaJwt,
        PickupName = "SBOX Hải Châu",
        PickupPhone = "0905123456",
        PickupAddress = "12 Bạch Đằng",
        FromProvinceName = "Thành phố Đà Nẵng",
        FromWardName = "Phường Hải Châu",
        ExtraJson = extra,
    };

    const string AhaCoords = "\"lat\":16.0678,\"lng\":108.2208,\"to_lat\":16.0544,\"to_lng\":108.2022";

    [Fact]
    public async Task Ahamove_estimates_group_services_va_path()
    {
        var http = new FakeHttp().On("POST", "/v3/orders/estimates",
            """[{"service_id":"DAD-BIKE","data":{"distance":3.2,"duration":1500,"distance_fee":23000,"request_fee":0,"stop_fee":0,"vat_fee":0,"discount":0,"total_fee":33000,"requests":[],"total_price":33000}}]""");
        var client = new AhamoveShippingClient(new FakeFactory(http), NullLogger<AhamoveShippingClient>.Instance);

        var r = await client.QuoteAsync(AhaSettings("{" + AhaCoords + ",\"group_service_id\":\"BIKE\"}"), DaNangQuote("Ahamove"));

        Assert.True(r.Success, r.Message);
        Assert.Equal(33000m, r.Fee);
        Assert.Equal("DAD-BIKE", r.ServiceCode);
        Assert.Equal(25, r.EtaMinutes);
        var call = http.Single("/v3/orders/estimates");
        Assert.Equal("partner-api.ahamove.com", call.Uri.Host);
        Assert.Equal($"Bearer {AhaJwt}", call.Header("Authorization"));
        var b = call.Json;
        Assert.Equal("BIKE", b.GetProperty("group_services")[0].GetProperty("_id").GetString());
        Assert.Equal(JsonValueKind.Array, b.GetProperty("group_services")[0].GetProperty("group_requests").ValueKind);
        Assert.Equal("BALANCE", b.GetProperty("payment_method").GetString());
        var path = b.GetProperty("path");
        Assert.Equal(2, path.GetArrayLength());
        Assert.Equal(16.0678, path[0].GetProperty("lat").GetDouble(), 4);
        Assert.Equal("84905123456", path[0].GetProperty("mobile").GetString());
        Assert.Equal(350_000, path[1].GetProperty("cod").GetInt32());
        Assert.Equal("84912345678", path[1].GetProperty("mobile").GetString());
        Assert.Contains("Phường Hải Châu", path[1].GetProperty("address").GetString());
    }

    [Fact]
    public async Task Ahamove_tao_don_service_id_requests_va_nguoi_nhan_tra()
    {
        var http = new FakeHttp().On("POST", "/v3/orders",
            """{"order_id":"24ABCD","status":"ASSIGNING","shared_link":"https://cloudjetstg.ahamove.com/share-order/24ABCD","order":{"_id":"24ABCD","currency":"VND","total_pay":33000,"total_fee":33000,"total_price":33000,"service_id":"DAD-BIKE","status":"ASSIGNING"}}""");
        var client = new AhamoveShippingClient(new FakeFactory(http), NullLogger<AhamoveShippingClient>.Instance);
        var order = DaNangOrder();

        var r = await client.CreateAsync(AhaSettings("{" + AhaCoords + ",\"service_id\":\"DAD-BIKE\"}"), order,
            new ShippingCreateRequest("Ahamove", order.Id, CodAmount: 450_000, ShipFeePayer: "customer"));

        Assert.True(r.Success, r.Message);
        Assert.Equal("24ABCD", r.TrackingCode);
        Assert.Equal(33000m, r.Fee);
        Assert.Contains("share-order/24ABCD", r.LabelUrl);
        var b = http.Single("/v3/orders").Json;
        Assert.Equal("DAD-BIKE", b.GetProperty("service_id").GetString());
        Assert.Equal(JsonValueKind.Array, b.GetProperty("requests").ValueKind);
        Assert.Equal("CASH_BY_RECIPIENT", b.GetProperty("payment_method").GetString());
        Assert.Equal(0, b.GetProperty("order_time").GetInt32());
        Assert.Equal("HD000123", b.GetProperty("path")[1].GetProperty("tracking_number").GetString());
        Assert.Equal(450_000, b.GetProperty("path")[1].GetProperty("cod").GetInt32());
        Assert.Equal(2, b.GetProperty("items").GetArrayLength());
    }

    [Fact]
    public async Task Ahamove_huy_DELETE_comment_va_loi_INVALID_ORDER_STATUS()
    {
        var ok = new FakeHttp().On("DELETE", "/v3/orders/24ABCD", "{}");
        var c1 = new AhamoveShippingClient(new FakeFactory(ok), NullLogger<AhamoveShippingClient>.Instance);
        Assert.True((await c1.CancelOrderAsync(AhaSettings("{}"), "24ABCD", "Khách hủy")).Success);
        Assert.Equal("Khách hủy", ok.Single("/v3/orders/24ABCD").Json.GetProperty("comment").GetString());

        var bad = new FakeHttp().On("DELETE", "/v3/orders/24ABCD",
            """{"title":"INVALID_ORDER_STATUS","description":"Order status is not cancellable"}""", HttpStatusCode.NotAcceptable);
        var c2 = new AhamoveShippingClient(new FakeFactory(bad), NullLogger<AhamoveShippingClient>.Instance);
        var r = await c2.CancelOrderAsync(AhaSettings("{}"), "24ABCD", null);
        Assert.False(r.Success);
        Assert.Equal("Order status is not cancellable", r.Message);
    }

    [Fact]
    public async Task Ahamove_401_lay_lai_token_roi_goi_lai()
    {
        const string fresh = "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjQxMDI0NDQ4MDAsInR5cCI6Im5ldyJ9.c2ln";
        var http = new FakeHttp()
            .On("GET", "/v3/orders/24ABCD", """{"title":"NOT_AUTHORIZED"}""", HttpStatusCode.Unauthorized, once: true)
            .On("POST", "/v3/accounts/token", $$"""{"token":"{{fresh}}","refresh_token":"r1"}""")
            .On("GET", "/v3/orders/24ABCD", """{"_id":"24ABCD","status":"IN PROCESS","path":[{},{}]}""");
        var client = new AhamoveShippingClient(new FakeFactory(http), NullLogger<AhamoveShippingClient>.Instance);
        var s = AhaSettings("{}");

        var t = await client.GetTrackingAsync(s, "24ABCD");

        Assert.True(t.Success, t.Message);
        Assert.Equal(fresh, s.Password);
        var tok = http.Single("/v3/accounts/token").Json;
        Assert.Equal("aha-test-api-key", tok.GetProperty("api_key").GetString());
        Assert.Equal("84905123456", tok.GetProperty("mobile").GetString());
        Assert.Equal($"Bearer {fresh}", http.Requests.Last().Header("Authorization"));
        Assert.Equal(ShipmentStatus.Delivering, ShipmentStatus.FromAhamove("IN PROCESS"));
    }

    // ══ Webhook controller: xác thực header theo docs từng hãng ══════

    const string StoreSecret = "5f2c0d8e9a1b4c7d8e9f0a1b2c3d4e5f";

    static async Task<(ZKTecoDbContext Db, ShippingWebhookController Ctl)> WebhookSetupAsync(
        string carrier, string tracking)
    {
        var db = NewDb();
        var store = Guid.NewGuid();
        db.PosShippingCarrierSettings.Add(new PosShippingCarrierSetting
        {
            StoreId = store, CarrierCode = carrier, Enabled = true,
            ExtraJson = $$"""{"webhookSecret":"{{StoreSecret}}"}""",
        });
        db.PosSaleOrders.Add(new PosSaleOrder
        {
            Id = Guid.NewGuid(), StoreId = store, OrderNo = "HD000123", IsDelivery = true,
            DeliveryCarrierCode = carrier, DeliveryTrackingCode = tracking, DeliveryCarrierOrderId = tracking,
        });
        await db.SaveChangesAsync();
        var svc = new PosShippingService(db, [], NullLogger<PosShippingService>.Instance);
        var ctl = new ShippingWebhookController(svc, NullLogger<ShippingWebhookController>.Instance)
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };
        return (db, ctl);
    }

    static void SetBody(ControllerBase ctl, string json, params (string Key, string Value)[] headers)
    {
        var req = ctl.HttpContext.Request;
        req.ContentType = "application/json";
        req.Body = new MemoryStream(Encoding.UTF8.GetBytes(json));
        foreach (var (k, v) in headers) req.Headers[k] = v;
    }

    [Fact]
    public async Task Ahamove_webhook_nhan_header_apikey()
    {
        const string body = """{"_id":"24ABCD","status":"ACCEPTED","sub_status":"BOARDED","path":[{},{}]}""";

        var (db1, noAuth) = await WebhookSetupAsync(ShippingCarrierCodes.Ahamove, "24ABCD");
        await using (db1)
        {
            SetBody(noAuth, body);
            Assert.IsType<UnauthorizedObjectResult>(await noAuth.Generic("Ahamove", default));
        }

        var (db2, withKey) = await WebhookSetupAsync(ShippingCarrierCodes.Ahamove, "24ABCD");
        await using (db2)
        {
            SetBody(withKey, body, ("apikey", StoreSecret));
            Assert.IsNotType<UnauthorizedObjectResult>(await withKey.Generic("Ahamove", default));
        }
    }

    [Fact]
    public async Task Ghn_webhook_nhan_header_tuy_chinh_Authorization()
    {
        const string body = """{"CODAmount":450000,"ClientOrderCode":"HD000123","OrderCode":"LDFKQ8","ShopID":885,"Status":"picking","Type":"switch_status","Time":"2026-10-26T03:00:00Z","Description":"Đang lấy hàng","Reason":"","ReasonCode":"","Weight":800}""";

        var (db1, wrong) = await WebhookSetupAsync(ShippingCarrierCodes.Ghn, "LDFKQ8");
        await using (db1)
        {
            SetBody(wrong, body, ("Authorization", "Bearer sai-ma"));
            Assert.IsType<UnauthorizedObjectResult>(await wrong.Ghn(default));
        }

        var (db2, right) = await WebhookSetupAsync(ShippingCarrierCodes.Ghn, "LDFKQ8");
        await using (db2)
        {
            SetBody(right, body, ("Authorization", $"Bearer {StoreSecret}"));
            Assert.IsNotType<UnauthorizedObjectResult>(await right.Ghn(default));
        }
    }
}
