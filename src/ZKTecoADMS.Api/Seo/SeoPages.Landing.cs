using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Seo;

/// <summary>
/// Trang đích SEO: /tinh-nang (trang giải pháp theo tính năng / ngành), /bang-gia, /tai-lieu (tài liệu tải miễn phí đổi
/// lấy thông tin liên hệ) + FAQ tự lấy từ mục «## Câu hỏi thường gặp» → JSON-LD FAQPage.
/// </summary>
public static partial class SeoPages
{
    public record FaqItem(string Question, string Answer);

    public record PricingPlan(
        string Name, string? Description, decimal? Monthly, decimal? Yearly, int TrialDays, int MaxUsers, int MaxDevices,
        int MaxBranches, string? Badge, bool Featured, IReadOnlyList<string> Highlights,
        IReadOnlyList<(string Category, IReadOnlyList<string> Modules)> ModuleGroups);

    public static string FeatureUrl(SiteInfo site, SeoArticle a) => $"{site.Origin}/tinh-nang/{a.Slug}";

    // ─── FAQ ────────────────────────────────────────────────────────

    [GeneratedRegex(@"^##\s+(câu hỏi thường gặp|hỏi đáp|hỏi\s*-\s*đáp|faq)\b", RegexOptions.IgnoreCase)]
    private static partial Regex FaqHeadingRx();

    /// <summary>Mục «## Câu hỏi thường gặp»: mỗi «### câu hỏi» + đoạn bên dưới là một cặp hỏi – đáp.</summary>
    public static List<FaqItem> Faq(string? markdown)
    {
        var list = new List<FaqItem>();
        var lines = (markdown ?? "").Replace("\r\n", "\n").Split('\n');
        var inFaq = false;
        string? q = null;
        var a = new List<string>();
        void Flush()
        {
            if (q != null)
            {
                var ans = SeoMarkdown.PlainText(string.Join("\n", a)).Trim();
                if (ans.Length > 0) list.Add(new FaqItem(q.Trim().TrimEnd('?') + "?", ans));
            }
            q = null;
            a.Clear();
        }
        foreach (var raw in lines)
        {
            var line = raw.Trim();
            if (line.StartsWith("## ", StringComparison.Ordinal))
            {
                Flush();
                inFaq = FaqHeadingRx().IsMatch(line);
                continue;
            }
            if (!inFaq) continue;
            if (line.StartsWith("### ", StringComparison.Ordinal))
            {
                Flush();
                q = line[4..];
                continue;
            }
            if (q != null) a.Add(raw);
        }
        Flush();
        return list;
    }

    static object? FaqLd(IReadOnlyList<FaqItem> faq) => faq.Count == 0
        ? null
        : new Dictionary<string, object>
        {
            ["@context"] = "https://schema.org",
            ["@type"] = "FAQPage",
            ["mainEntity"] = faq.Select(f => (object)new Dictionary<string, object>
            {
                ["@type"] = "Question",
                ["name"] = f.Question,
                ["acceptedAnswer"] = new Dictionary<string, object> { ["@type"] = "Answer", ["text"] = f.Answer },
            }).ToArray(),
        };

    static object Crumbs(SiteInfo s, params (string Name, string Url)[] items) => new Dictionary<string, object>
    {
        ["@context"] = "https://schema.org",
        ["@type"] = "BreadcrumbList",
        ["itemListElement"] = items.Select((x, i) => (object)new Dictionary<string, object>
        {
            ["@type"] = "ListItem", ["position"] = i + 1, ["name"] = x.Name, ["item"] = x.Url,
        }).ToArray(),
    };

    static object App(SiteInfo s, string? description = null, IEnumerable<string>? features = null)
    {
        var d = new Dictionary<string, object>
        {
            ["@context"] = "https://schema.org",
            ["@type"] = "SoftwareApplication",
            ["name"] = s.Brand,
            ["applicationCategory"] = "BusinessApplication",
            ["operatingSystem"] = "Web, Android, iOS",
            ["url"] = s.Origin + "/",
            ["image"] = s.Origin + s.DefaultImage,
            ["description"] = description ?? s.CtaText,
            ["offers"] = new Dictionary<string, object>
            {
                ["@type"] = "Offer", ["price"] = "0", ["priceCurrency"] = "VND", ["description"] = "Dùng thử miễn phí, không cần thẻ thanh toán",
            },
            ["publisher"] = Organization(s),
        };
        var f = features?.ToArray();
        if (f is { Length: > 0 }) d["featureList"] = f;
        return d;
    }

    const string LandingCss = """
.lp-hero{background:linear-gradient(180deg,color-mix(in srgb,var(--c) 8%,#fff),#fff);border-bottom:1px solid var(--b);padding:34px 0 40px}
.lp-hero .wrap{display:grid;grid-template-columns:minmax(0,1.1fr) minmax(0,1fr);gap:40px;align-items:center}
.lp-hero h1{font-size:clamp(30px,4.2vw,44px);line-height:1.2;margin:6px 0 14px}.lp-hero p.lead{font-size:19px;color:#334155;margin:0 0 22px}
.lp-hero img{border-radius:16px;border:1px solid var(--b);box-shadow:0 18px 40px rgba(15,23,42,.10);width:100%;aspect-ratio:1200/630;object-fit:cover;background:var(--bg)}
.lp-actions{display:flex;gap:12px;flex-wrap:wrap}.lp-note{font-size:14px;color:var(--m);margin-top:12px}
.lp-sec{padding:10px 0 20px}.lp-sec h2.t{font-size:28px;margin:34px 0 8px}.lp-sec p.s{color:var(--m);margin:0 0 18px}
.faq details{border:1px solid var(--b);border-radius:12px;padding:14px 18px;margin:0 0 10px;background:#fff}.faq summary{cursor:pointer;font-weight:700;font-size:17px}.faq details p{margin:10px 0 0;color:#334155}
.plans{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:20px;margin:24px 0}
.plan{border:1px solid var(--b);border-radius:16px;padding:22px;background:#fff;display:flex;flex-direction:column;gap:10px;position:relative}
.plan.feat{border:2px solid var(--c);box-shadow:0 14px 34px rgba(15,23,42,.10)}.plan h2{margin:0;font-size:21px}.plan .price{font-size:28px;font-weight:800;color:var(--c)}.plan .price small{font-size:15px;color:var(--m);font-weight:600}
.plan ul{margin:0;padding-left:20px;font-size:15px}.plan li{margin:3px 0}.plan .badge{position:absolute;top:-12px;right:16px;background:var(--c);color:#fff;border-radius:20px;padding:2px 12px;font-size:13px;font-weight:700}
.plan details{font-size:14px;color:var(--m)}.plan details summary{cursor:pointer;font-weight:700;color:var(--t)}
.lead-form{border:1px solid var(--b);border-radius:16px;padding:22px;background:var(--bg);display:grid;gap:12px;max-width:560px}
.lead-form input,.lead-form select,.lead-form textarea{font:inherit;padding:11px 13px;border:1px solid #cbd5e1;border-radius:10px;width:100%;background:#fff}
.lead-form .row{display:grid;grid-template-columns:1fr 1fr;gap:12px}.lead-form .msg{font-size:15px;margin:0}.lead-form button{border:0;cursor:pointer;font:inherit;font-size:16px}
.hp{position:absolute!important;left:-9999px!important;width:1px;height:1px;overflow:hidden}
.res{border:1px solid var(--b);border-radius:16px;padding:22px;background:#fff;display:flex;flex-direction:column;gap:10px}.res h2{font-size:20px;margin:0}.res ul{margin:0;padding-left:20px;font-size:15px;color:#334155}
.res .lead-form{padding:14px;background:#fff;margin-top:auto}.res .lead-form .row{grid-template-columns:1fr}
.res .ico{width:44px;height:44px;border-radius:12px;background:#E7F5EC;color:#1E7E45;display:grid;place-items:center;font-weight:800}
.feat-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:20px;margin:22px 0 40px}
@media(max-width:900px){.lp-hero .wrap{grid-template-columns:1fr}.lead-form .row{grid-template-columns:1fr}}
""";

    /// <summary>Form gửi SĐT: POST JSON tới endpoint; data-download → chuyển tới liên kết tải trả về.</summary>
    static string LeadForm(string id, string endpoint, string button, string? plan = null, bool withNote = false) => $"""
<form class="lead-form" id="{id}" data-endpoint="{SeoMarkdown.Enc(endpoint)}" novalidate>
<div class="row"><input name="name" placeholder="Họ và tên *" required autocomplete="name"><input name="phone" placeholder="Số điện thoại / Zalo *" required inputmode="tel" autocomplete="tel"></div>
<input name="company" placeholder="Tên doanh nghiệp / cửa hàng" autocomplete="organization">
{(plan == null ? "" : $"<input type=\"hidden\" name=\"interestedPlan\" value=\"{SeoMarkdown.Enc(plan)}\">")}
{(withNote ? "<textarea name=\"notes\" rows=\"3\" placeholder=\"Số nhân viên, số chi nhánh, máy chấm công đang dùng…\"></textarea>" : "")}
<div class="hp" aria-hidden="true"><input name="website" tabindex="-1" autocomplete="off"></div>
<button class="btn" type="submit">{SeoMarkdown.Enc(button)}</button>
<p class="msg" role="status"></p>
</form>
""";

    const string LeadScript = """
<script>
document.querySelectorAll('form.lead-form').forEach(function (f) {
  f.addEventListener('submit', function (e) {
    e.preventDefault();
    var msg = f.querySelector('.msg'), btn = f.querySelector('button'), data = {};
    new FormData(f).forEach(function (v, k) { data[k] = String(v).trim(); });
    if (!data.name || !data.phone) { msg.textContent = 'Vui lòng nhập họ tên và số điện thoại.'; msg.style.color = '#b91c1c'; return; }
    btn.disabled = true; msg.style.color = ''; msg.textContent = 'Đang gửi…';
    fetch(f.getAttribute('data-endpoint'), { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) })
      .then(function (r) { return r.json().then(function (j) { return { ok: r.ok, j: j }; }); })
      .then(function (x) {
        btn.disabled = false;
        if (!x.ok || !x.j || x.j.isSuccess === false) { msg.textContent = (x.j && (x.j.message || (x.j.errors && x.j.errors[0]))) || 'Gửi chưa được, vui lòng thử lại.'; msg.style.color = '#b91c1c'; return; }
        var url = x.j.data && x.j.data.downloadUrl;
        msg.style.color = '#15803d';
        if (url) { msg.innerHTML = 'Cảm ơn bạn! File đang tải xuống. Nếu không thấy, <a href="' + url + '">bấm vào đây</a>.'; location.href = url; }
        else { msg.textContent = 'Cảm ơn bạn! SBOX sẽ gọi lại trong giờ làm việc.'; f.reset(); }
      })
      .catch(function () { btn.disabled = false; msg.textContent = 'Mất kết nối, vui lòng thử lại.'; msg.style.color = '#b91c1c'; });
  });
});
</script>
""";

    static string Card(string href, string img, string title, string desc, string? tag = null, bool h3 = false)
    {
        var h = h3 ? "h3" : "h2";
        return $"<div class=\"card\"><a href=\"{E(href)}\" tabindex=\"-1\"><img src=\"{E(img)}\" alt=\"{E(title)}\" loading=\"lazy\" width=\"1200\" height=\"630\"></a><div class=\"in\">"
            + (tag == null ? "" : $"<span><span class=\"tag\">{E(tag)}</span></span>")
            + $"<{h}><a href=\"{E(href)}\">{E(title)}</a></{h}><p>{E(desc)}</p></div></div>\n";
    }

    // ─── /tinh-nang ─────────────────────────────────────────────────

    public static string FeatureIndexPage(SiteInfo s, IReadOnlyList<SeoArticle> features)
    {
        var url = s.Origin + "/tinh-nang";
        var title = s.Code == "hrm"
            ? "Tính năng phần mềm chấm công, tính lương & nhân sự | SBOX HRM"
            : "Tính năng phần mềm bán hàng POS cho F&B, bán lẻ, spa | SBOX POS";
        var desc = s.Code == "hrm"
            ? "Khám phá các tính năng SBOX HRM: chấm công máy ZKTeco, chấm công khuôn mặt trên điện thoại, xếp ca, tính lương, nghỉ phép, tăng ca và quản lý hồ sơ nhân sự."
            : "Khám phá các tính năng SBOX POS: bán hàng tại quầy, sơ đồ bàn, gọi món QR, màn hình bếp, quản lý kho, lịch hẹn spa và báo cáo doanh thu theo thời gian thực.";
        var ld = new List<object>
        {
            new Dictionary<string, object>
            {
                ["@context"] = "https://schema.org", ["@type"] = "CollectionPage", ["name"] = title, ["description"] = desc, ["url"] = url,
                ["inLanguage"] = "vi-VN", ["publisher"] = Organization(s),
                ["mainEntity"] = new Dictionary<string, object>
                {
                    ["@type"] = "ItemList",
                    ["itemListElement"] = features.Select((f, i) => (object)new Dictionary<string, object>
                        { ["@type"] = "ListItem", ["position"] = i + 1, ["url"] = FeatureUrl(s, f), ["name"] = f.Title }).ToArray(),
                },
            },
            Crumbs(s, ("Trang chủ", s.Origin + "/"), ("Tính năng", url)),
            App(s, desc, features.Select(f => f.Title)),
        };
        var kw = s.Code == "hrm"
            ? "phần mềm chấm công, phần mềm tính lương, phần mềm quản lý nhân sự, phần mềm HRM, app chấm công, chấm công khuôn mặt, chấm công GPS, chấm công WiFi, chấm công ZKTeco, xếp ca, nghỉ phép online, lương sản phẩm, BHXH, thuế TNCN"
            : null;
        var sb = new StringBuilder(Head(s, title, desc, url, s.Origin + s.DefaultImage, "website", kw, ld));
        sb.Append("<section class=\"hero\"><div class=\"wrap\"><div class=\"crumb\" style=\"margin-top:0\"><a href=\"/\">Trang chủ</a> › Tính năng</div>");
        sb.Append($"<h1>{(s.Code == "hrm" ? "Tính năng phần mềm chấm công, tính lương &amp; quản lý nhân sự SBOX HRM" : "Tính năng SBOX POS")}</h1><p>{E(desc)}</p>");
        sb.Append("<div class=\"lp-actions\" style=\"margin-top:16px\"><a class=\"btn\" href=\"/register\">Dùng thử miễn phí</a><a class=\"btn ghost\" href=\"/bang-gia\">Xem bảng giá</a></div></div></section>\n");
        sb.Append("<main class=\"wrap\">\n<div class=\"feat-grid\">\n");
        foreach (var f in features)
            sb.Append(Card($"/tinh-nang/{f.Slug}", string.IsNullOrWhiteSpace(f.CoverImageUrl) ? s.DefaultImage : f.CoverImageUrl!, f.Title, Description(f), f.Category));
        sb.Append("</div>\n").Append(Cta(s)).Append("</main>\n");
        sb.Append(Footer(s));
        return sb.ToString();
    }

    public static string FeaturePage(SiteInfo s, SeoArticle a, IReadOnlyList<SeoArticle> otherFeatures, IReadOnlyList<SeoArticle> articles)
    {
        var url = FeatureUrl(s, a);
        var title = string.IsNullOrWhiteSpace(a.MetaTitle) ? $"{a.Title} | {s.Brand}" : a.MetaTitle!;
        var desc = Description(a);
        var image = Abs(s, a.CoverImageUrl);
        var body = SeoMarkdown.Render(a.ContentMarkdown, out var headings);
        var faq = Faq(a.ContentMarkdown);
        var ld = new List<object>
        {
            new Dictionary<string, object>
            {
                ["@context"] = "https://schema.org", ["@type"] = "WebPage", ["name"] = a.Title, ["description"] = desc, ["url"] = url,
                ["inLanguage"] = "vi-VN", ["primaryImageOfPage"] = image,
                ["dateModified"] = IsoDate(a.UpdatedAt ?? a.PublishedAt ?? a.CreatedAt),
                ["isPartOf"] = new Dictionary<string, object> { ["@type"] = "WebSite", ["url"] = s.Origin + "/", ["name"] = s.Brand },
                ["about"] = App(s, desc, headings.Where(h => h.Level == 2 && !FaqHeadingRx().IsMatch("## " + h.Text)).Select(h => h.Text)),
            },
            Crumbs(s, ("Trang chủ", s.Origin + "/"), ("Tính năng", s.Origin + "/tinh-nang"), (a.Title, url)),
        };
        if (FaqLd(faq) is { } faqLd) ld.Add(faqLd);

        var sb = new StringBuilder(Head(s, title, desc, url, image, "website", a.Keywords, ld));
        sb.Append("<section class=\"lp-hero\"><div class=\"wrap\"><div>");
        sb.Append("<div class=\"crumb\" style=\"margin-top:0\"><a href=\"/\">Trang chủ</a> › <a href=\"/tinh-nang\">Tính năng</a></div>");
        if (!string.IsNullOrWhiteSpace(a.Category)) sb.Append($"<span class=\"tag\">{E(a.Category)}</span>");
        sb.Append($"<h1>{E(a.Title)}</h1>");
        if (!string.IsNullOrWhiteSpace(a.Summary)) sb.Append($"<p class=\"lead\">{E(a.Summary)}</p>");
        sb.Append("<div class=\"lp-actions\"><a class=\"btn\" href=\"/register\">Dùng thử miễn phí</a><a class=\"btn ghost\" href=\"#tu-van\">Nhận tư vấn</a></div>");
        sb.Append("<p class=\"lp-note\">Không cần thẻ thanh toán · Web, Android, iOS · Hỗ trợ cài đặt qua Zalo 0973 024 042</p></div>");
        sb.Append($"<div><img src=\"{E(string.IsNullOrWhiteSpace(a.CoverImageUrl) ? s.DefaultImage : a.CoverImageUrl)}\" alt=\"{E(a.Title)}\" width=\"1200\" height=\"630\"></div>");
        sb.Append("</div></section>\n");

        sb.Append("<main class=\"wrap\">\n<div class=\"layout\" style=\"margin-top:26px\">\n<article>\n<div class=\"content\">\n").Append(body).Append("</div>\n");
        sb.Append("<section id=\"tu-van\" class=\"lp-sec\"><h2 class=\"t\">Nhận tư vấn & demo miễn phí</h2><p class=\"s\">Để lại số điện thoại, SBOX gọi lại tư vấn cấu hình phù hợp và hướng dẫn dùng thử.</p>");
        sb.Append(LeadForm("tu-van-form", "/api/public/leads", "Gửi yêu cầu tư vấn", a.Title, withNote: true)).Append("</section>\n");
        if (articles.Count > 0)
        {
            sb.Append("<section class=\"lp-sec\"><h2 class=\"t\">Bài viết hữu ích</h2><div class=\"cards\">");
            foreach (var r in articles)
                sb.Append(Card($"/bai-viet/{r.Slug}", string.IsNullOrWhiteSpace(r.CoverImageUrl) ? s.DefaultImage : r.CoverImageUrl!, r.Title, Description(r), r.Category, h3: true));
            sb.Append("</div></section>\n");
        }
        sb.Append("</article>\n<aside>\n");
        var toc = headings.Where(h => h.Level == 2).ToList();
        if (toc.Count >= 2)
        {
            sb.Append("<div class=\"box toc\"><h2>Trên trang này</h2><ol>");
            foreach (var h in toc) sb.Append($"<li><a href=\"#{h.Id}\">{E(h.Text)}</a></li>");
            sb.Append("</ol></div>\n");
        }
        if (otherFeatures.Count > 0)
        {
            sb.Append("<div class=\"box\"><h2>Tính năng khác</h2><ul class=\"related\">");
            foreach (var f in otherFeatures) sb.Append($"<li><a href=\"/tinh-nang/{E(f.Slug)}\">{E(f.Title)}</a></li>");
            sb.Append("</ul></div>\n");
        }
        sb.Append($"<div class=\"box\"><h2>{E(s.Brand)}</h2><p style=\"margin:0 0 12px;font-size:15px;color:var(--m)\">{E(s.CtaText)}</p><a class=\"btn\" href=\"/register\">Dùng thử miễn phí</a> <a href=\"/bang-gia\" style=\"display:inline-block;margin-top:10px;font-weight:700\">Xem bảng giá →</a></div>\n");
        sb.Append("</aside>\n</div>\n").Append(Cta(s)).Append("</main>\n");
        sb.Append(LeadScript);
        sb.Append(Footer(s));
        return sb.ToString();
    }

    // ─── /bang-gia ─────────────────────────────────────────────────

    static readonly CultureInfo ViPrice = CultureInfo.GetCultureInfo("vi-VN");
    static string Vnd(decimal v) => v.ToString("#,##0", ViPrice) + " đ";

    static IReadOnlyList<FaqItem> PricingFaq(SiteInfo s) => s.Code == "hrm"
        ?
        [
            new("Dùng thử có mất phí hay cần thẻ thanh toán không", "Không. Bạn đăng ký tài khoản trên web hoặc app, dùng thử miễn phí đầy đủ tính năng của gói đã chọn, không cần nhập thẻ thanh toán."),
            new("Giá đã bao gồm máy chấm công chưa", "Chưa. Giá là phí sử dụng phần mềm. SBOX kết nối được máy chấm công ZKTeco có hỗ trợ ADMS / Push mà doanh nghiệp đang có, hoặc chấm công bằng điện thoại không cần mua máy."),
            new("Có phí cài đặt, đào tạo không", "Không thu phí cài đặt. Đội kỹ thuật SBOX hỗ trợ kết nối máy chấm công, nhập nhân viên và cấu hình ca, lương qua Zalo, điện thoại hoặc điều khiển máy tính từ xa."),
            new("Có thể nâng cấp hoặc đổi gói sau không", "Có. Bạn có thể nâng gói, thêm người dùng, chi nhánh hoặc máy chấm công bất kỳ lúc nào; dữ liệu giữ nguyên."),
            new("Có xuất được dữ liệu ra Excel không", "Có. Bảng công, bảng lương, phiếu lương và các báo cáo đều xuất được Excel bất kỳ lúc nào để lưu trữ hoặc gửi kế toán."),
        ]
        :
        [
            new("Dùng thử có mất phí hay cần thẻ thanh toán không", "Không. Bạn đăng ký và bán hàng thử miễn phí trên web, máy POS Android hoặc tablet, không cần thẻ thanh toán."),
            new("Giá đã bao gồm máy POS, máy in chưa", "Chưa. Giá là phí sử dụng phần mềm. SBOX POS chạy trên máy tính, tablet, điện thoại và máy POS Android; dùng được máy in nhiệt 58/80mm qua LAN, USB hoặc Bluetooth."),
            new("Gói khác nhau ở điểm nào", "Các gói khác nhau ở nhóm chức năng (bán hàng, kho, bếp, gọi món QR, lịch hẹn…), số tài khoản, chi nhánh và thiết bị đăng nhập. Bấm «Chức năng trong gói» ở từng gói để xem chi tiết."),
            new("Có xuất hóa đơn điện tử không", "Có. SBOX POS kết nối nhà cung cấp hóa đơn điện tử để xuất hóa đơn ngay từ đơn bán, hỗ trợ hộ kinh doanh và doanh nghiệp."),
            new("Có thể thêm chi nhánh sau không", "Có. Bạn thêm chi nhánh, kho và nhân viên bất kỳ lúc nào; báo cáo tổng hợp toàn chuỗi và từng cửa hàng."),
        ];

    public static string PricingPage(SiteInfo s, IReadOnlyList<PricingPlan> plans)
    {
        var url = s.Origin + "/bang-gia";
        var title = s.Code == "hrm" ? "Bảng giá phần mềm chấm công, tính lương | SBOX HRM" : "Bảng giá phần mềm bán hàng POS | SBOX POS";
        var desc = s.Code == "hrm"
            ? "Bảng giá SBOX HRM: gói chấm công điện thoại, máy chấm công ZKTeco và gói nhân sự đầy đủ. Không phí cài đặt, dùng thử miễn phí, nâng cấp bất kỳ lúc nào."
            : "Bảng giá SBOX POS: phần mềm bán hàng cho quán cà phê, nhà hàng, bán lẻ, spa. Không phí cài đặt, dùng thử miễn phí, nâng cấp bất kỳ lúc nào.";
        var faq = PricingFaq(s);
        var offers = plans.Where(p => p.Monthly.HasValue || p.Yearly.HasValue).Select(p => (object)new Dictionary<string, object>
        {
            ["@type"] = "Offer", ["name"] = p.Name, ["priceCurrency"] = "VND",
            ["price"] = (p.Monthly ?? p.Yearly!.Value).ToString("0", CultureInfo.InvariantCulture),
            ["description"] = p.Monthly.HasValue ? "Giá theo tháng" : "Giá theo năm",
        }).ToArray();
        var app = (Dictionary<string, object>)App(s, desc);
        if (offers.Length > 0) app["offers"] = offers;
        var ld = new List<object> { app, Crumbs(s, ("Trang chủ", s.Origin + "/"), ("Bảng giá", url)) };
        if (FaqLd(faq) is { } faqLd) ld.Add(faqLd);

        var kw = s.Code == "hrm"
            ? "bảng giá phần mềm chấm công, giá phần mềm tính lương, giá phần mềm quản lý nhân sự, phần mềm chấm công miễn phí, giá máy chấm công, SBOX HRM"
            : null;
        var sb = new StringBuilder(Head(s, title, desc, url, s.Origin + s.DefaultImage, "website", kw, ld));
        sb.Append("<section class=\"hero\"><div class=\"wrap\"><div class=\"crumb\" style=\"margin-top:0\"><a href=\"/\">Trang chủ</a> › Bảng giá</div>");
        sb.Append($"<h1>{(s.Code == "hrm" ? "Bảng giá phần mềm chấm công, tính lương SBOX HRM" : "Bảng giá " + E(s.Brand))}</h1><p>{E(desc)}</p></div></section>\n<main class=\"wrap\">\n");
        if (plans.Count == 0) sb.Append("<p style=\"margin:30px 0\">Bảng giá đang được cập nhật — vui lòng để lại số điện thoại để nhận báo giá.</p>");
        sb.Append("<div class=\"plans\">\n");
        foreach (var p in plans)
        {
            sb.Append($"<div class=\"plan{(p.Featured ? " feat" : "")}\">");
            if (!string.IsNullOrWhiteSpace(p.Badge) || p.Featured) sb.Append($"<span class=\"badge\">{E(string.IsNullOrWhiteSpace(p.Badge) ? "Phổ biến" : p.Badge)}</span>");
            sb.Append($"<h2>{E(p.Name)}</h2>");
            sb.Append(p.Monthly.HasValue
                ? $"<div class=\"price\">{Vnd(p.Monthly.Value)} <small>/ tháng</small></div>"
                : p.Yearly.HasValue
                    ? $"<div class=\"price\">{Vnd(p.Yearly.Value)} <small>/ năm</small></div>"
                    : "<div class=\"price\" style=\"font-size:22px\">Liên hệ báo giá</div>");
            if (p.Monthly.HasValue && p.Yearly.HasValue) sb.Append($"<div style=\"font-size:14px;color:var(--m)\">hoặc {Vnd(p.Yearly.Value)} / năm</div>");
            if (!string.IsNullOrWhiteSpace(p.Description)) sb.Append($"<p style=\"margin:0;color:#334155;font-size:15px\">{E(p.Description)}</p>");
            sb.Append("<ul>");
            if (p.TrialDays > 0) sb.Append($"<li>Dùng thử miễn phí {p.TrialDays} ngày</li>");
            sb.Append($"<li>{(p.MaxUsers > 0 ? $"Tối đa {p.MaxUsers} tài khoản người dùng" : "Không giới hạn người dùng")}</li>");
            if (s.Code == "hrm") sb.Append($"<li>{(p.MaxDevices > 0 ? $"{p.MaxDevices} máy chấm công" : "Không giới hạn máy chấm công")}</li>");
            sb.Append($"<li>{(p.MaxBranches > 0 ? $"{p.MaxBranches} chi nhánh" : "Không giới hạn chi nhánh")}</li>");
            foreach (var h in p.Highlights) sb.Append($"<li>{E(h)}</li>");
            sb.Append("</ul>");
            if (p.ModuleGroups.Count > 0)
            {
                sb.Append("<details><summary>Chức năng trong gói</summary>");
                foreach (var (cat, mods) in p.ModuleGroups) sb.Append($"<p style=\"margin:8px 0 0\"><strong>{E(cat)}:</strong> {E(string.Join(", ", mods))}</p>");
                sb.Append("</details>");
            }
            sb.Append($"<div class=\"lp-actions\" style=\"margin-top:auto;padding-top:8px\"><a class=\"btn\" href=\"/register\">Dùng thử</a><a class=\"btn ghost\" href=\"#bao-gia\" onclick=\"var i=document.querySelector('#bao-gia-form [name=interestedPlan]');if(i)i.value={E(System.Text.Json.JsonSerializer.Serialize(p.Name))}\">Nhận báo giá</a></div>");
            sb.Append("</div>\n");
        }
        sb.Append("</div>\n<p style=\"color:var(--m);font-size:14px\">* Giá chưa gồm VAT. Không phí cài đặt. Hỗ trợ kết nối thiết bị và cấu hình ban đầu miễn phí.</p>\n");
        sb.Append("<section id=\"bao-gia\" class=\"lp-sec\"><h2 class=\"t\">Nhận báo giá theo quy mô</h2><p class=\"s\">Cho SBOX biết số nhân viên, chi nhánh và thiết bị — chúng tôi gọi lại báo giá và tư vấn gói tiết kiệm nhất.</p>");
        sb.Append(LeadForm("bao-gia-form", "/api/public/leads", "Nhận báo giá", plan: "", withNote: true)).Append("</section>\n");
        sb.Append("<section class=\"lp-sec faq\"><h2 class=\"t\">Câu hỏi về giá & gói dịch vụ</h2>");
        foreach (var f in faq) sb.Append($"<details><summary>{E(f.Question)}</summary><p>{E(f.Answer)}</p></details>");
        sb.Append("</section>\n").Append(Cta(s)).Append("</main>\n");
        sb.Append(LeadScript);
        sb.Append(Footer(s));
        return sb.ToString();
    }

    // ─── /tai-lieu ─────────────────────────────────────────────────

    public static string ResourcesPage(SiteInfo s)
    {
        var url = s.Origin + "/tai-lieu";
        var items = SeoResources.ForSite(s.Code).ToList();
        var title = s.Code == "hrm"
            ? "Tải miễn phí mẫu bảng lương, bảng chấm công Excel 2026 | SBOX HRM"
            : "Tải miễn phí mẫu quản lý kho, định lượng món Excel | SBOX POS";
        var desc = s.Code == "hrm"
            ? "Tải miễn phí mẫu bảng lương Excel 2026 tự tính BHXH, thuế TNCN; mẫu bảng chấm công tháng và checklist onboarding nhân viên mới."
            : "Tải miễn phí mẫu Excel quản lý kho nhập – xuất – tồn, bảng định lượng & giá vốn món, biên bản chốt ca thu ngân cho quán và cửa hàng.";
        var ld = new List<object>
        {
            new Dictionary<string, object>
            {
                ["@context"] = "https://schema.org", ["@type"] = "CollectionPage", ["name"] = title, ["description"] = desc, ["url"] = url,
                ["inLanguage"] = "vi-VN", ["publisher"] = Organization(s),
                ["hasPart"] = items.Select(r => (object)new Dictionary<string, object>
                {
                    ["@type"] = "DigitalDocument", ["name"] = r.Title, ["description"] = r.Description,
                    ["encodingFormat"] = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                    ["isAccessibleForFree"] = true, ["url"] = $"{url}#{r.Slug}",
                }).ToArray(),
            },
            Crumbs(s, ("Trang chủ", s.Origin + "/"), ("Tài liệu", url)),
        };
        var sb = new StringBuilder(Head(s, title, desc, url, s.Origin + s.DefaultImage, "website", null, ld));
        sb.Append("<section class=\"hero\"><div class=\"wrap\"><div class=\"crumb\" style=\"margin-top:0\"><a href=\"/\">Trang chủ</a> › Tài liệu</div>");
        sb.Append($"<h1>{(s.Code == "hrm" ? "Tài liệu nhân sự miễn phí" : "Tài liệu quản lý cửa hàng miễn phí")}</h1><p>{E(desc)} Điền tên và số điện thoại để tải ngay.</p></div></section>\n");
        sb.Append("<main class=\"wrap\">\n<div class=\"feat-grid\">\n");
        foreach (var r in items)
        {
            sb.Append($"<div class=\"res\" id=\"{E(r.Slug)}\"><div class=\"ico\">XLS</div><h2>{E(r.Title)}</h2><p style=\"margin:0;color:var(--m)\">{E(r.Description)}</p><ul>");
            foreach (var x in r.Inside) sb.Append($"<li>{E(x)}</li>");
            sb.Append("</ul>");
            if (r.ArticleSlug != null) sb.Append($"<a href=\"/bai-viet/{E(r.ArticleSlug)}\" style=\"font-weight:700;font-size:15px\">Đọc hướng dẫn sử dụng →</a>");
            sb.Append(LeadForm($"tl-{r.Slug}", $"/api/public/resources/{r.Slug}", "Tải miễn phí"));
            sb.Append("</div>\n");
        }
        sb.Append("</div>\n<p style=\"color:var(--m);font-size:14px\">Thông tin của bạn chỉ dùng để SBOX gửi tài liệu và tư vấn khi bạn cần — không chia sẻ cho bên thứ ba.</p>\n");
        sb.Append(Cta(s)).Append("</main>\n");
        sb.Append(LeadScript);
        sb.Append(Footer(s));
        return sb.ToString();
    }
}
