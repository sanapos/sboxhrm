using System.Globalization;
using System.Text;

namespace ZKTecoADMS.Api.Seo;

/// <summary>
/// Trang sản phẩm máy chấm công: /lap-dat-may-cham-cong/san-pham/{slug} (sboxhrm.com).
/// Dữ liệu lấy từ «Sản phẩm thiết bị» (landing_products) — thêm máy ở Thiết lập › Landing là có thêm trang.
/// Trước đây thẻ sản phẩm trên trang chủ trỏ sang website khác; nay mọi liên kết và ảnh nằm trên chính SBOX.
/// </summary>
public static partial class SeoPages
{
    const string DeviceBase = LocalBase + "/san-pham";

    /// <summary>Slug trang sản phẩm: «ZKTeco SenseFace 2A» → zkteco-senseface-2a (khớp hàm deviceSlug trong home.html).</summary>
    public static string DeviceSlug(string name) => SeoMarkdown.Slugify(name);

    public static string DeviceUrl(SiteInfo s, DeviceOffer d) => $"{s.Origin}{DeviceBase}/{DeviceSlug(d.Name)}";

    static bool IsFaceDevice(DeviceOffer d) =>
        $"{d.Name} {d.Sub} {d.Specs}".Contains("khuôn mặt", StringComparison.OrdinalIgnoreCase)
        || $"{d.Name} {d.Sub}".Contains("face", StringComparison.OrdinalIgnoreCase);

    static bool HasAdms(DeviceOffer d) =>
        $"{d.Name} {d.Sub} {d.Specs}".Contains("ADMS", StringComparison.OrdinalIgnoreCase);

    static bool HasWifi(DeviceOffer d) =>
        $"{d.Name} {d.Sub} {d.Specs}".Contains("wifi", StringComparison.OrdinalIgnoreCase);

    /// <summary>Ảnh minh họa của SBOX (flutter_client/web/images/devices) — thay bằng ảnh chụp thật khi có.</summary>
    public static string DeviceImage(DeviceOffer d) =>
        IsFaceDevice(d) ? "/images/devices/device-face.svg" : "/images/devices/device-fingerprint.svg";

    /// <summary>
    /// Thông số do hãng công bố, chỉ ghi các số đã đối chiếu tài liệu chính hãng (zkteco.com). Máy chưa có nguồn chính hãng
    /// thì không ghi thông số — trang chỉ hiện các dòng người quản trị nhập và báo cấu hình cụ thể khi báo giá.
    /// </summary>
    static readonly Dictionary<string, (string Source, (string Name, string Value)[] Rows)> OfficialSpecs = new()
    {
        ["zkteco-senseface-2a"] = ("zkteco.com/en/SenseFaceSeries/SenseFace_2A",
        [
            ("Màn hình", "2,4 inch TFT màu, độ phân giải 320 × 240"),
            ("Dung lượng khuôn mặt", "1.500 (bản Entry) hoặc 3.000 (bản Standard)"),
            ("Dung lượng vân tay", "1.500 (bản Entry) hoặc 3.000 (bản Standard)"),
            ("Thẻ và người dùng", "3.000"),
            ("Bản ghi chấm công", "150.000"),
            ("Tốc độ xác thực", "Vân tay dưới 0,5 giây · Khuôn mặt dưới 0,35 giây"),
            ("Bộ xử lý", "Lõi kép 1 GHz, RAM 512 MB"),
        ]),
        ["zkteco-mb10vl"] = ("zkteco.com/en/Standalone_Device/MB10-VL",
        [
            ("Dung lượng khuôn mặt", "100 (tùy chọn nâng lên 800)"),
            ("Dung lượng vân tay", "500 (tùy chọn nâng lên 800)"),
            ("Dung lượng thẻ", "500 (tùy chọn nâng lên 800)"),
            ("Bản ghi chấm công", "50.000 (tùy chọn nâng lên 150.000)"),
            ("Kết nối", "TCP/IP, USB Host, WiFi (tùy chọn)"),
            ("Chức năng chuẩn", "ADMS, chuyển trạng thái tự động, hỗ trợ camera chụp ảnh"),
            ("Khoảng cách nhận diện", "Khoảng 30 – 50 cm, tốc độ dưới 1 giây"),
        ]),
    };

    static List<FaqItem> DeviceFaq(DeviceOffer d, string kind)
    {
        var internet = HasAdms(d) || HasWifi(d)
            ? $"Máy {d.Name} hỗ trợ kết nối Internet ({(HasAdms(d) ? "ADMS" : "WiFi")}) nên gửi dữ liệu chấm công lên SBOX HRM sau vài giây; chủ doanh nghiệp xem công trên điện thoại hoặc trình duyệt web mà không cần máy tính bật tại văn phòng."
            : $"Cấu hình kết nối của {d.Name} (mạng LAN, WiFi hoặc ADMS) tùy phiên bản. Kỹ thuật SBOX khảo sát và chọn cách kết nối phù hợp hạ tầng mạng của bạn khi lắp đặt; hãy hỏi trước khi mua nếu cần xem công từ xa.";
        return
        [
            new($"Máy {d.Name} có xem được công trên điện thoại không", internet),
            new($"Mua máy {d.Name} có được lắp đặt miễn phí không",
                "Khi mua máy chấm công tại SBOX bạn được miễn phí lắp đặt tận nơi, cài đặt kết nối và tặng phần mềm chấm công SBOX HRM. Phí và phạm vi áp dụng theo từng khu vực, SBOX báo rõ khi báo giá."),
            new($"Máy {d.Name} phù hợp với doanh nghiệp nào",
                kind == "face"
                    ? "Máy nhận diện khuôn mặt không chạm phù hợp nhà xưởng, khách sạn, nhà hàng, văn phòng đông người và nơi nhân viên làm việc tay chân (tay bẩn, ướt) làm vân tay hay lỗi."
                    : "Máy vân tay phù hợp văn phòng, cửa hàng, quán ăn có số nhân viên vừa phải và ngân sách gọn. Nhân viên tay chân thường mòn hoặc bẩn vân tay nên cân nhắc máy khuôn mặt."),
            new("Giá máy chấm công trên trang có cố định không",
                "Giá là giá tham khảo, có thể thay đổi theo thời điểm, số lượng và địa điểm lắp đặt. Để lại số điện thoại hoặc gọi 0973 024 042 để nhận báo giá chính xác."),
            new("Đã có máy chấm công cũ thì có dùng được phần mềm SBOX HRM không",
                "Máy ZKTeco hỗ trợ ADMS đang dùng vẫn kết nối được phần mềm. Xem hướng dẫn kết nối máy chấm công ZKTeco qua Internet hoặc nhờ kỹ thuật SBOX kiểm tra model máy giúp bạn."),
        ];
    }

    public static string DevicePage(DeviceOffer d, IReadOnlyList<DeviceOffer> all)
    {
        var s = Hrm;
        var slug = DeviceSlug(d.Name);
        var url = $"{s.Origin}{DeviceBase}/{slug}";
        var kind = IsFaceDevice(d) ? "face" : "finger";
        var kindName = kind == "face" ? "nhận diện khuôn mặt" : "vân tay";
        var title = $"{d.Name} – máy chấm công {kindName}, giá tốt | SBOX";
        if (title.Length > 66) title = $"{d.Name} – máy chấm công giá tốt | SBOX";
        var priceV = PriceValue(d.Price);
        var priceText = priceV is { } pv ? Vnd(pv) : (d.Price ?? "Liên hệ");
        var oldV = PriceValue(d.OldPrice);
        var desc = $"{d.Name}{(d.Sub == null ? "" : $" – {d.Sub}")}: {d.Specs ?? kindName}. Giá tham khảo {priceText}, miễn phí lắp đặt, tặng phần mềm chấm công SBOX HRM, xem công trên điện thoại.";
        if (desc.Length > 165) desc = $"{d.Name}: {d.Specs ?? kindName}. Giá {priceText}, miễn phí lắp đặt, tặng phần mềm chấm công SBOX HRM.";
        var faq = DeviceFaq(d, kind);
        var image = DeviceImage(d);
        var kw = $"{d.Name}, máy chấm công {d.Name}, giá {d.Name}, mua {d.Name}, máy chấm công {kindName}, {d.Brand ?? "ZKTeco"} chấm công, phần mềm chấm công, lắp đặt máy chấm công";

        var product = new Dictionary<string, object>
        {
            ["@context"] = "https://schema.org",
            ["@type"] = "Product",
            ["name"] = d.Name,
            ["description"] = $"{d.Name}{(d.Sub == null ? "" : $" – {d.Sub}")}. {d.Specs}".Trim(),
            ["image"] = new[] { s.Origin + image },
            ["brand"] = new Dictionary<string, object> { ["@type"] = "Brand", ["name"] = d.Brand ?? "ZKTeco" },
            ["category"] = "Máy chấm công",
            ["url"] = url,
        };
        if (priceV is { } p0)
            product["offers"] = new Dictionary<string, object>
            {
                ["@type"] = "Offer", ["priceCurrency"] = "VND", ["price"] = p0.ToString(CultureInfo.InvariantCulture),
                ["availability"] = "https://schema.org/InStock", ["url"] = url, ["itemCondition"] = "https://schema.org/NewCondition",
                ["seller"] = Organization(s),
            };
        var ld = new List<object>
        {
            product,
            Crumbs(s, ("Trang chủ", s.Origin + "/"), ("Lắp đặt máy chấm công", s.Origin + LocalBase), (d.Name, url)),
        };
        if (FaqLd(faq) is { } f) ld.Add(f);

        var sb = new StringBuilder(Head(s, title, desc, url, s.Origin + image, "website", kw, ld));
        sb.Append("<section class=\"lp-hero\"><div class=\"wrap\"><div>");
        sb.Append($"<div class=\"crumb\" style=\"margin-top:0\"><a href=\"/\">Trang chủ</a> › <a href=\"{LocalBase}\">Lắp đặt máy chấm công</a> › {E(d.Name)}</div>");
        sb.Append($"<span class=\"tag\">{E(d.Brand ?? "Máy chấm công")}</span>");
        sb.Append($"<h1>{E(d.Name)}{(d.Sub == null ? "" : $" – {E(d.Sub)}")}</h1>");
        sb.Append($"<p class=\"lead\">{E(d.Specs ?? "")}. <strong>Giá tham khảo {E(priceText)}</strong>");
        if (oldV is { } ov && priceV is { } nv && ov > nv) sb.Append($" <s style=\"opacity:.75\">{E(Vnd(ov))}</s>");
        sb.Append(" — <strong>miễn phí lắp đặt</strong> và <strong>tặng phần mềm chấm công</strong> SBOX HRM khi mua máy.</p>");
        sb.Append("<div class=\"lp-actions\"><a class=\"btn\" href=\"#bao-gia\">Nhận báo giá</a><a class=\"btn ghost\" href=\"tel:+84973024042\">Gọi 0973 024 042</a></div>");
        sb.Append("<p class=\"lp-note\">Lắp tận nơi toàn quốc · Hỗ trợ qua Zalo 0973 024 042</p></div>");
        sb.Append($"<div><img src=\"{image}\" alt=\"{E(d.Name)} – máy chấm công {E(kindName)}\" width=\"800\" height=\"600\" fetchpriority=\"high\" style=\"max-height:360px;width:auto;max-width:100%;margin:0 auto;display:block;border-radius:16px;object-fit:contain\"></div></div></section>\n");

        sb.Append("<main class=\"wrap\"><div class=\"layout\" style=\"margin-top:26px\"><article><div class=\"content\">\n");

        // ── Thông số ──
        sb.Append($"<h2 id=\"thong-so\">Thông số {E(d.Name)}</h2>\n");
        sb.Append("<div class=\"table-wrap\"><table><thead><tr><th>Hạng mục</th><th>Thông tin</th></tr></thead><tbody>");
        sb.Append($"<tr><td><strong>Loại máy</strong></td><td>Máy chấm công {E(kindName)}</td></tr>");
        if (d.Brand != null) sb.Append($"<tr><td><strong>Thương hiệu</strong></td><td>{E(d.Brand)}</td></tr>");
        if (d.Specs != null) sb.Append($"<tr><td><strong>Chấm công bằng</strong></td><td>{E(d.Specs)}</td></tr>");
        var hasOfficial = OfficialSpecs.TryGetValue(slug, out var off);
        if (hasOfficial)
            foreach (var (n, v) in off.Rows) sb.Append($"<tr><td><strong>{E(n)}</strong></td><td>{E(v)}</td></tr>");
        sb.Append($"<tr><td><strong>Giá tham khảo</strong></td><td><strong>{E(priceText)}</strong></td></tr>");
        sb.Append("</tbody></table></div>\n");
        sb.Append(hasOfficial
            ? $"<p style=\"font-size:14px;color:var(--m)\">Thông số kỹ thuật theo công bố của hãng ({E(off.Source)}); dung lượng có thể khác nhau theo phiên bản và tùy chọn nâng cấp. SBOX báo đúng cấu hình khi báo giá.</p>\n"
            : "<p style=\"font-size:14px;color:var(--m)\">Cấu hình chi tiết (dung lượng, kết nối, phụ kiện) có thể khác nhau theo phiên bản; SBOX báo đúng cấu hình và bảo hành trong phiếu báo giá.</p>\n");

        // ── Phù hợp ──
        sb.Append($"<h2 id=\"phu-hop\">{E(d.Name)} phù hợp với ai?</h2>\n");
        if (kind == "face")
            sb.Append("<ul><li><strong>Nhà xưởng, nhà máy, kho bãi</strong> đông công nhân cần chấm nhanh giờ cao điểm, không chạm.</li>"
                + "<li><strong>Khách sạn, nhà hàng, quán cà phê</strong>: nhân viên tay ướt, bẩn, đeo găng vẫn chấm được.</li>"
                + "<li><strong>Văn phòng vừa và lớn</strong> muốn hạn chế chấm công hộ bằng vân tay hoặc thẻ.</li></ul>\n");
        else
            sb.Append("<ul><li><strong>Văn phòng, cửa hàng, phòng khám</strong> có số nhân viên vừa phải, ngân sách gọn.</li>"
                + "<li><strong>Quán ăn, spa, salon</strong> cần máy đơn giản, dễ dùng cho nhân viên mới.</li>"
                + "<li><strong>Doanh nghiệp nhiều điểm</strong>: mỗi điểm một máy, dữ liệu gom về một phần mềm.</li></ul>\n"
                + "<p>Nhân viên làm việc tay chân thường mòn hoặc bẩn vân tay; khi đó nên chọn máy khuôn mặt hoặc kết hợp thẻ. Xem <a href=\"/bai-viet/cham-cong-khuon-mat-hay-van-tay\">nên chọn khuôn mặt hay vân tay</a>.</p>\n");

        // ── Dùng với SBOX HRM ──
        sb.Append($"<h2 id=\"sbox-hrm\">Dùng {E(d.Name)} với phần mềm SBOX HRM</h2>\n");
        sb.Append(HasAdms(d) || HasWifi(d)
            ? $"<p>{E(d.Name)} kết nối Internet {(HasAdms(d) ? "theo giao thức <strong>ADMS</strong>" : "qua <strong>WiFi</strong>")}: nhân viên vừa chấm, dữ liệu đã về SBOX HRM sau vài giây — không cần IP tĩnh, không cần máy tính cài sẵn phần mềm.</p>\n"
            : $"<p>Kỹ thuật SBOX chọn cách kết nối {E(d.Name)} với phần mềm phù hợp hạ tầng mạng của bạn (ưu tiên kết nối Internet để xem công mọi nơi).</p>\n");
        sb.Append("<ul><li>Xem bảng công, đi trễ – về sớm, tăng ca trên <strong>điện thoại, MacBook, trình duyệt web</strong>.</li>"
            + "<li>Bảng lương tự động: ngày công, phụ cấp, BHXH, thuế TNCN.</li>"
            + "<li>Nhân viên xin nghỉ phép, tăng ca và xem phiếu lương trên app.</li>"
            + "<li>Bổ sung <a href=\"/tinh-nang/cham-cong-khuon-mat-dien-thoai\">chấm công bằng điện thoại</a> cho nhân viên đi ngoài, không cần mua thêm máy.</li></ul>\n");
        sb.Append("<p>Tìm hiểu: <a href=\"/tinh-nang/phan-mem-cham-cong-zkteco\">phần mềm chấm công ZKTeco</a>, <a href=\"/bai-viet/ket-noi-may-cham-cong-zkteco-qua-internet\">kết nối máy chấm công qua Internet</a>, <a href=\"/bai-viet/kinh-nghiem-chon-mua-may-cham-cong-zkteco\">kinh nghiệm chọn mua máy chấm công</a>.</p>\n");

        // ── Ưu đãi + quy trình ──
        sb.Append("<h2 id=\"uu-dai\">Ưu đãi khi mua máy tại SBOX</h2>\n<ul><li><strong>Miễn phí lắp đặt</strong> tận nơi, cài đặt kết nối.</li><li><strong>Tặng phần mềm chấm công SBOX HRM</strong> khi mua máy.</li><li>Hướng dẫn đăng ký vân tay / khuôn mặt cho nhân viên.</li><li>Hỗ trợ qua hotline / Zalo <a href=\"tel:+84973024042\">0973 024 042</a>.</li></ul>\n");
        sb.Append(ProcessSection(""));

        // ── So sánh với máy khác ──
        var others = all.Where(x => DeviceSlug(x.Name) != slug).ToList();
        if (others.Count > 0)
        {
            sb.Append("<h2 id=\"may-khac\">Các máy chấm công khác tại SBOX</h2>\n");
            sb.Append("<div class=\"table-wrap\"><table><thead><tr><th>Máy chấm công</th><th>Chấm công bằng</th><th>Giá tham khảo</th></tr></thead><tbody>");
            foreach (var o in others)
            {
                var pr = PriceValue(o.Price) is { } v ? Vnd(v) : (o.Price ?? "Liên hệ");
                sb.Append($"<tr><td><a href=\"{DeviceBase}/{DeviceSlug(o.Name)}\"><strong>{E(o.Name)}</strong></a>{(o.Sub == null ? "" : $"<br><span style=\"color:var(--m);font-size:14px\">{E(o.Sub)}</span>")}</td><td>{E(o.Specs ?? "")}</td><td><strong>{E(pr)}</strong></td></tr>");
            }
            sb.Append("</tbody></table></div>\n");
        }
        sb.Append("<p>Muốn lắp tại tỉnh thành của bạn? Xem <a href=\"" + LocalBase + "\">lắp đặt máy chấm công toàn quốc (34 tỉnh thành)</a>.</p>\n");
        sb.Append("</div>\n");
        sb.Append(LocalLeadSection($"Báo giá {d.Name}"));
        sb.Append("<section class=\"lp-sec faq\"><h2 class=\"t\">Câu hỏi thường gặp</h2>");
        foreach (var q in faq) sb.Append($"<details><summary>{E(q.Question)}</summary><p>{E(q.Answer)}</p></details>");
        sb.Append("</section>\n</article>\n<aside>\n");
        sb.Append("<div class=\"box\"><h2>Ưu đãi khi mua máy</h2><ul style=\"margin:0 0 12px;padding-left:18px;font-size:15px\"><li>Miễn phí lắp đặt tận nơi</li><li>Tặng phần mềm chấm công SBOX HRM</li><li>Giá tốt theo số lượng</li></ul><a class=\"btn\" href=\"#bao-gia\">Nhận báo giá</a></div>\n");
        sb.Append($"<div class=\"box\"><h2>Máy chấm công khác</h2><ul class=\"related\">");
        foreach (var o in others) sb.Append($"<li><a href=\"{DeviceBase}/{DeviceSlug(o.Name)}\">{E(o.Name)}</a></li>");
        sb.Append($"<li><a href=\"{LocalBase}\">Tất cả dịch vụ lắp đặt →</a></li></ul></div>\n");
        sb.Append("</aside></div>\n").Append(Cta(s)).Append("</main>\n").Append(LeadScript).Append(Footer(s));
        return sb.ToString();
    }
}
