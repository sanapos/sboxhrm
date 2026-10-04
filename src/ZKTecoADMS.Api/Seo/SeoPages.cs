using System.Globalization;
using System.Text;
using System.Text.Json;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Seo;

/// <summary>
/// Dựng HTML phía server cho bài viết SEO (bot không cần chạy JavaScript): canonical theo tên miền,
/// Open Graph, JSON-LD Article / BreadcrumbList / CollectionPage, mục lục, bài liên quan; sitemap + robots theo site.
/// </summary>
public static partial class SeoPages
{
    public record SiteInfo(
        string Code, string Origin, string Brand, string Tagline, string Color, string ColorDark,
        string Logo, string DefaultImage, string Privacy, string? Terms, string CtaTitle, string CtaText,
        string BlogTitle, string BlogDescription);

    public static readonly SiteInfo Hrm = new(
        "hrm", "https://sboxhrm.com", "SBOX HRM", "Phần mềm chấm công & tính lương",
        "#0C56D0", "#0A3F99", "/images/landing/sbox-logo.png", "/images/landing/screenshot-01.jpg",
        "/privacy-policy.html", null,
        "Dùng thử SBOX HRM miễn phí",
        "Chấm công khuôn mặt, kết nối máy ZKTeco, xếp ca và tính lương tự động — triển khai trong 1–3 ngày.",
        "Kiến thức chấm công, tính lương & quản lý nhân sự",
        "Hướng dẫn chấm công, tính lương, bảo hiểm, thuế TNCN và quản lý nhân sự cho doanh nghiệp Việt Nam — từ đội ngũ SBOX HRM.");

    public static readonly SiteInfo Pos = new(
        "pos", "https://sboxpos.com", "SBOX POS", "Phần mềm bán hàng & quản lý cửa hàng",
        "#2E7D32", "#1B5E20", "/images/landing/sbox-pos-logo.png", "/images/landing/pos/sbox-pos-og.jpg?v=3",
        "/privacy-policy-pos.html", "/terms-pos.html",
        "Dùng thử SBOX POS miễn phí",
        "Bán tại quầy, sơ đồ bàn, in hóa đơn & phiếu bếp, quản lý kho và báo cáo doanh thu theo thời gian thực.",
        "Kiến thức bán hàng & quản lý cửa hàng",
        "Kinh nghiệm mở và vận hành quán cà phê, nhà hàng, cửa hàng bán lẻ: quản lý kho, giá vốn, khuyến mãi, hóa đơn điện tử — từ đội ngũ SBOX POS.");

    /// <summary>sboxpos.* → POS; còn lại (sboxhrm.com, localhost…) → HRM. ?site=pos|hrm để thử ở máy dev.</summary>
    public static SiteInfo Detect(string? host, string? siteQuery = null)
    {
        if (string.Equals(siteQuery, "pos", StringComparison.OrdinalIgnoreCase)) return Pos;
        if (string.Equals(siteQuery, "hrm", StringComparison.OrdinalIgnoreCase)) return Hrm;
        return (host ?? "").Contains("sboxpos", StringComparison.OrdinalIgnoreCase) ? Pos : Hrm;
    }

    static readonly CultureInfo Vi = CultureInfo.GetCultureInfo("vi-VN");
    static string E(string? s) => SeoMarkdown.Enc(s);
    static string Abs(SiteInfo site, string? url) =>
        string.IsNullOrWhiteSpace(url) ? site.Origin + site.DefaultImage
        : url.StartsWith("http", StringComparison.OrdinalIgnoreCase) ? url : site.Origin + (url.StartsWith('/') ? url : "/" + url);

    public static string ArticleUrl(SiteInfo site, SeoArticle a) => $"{site.Origin}/bai-viet/{a.Slug}";

    public static string Description(SeoArticle a)
    {
        var d = a.MetaDescription ?? a.Summary;
        if (string.IsNullOrWhiteSpace(d)) d = SeoMarkdown.PlainText(a.ContentMarkdown);
        d = d.Trim();
        return d.Length > 160 ? d[..157].TrimEnd() + "…" : d;
    }

    static int ReadingMinutes(string markdown) =>
        Math.Max(1, (int)Math.Round(SeoMarkdown.PlainText(markdown).Split(' ', StringSplitOptions.RemoveEmptyEntries).Length / 220.0));

    static string Date(DateTime? d) => (d ?? DateTime.UtcNow).AddHours(7).ToString("dd/MM/yyyy", Vi);
    static string IsoDate(DateTime? d) => DateTime.SpecifyKind(d ?? DateTime.UtcNow, DateTimeKind.Utc).ToString("yyyy-MM-ddTHH:mm:ssZ");

    static string Json(object o) =>
        JsonSerializer.Serialize(o, new JsonSerializerOptions { Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping })
            .Replace("</", "<\\/");

    static string Head(SiteInfo site, string title, string description, string canonical, string image,
        string ogType, string? keywords, IEnumerable<object> jsonLd, string? robots = null)
    {
        var sb = new StringBuilder();
        sb.Append("<!DOCTYPE html>\n<html lang=\"vi\">\n<head>\n<meta charset=\"utf-8\">\n");
        sb.Append("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n");
        sb.Append($"<title>{E(title)}</title>\n");
        sb.Append($"<meta name=\"description\" content=\"{E(description)}\">\n");
        if (!string.IsNullOrWhiteSpace(keywords)) sb.Append($"<meta name=\"keywords\" content=\"{E(keywords)}\">\n");
        sb.Append($"<meta name=\"robots\" content=\"{robots ?? "index, follow, max-image-preview:large, max-snippet:-1"}\">\n");
        sb.Append($"<link rel=\"canonical\" href=\"{E(canonical)}\">\n");
        sb.Append($"<link rel=\"alternate\" hreflang=\"vi\" href=\"{E(canonical)}\">\n");
        sb.Append($"<meta name=\"theme-color\" content=\"{site.Color}\">\n");
        sb.Append($"<meta property=\"og:type\" content=\"{ogType}\">\n<meta property=\"og:locale\" content=\"vi_VN\">\n");
        sb.Append($"<meta property=\"og:site_name\" content=\"{E(site.Brand)}\">\n");
        sb.Append($"<meta property=\"og:title\" content=\"{E(title)}\">\n");
        sb.Append($"<meta property=\"og:description\" content=\"{E(description)}\">\n");
        sb.Append($"<meta property=\"og:url\" content=\"{E(canonical)}\">\n");
        sb.Append($"<meta property=\"og:image\" content=\"{E(image)}\">\n");
        sb.Append("<meta name=\"twitter:card\" content=\"summary_large_image\">\n");
        sb.Append($"<meta name=\"twitter:title\" content=\"{E(title)}\">\n");
        sb.Append($"<meta name=\"twitter:description\" content=\"{E(description)}\">\n");
        sb.Append($"<meta name=\"twitter:image\" content=\"{E(image)}\">\n");
        sb.Append("<link rel=\"icon\" type=\"image/png\" href=\"/favicon.png\">\n");
        foreach (var ld in jsonLd)
            sb.Append("<script type=\"application/ld+json\">").Append(Json(ld)).Append("</script>\n");
        sb.Append("<style>").Append(Css(site)).Append(LandingCss).Append("</style>\n</head>\n<body>\n");
        sb.Append(Header(site));
        return sb.ToString();
    }

    static string Css(SiteInfo s) => $$"""
:root{--c:{{s.Color}};--cd:{{s.ColorDark}};--t:#0f172a;--m:#475569;--b:#e2e8f0;--bg:#f8fafc}
*{box-sizing:border-box}body{margin:0;font-family:"Be Vietnam Pro",system-ui,-apple-system,"Segoe UI",Roboto,Arial,sans-serif;color:var(--t);background:#fff;line-height:1.7;font-size:17px}
a{color:var(--c)}img{max-width:100%;height:auto}
.wrap{max-width:1120px;margin:0 auto;padding:0 20px}
header.top{border-bottom:1px solid var(--b);background:#fff;position:sticky;top:0;z-index:10}
header.top .wrap{display:flex;align-items:center;gap:20px;height:64px}
.logo{display:flex;align-items:center;gap:10px;text-decoration:none;color:var(--t);font-weight:800;font-size:18px}.logo img{height:36px;width:auto}
nav.menu{display:flex;gap:18px;margin-left:auto;align-items:center;flex-wrap:wrap}nav.menu a{text-decoration:none;color:var(--m);font-weight:600;font-size:15px}nav.menu a:hover{color:var(--c)}
.btn{display:inline-block;background:var(--c);color:#fff!important;padding:10px 18px;border-radius:10px;text-decoration:none;font-weight:700}.btn:hover{background:var(--cd)}
.btn.ghost{background:transparent;color:var(--c)!important;border:2px solid var(--c)}
.crumb{font-size:14px;color:var(--m);margin:22px 0 6px}.crumb a{color:var(--m);text-decoration:none}.crumb a:hover{color:var(--c)}
.layout{display:grid;grid-template-columns:minmax(0,1fr) 300px;gap:48px;align-items:start}
article h1{font-size:clamp(28px,4vw,40px);line-height:1.25;margin:8px 0 12px}
.meta{color:var(--m);font-size:14px;margin-bottom:18px}.tag{display:inline-block;background:color-mix(in srgb,var(--c) 10%,#fff);color:var(--c);border-radius:20px;padding:2px 10px;font-weight:700;font-size:13px;margin-right:8px;text-decoration:none}
.lead{font-size:19px;color:#334155}
.cover{border-radius:14px;margin:6px 0 22px;width:100%;object-fit:cover;aspect-ratio:1200/630;background:var(--bg)}
.content h2{font-size:26px;margin:34px 0 10px;line-height:1.3}.content h3{font-size:21px;margin:26px 0 8px}.content h4{font-size:18px;margin:20px 0 6px}
.content p,.content li{color:#1e293b}.content blockquote{margin:20px 0;padding:12px 18px;border-left:4px solid var(--c);background:var(--bg);border-radius:0 10px 10px 0}
.content figure{margin:22px 0}.content figure img{border-radius:12px;border:1px solid var(--b)}.content figcaption{font-size:14px;color:var(--m);text-align:center;margin-top:6px}
.table-wrap{overflow-x:auto;margin:18px 0}table{border-collapse:collapse;width:100%;font-size:15px}th,td{border:1px solid var(--b);padding:9px 12px;text-align:left;vertical-align:top}th{background:var(--bg)}
code{background:var(--bg);padding:2px 6px;border-radius:6px;font-size:.92em}hr{border:0;border-top:1px solid var(--b);margin:30px 0}
aside .box{border:1px solid var(--b);border-radius:14px;padding:18px;margin-bottom:18px;background:#fff}aside h2{font-size:16px;margin:0 0 10px}
.toc ol{margin:0;padding-left:18px;font-size:15px}.toc li{margin:4px 0}.toc a{text-decoration:none;color:var(--m)}.toc a:hover{color:var(--c)}
.cta{background:linear-gradient(135deg,var(--c),var(--cd));color:#fff;border-radius:16px;padding:26px;margin:36px 0}.cta h2{margin:0 0 8px;color:#fff;font-size:22px}.cta p{color:#e2e8f0;margin:0 0 16px}.cta .btn{background:#fff;color:var(--cd)!important}
.cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:22px;margin:22px 0 40px}
.card{border:1px solid var(--b);border-radius:14px;overflow:hidden;display:flex;flex-direction:column;background:#fff;transition:box-shadow .15s}.card:hover{box-shadow:0 8px 24px rgba(15,23,42,.08)}
.card img{aspect-ratio:1200/630;object-fit:cover;width:100%;background:var(--bg)}.card .in{padding:16px 18px 18px;display:flex;flex-direction:column;gap:6px;flex:1}
.card h2,.card h3{font-size:19px;line-height:1.35;margin:0}.card h2 a,.card h3 a{text-decoration:none;color:var(--t)}.card h2 a:hover,.card h3 a:hover{color:var(--c)}
.card p{margin:0;color:var(--m);font-size:15px}.card .meta{margin:auto 0 0;font-size:13px}
.hero{background:var(--bg);border-bottom:1px solid var(--b);padding:34px 0 26px}.hero h1{margin:6px 0 8px;font-size:clamp(28px,4vw,38px);line-height:1.25}.hero p{margin:0;color:var(--m);max-width:760px}
.cats{display:flex;gap:8px;flex-wrap:wrap;margin-top:16px}
.pager{display:flex;gap:8px;justify-content:center;margin:0 0 50px}.pager a,.pager span{padding:8px 14px;border:1px solid var(--b);border-radius:10px;text-decoration:none}.pager span{background:var(--c);color:#fff;border-color:var(--c)}
.related{list-style:none;padding:0;margin:0}.related li{margin:0 0 12px;font-size:15px;line-height:1.45}.related a{text-decoration:none;color:var(--t);font-weight:600}.related a:hover{color:var(--c)}
footer{border-top:1px solid var(--b);background:var(--bg);padding:30px 0;margin-top:30px;font-size:14px;color:var(--m)}footer .wrap{display:flex;gap:24px;flex-wrap:wrap;justify-content:space-between}footer a{color:var(--m);margin-right:14px}
.mbar{display:none}
@media(max-width:900px){.layout{grid-template-columns:1fr}aside{order:2}body{font-size:16px;padding-bottom:72px}
header.top .wrap{flex-wrap:wrap;height:auto;padding-top:10px;gap:8px}
nav.menu{order:3;width:100%;margin:0 -20px;padding:0 20px 10px;flex-wrap:nowrap;overflow-x:auto;gap:8px;scrollbar-width:none}nav.menu::-webkit-scrollbar{display:none}
nav.menu a{flex:0 0 auto;font-size:14px;padding:6px 12px;border:1px solid var(--b);border-radius:999px;background:var(--bg)}nav.menu a.btn{display:none}
.mbar{display:flex;gap:10px;position:fixed;left:0;right:0;bottom:0;z-index:20;padding:10px 14px calc(10px + env(safe-area-inset-bottom));background:#fff;border-top:1px solid var(--b);box-shadow:0 -6px 20px rgba(15,23,42,.06)}
.mbar a{flex:1;text-align:center;padding:12px 10px;border-radius:12px;font-weight:700;text-decoration:none;font-size:15px}.mbar .call{border:1.5px solid var(--c);color:var(--c)}.mbar .btn{padding:12px 10px}
.hero{padding:22px 0 20px}.cards{gap:16px;grid-template-columns:1fr}.cta{padding:20px}footer .wrap{flex-direction:column;gap:12px}footer a{display:inline-block;margin:4px 14px 4px 0} }
""";

    static string Header(SiteInfo s) => $"""
<header class="top"><div class="wrap">
<a class="logo" href="/"><img src="{s.Logo}" alt="{E(s.Brand)}" width="36" height="36"><span>{E(s.Brand)}</span></a>
<nav class="menu" aria-label="Điều hướng"><a class="hide-m" href="/tinh-nang">Tính năng</a><a class="hide-m" href="/bang-gia">Bảng giá</a><a href="/bai-viet">Bài viết</a><a class="hide-m" href="/tai-lieu">Tài liệu</a><a class="hide-m" href="/login-app">Đăng nhập</a><a class="btn" href="/register">Dùng thử miễn phí</a></nav>
</div></header>
""";

    static string Footer(SiteInfo s) => $"""
<footer><div class="wrap">
<div><strong>{E(s.Brand)}</strong> — {E(s.Tagline)}<br>Hotline / Zalo: <a href="tel:+84973024042">0973 024 042</a> · Email: <a href="mailto:support@sboxhrm.com">support@sboxhrm.com</a><br>184 Nam Cao, Hòa Khánh, Đà Nẵng</div>
<div><a href="/">Trang chủ</a><a href="/tinh-nang">Tính năng</a><a href="/bang-gia">Bảng giá</a><a href="/bai-viet">Bài viết</a><a href="/tai-lieu">Tài liệu</a>{(s.Code == "hrm" ? "<a href=\"/lap-dat-may-cham-cong\">Lắp đặt máy chấm công</a>" : "")}<a href="{s.Privacy}">Chính sách bảo mật</a>{(s.Terms == null ? "" : $"<a href=\"{s.Terms}\">Điều khoản</a>")}</div>
</div></footer>
<div class="mbar"><a class="call" href="tel:+84973024042">Gọi 0973 024 042</a><a class="btn" href="/register">Dùng thử miễn phí</a></div>
</body>
</html>
""";

    static string Cta(SiteInfo s) => $"""
<section class="cta"><h2>{E(s.CtaTitle)}</h2><p>{E(s.CtaText)}</p><a class="btn" href="/register">Đăng ký miễn phí</a> <a class="btn ghost" style="color:#fff!important;border-color:#fff" href="tel:+84973024042">Gọi tư vấn</a></section>
""";

    static object Organization(SiteInfo s) => new Dictionary<string, object>
    {
        ["@type"] = "Organization",
        ["@id"] = s.Origin + "/#organization",
        ["name"] = s.Brand,
        ["url"] = s.Origin + "/",
        ["logo"] = new Dictionary<string, object> { ["@type"] = "ImageObject", ["url"] = s.Origin + s.Logo },
        ["email"] = "support@sboxhrm.com",
        ["telephone"] = "+84-973-024-042",
        ["address"] = new Dictionary<string, object>
        {
            ["@type"] = "PostalAddress", ["streetAddress"] = "184 Nam Cao", ["addressLocality"] = "Hòa Khánh",
            ["addressRegion"] = "Đà Nẵng", ["addressCountry"] = "VN",
        },
    };

    public static string ArticlePage(SiteInfo s, SeoArticle a, IReadOnlyList<SeoArticle> related)
    {
        var url = ArticleUrl(s, a);
        var title = string.IsNullOrWhiteSpace(a.MetaTitle) ? $"{a.Title} | {s.Brand}" : a.MetaTitle!;
        var desc = Description(a);
        var image = Abs(s, a.CoverImageUrl);
        var body = SeoMarkdown.Render(a.ContentMarkdown, out var headings);
        var published = a.PublishedAt ?? a.CreatedAt;
        var modified = a.UpdatedAt ?? published;

        var articleLd = new Dictionary<string, object>
        {
            ["@context"] = "https://schema.org",
            ["@type"] = "BlogPosting",
            ["headline"] = a.Title.Length > 110 ? a.Title[..110] : a.Title,
            ["description"] = desc,
            ["image"] = new[] { image },
            ["datePublished"] = IsoDate(published),
            ["dateModified"] = IsoDate(modified),
            ["inLanguage"] = "vi-VN",
            ["mainEntityOfPage"] = new Dictionary<string, object> { ["@type"] = "WebPage", ["@id"] = url },
            ["author"] = new Dictionary<string, object> { ["@type"] = "Organization", ["name"] = a.AuthorName ?? s.Brand, ["url"] = s.Origin + "/" },
            ["publisher"] = Organization(s),
        };
        if (!string.IsNullOrWhiteSpace(a.Keywords)) articleLd["keywords"] = a.Keywords!;
        if (!string.IsNullOrWhiteSpace(a.Category)) articleLd["articleSection"] = a.Category!;
        var crumbs = new Dictionary<string, object>
        {
            ["@context"] = "https://schema.org",
            ["@type"] = "BreadcrumbList",
            ["itemListElement"] = new object[]
            {
                new Dictionary<string, object> { ["@type"] = "ListItem", ["position"] = 1, ["name"] = "Trang chủ", ["item"] = s.Origin + "/" },
                new Dictionary<string, object> { ["@type"] = "ListItem", ["position"] = 2, ["name"] = "Bài viết", ["item"] = s.Origin + "/bai-viet" },
                new Dictionary<string, object> { ["@type"] = "ListItem", ["position"] = 3, ["name"] = a.Title, ["item"] = url },
            },
        };

        var ld = new List<object> { articleLd, crumbs };
        if (FaqLd(Faq(a.ContentMarkdown)) is { } faqLd) ld.Add(faqLd);
        var sb = new StringBuilder(Head(s, title, desc, url, image, "article", a.Keywords, ld));
        sb.Append("<main class=\"wrap\">\n");
        sb.Append($"<div class=\"crumb\"><a href=\"/\">Trang chủ</a> › <a href=\"/bai-viet\">Bài viết</a>{(string.IsNullOrWhiteSpace(a.Category) ? "" : $" › <a href=\"/bai-viet?chuyen-muc={Uri.EscapeDataString(a.Category!)}\">{E(a.Category)}</a>")}</div>\n");
        sb.Append("<div class=\"layout\">\n<article>\n");
        sb.Append($"<h1>{E(a.Title)}</h1>\n");
        sb.Append("<div class=\"meta\">");
        if (!string.IsNullOrWhiteSpace(a.Category)) sb.Append($"<a class=\"tag\" href=\"/bai-viet?chuyen-muc={Uri.EscapeDataString(a.Category!)}\">{E(a.Category)}</a>");
        sb.Append($"<time datetime=\"{IsoDate(published)}\">{Date(published)}</time>");
        if (modified.Date > published.Date) sb.Append($" · Cập nhật <time datetime=\"{IsoDate(modified)}\">{Date(modified)}</time>");
        sb.Append($" · {ReadingMinutes(a.ContentMarkdown)} phút đọc · {E(a.AuthorName ?? s.Brand)}</div>\n");
        if (!string.IsNullOrWhiteSpace(a.Summary)) sb.Append($"<p class=\"lead\">{E(a.Summary)}</p>\n");
        if (!string.IsNullOrWhiteSpace(a.CoverImageUrl))
            sb.Append($"<img class=\"cover\" src=\"{E(a.CoverImageUrl)}\" alt=\"{E(a.Title)}\" width=\"1200\" height=\"630\">\n");
        sb.Append("<div class=\"content\">\n").Append(body).Append("</div>\n");
        sb.Append(Cta(s));
        sb.Append("</article>\n<aside>\n");
        var toc = headings.Where(h => h.Level == 2).ToList();
        if (toc.Count >= 2)
        {
            sb.Append("<div class=\"box toc\"><h2>Nội dung bài viết</h2><ol>");
            foreach (var h in toc) sb.Append($"<li><a href=\"#{h.Id}\">{E(h.Text)}</a></li>");
            sb.Append("</ol></div>\n");
        }
        if (related.Count > 0)
        {
            sb.Append("<div class=\"box\"><h2>Bài viết liên quan</h2><ul class=\"related\">");
            foreach (var r in related) sb.Append($"<li><a href=\"/bai-viet/{E(r.Slug)}\">{E(r.Title)}</a></li>");
            sb.Append("</ul></div>\n");
        }
        sb.Append($"<div class=\"box\"><h2>{E(s.Brand)}</h2><p style=\"margin:0 0 12px;font-size:15px;color:var(--m)\">{E(s.CtaText)}</p><a class=\"btn\" href=\"/register\">Dùng thử miễn phí</a></div>\n");
        sb.Append("</aside>\n</div>\n</main>\n");
        sb.Append(Footer(s));
        return sb.ToString();
    }

    public static string ListPage(SiteInfo s, IReadOnlyList<SeoArticle> items, int page, int totalPages,
        string? category, IReadOnlyList<string> categories)
    {
        var baseUrl = s.Origin + "/bai-viet";
        string PageUrl(int p) =>
            "/bai-viet" + (category != null || p > 1
                ? "?" + string.Join("&", new[]
                {
                    category == null ? null : "chuyen-muc=" + Uri.EscapeDataString(category),
                    p > 1 ? "trang=" + p : null,
                }.Where(x => x != null))
                : "");
        var canonical = s.Origin + PageUrl(page);
        var title = category == null
            ? (page > 1 ? $"{s.BlogTitle} – Trang {page} | {s.Brand}" : $"{s.BlogTitle} | {s.Brand}")
            : $"{category} – Bài viết{(page > 1 ? $" – Trang {page}" : "")} | {s.Brand}";
        var desc = s.BlogDescription;
        var ld = new Dictionary<string, object>
        {
            ["@context"] = "https://schema.org",
            ["@type"] = "CollectionPage",
            ["name"] = title,
            ["description"] = desc,
            ["url"] = canonical,
            ["inLanguage"] = "vi-VN",
            ["publisher"] = Organization(s),
            ["mainEntity"] = new Dictionary<string, object>
            {
                ["@type"] = "ItemList",
                ["itemListElement"] = items.Select((a, i) => (object)new Dictionary<string, object>
                {
                    ["@type"] = "ListItem",
                    ["position"] = (page - 1) * 12 + i + 1,
                    ["url"] = ArticleUrl(s, a),
                    ["name"] = a.Title,
                }).ToArray(),
            },
        };
        var sb = new StringBuilder(Head(s, title, desc, canonical, s.Origin + s.DefaultImage, "website", null, [ld]));
        sb.Append("<section class=\"hero\"><div class=\"wrap\">");
        sb.Append("<div class=\"crumb\" style=\"margin-top:0\"><a href=\"/\">Trang chủ</a> › Bài viết</div>");
        sb.Append($"<h1>{E(category ?? s.BlogTitle)}</h1><p>{E(desc)}</p>");
        if (categories.Count > 0)
        {
            sb.Append("<div class=\"cats\">");
            sb.Append($"<a class=\"tag\" href=\"/bai-viet\"{(category == null ? " style=\"background:var(--c);color:#fff\"" : "")}>Tất cả</a>");
            foreach (var c in categories)
                sb.Append($"<a class=\"tag\" href=\"/bai-viet?chuyen-muc={Uri.EscapeDataString(c)}\"{(c == category ? " style=\"background:var(--c);color:#fff\"" : "")}>{E(c)}</a>");
            sb.Append("</div>");
        }
        sb.Append("</div></section>\n<main class=\"wrap\">\n");
        if (items.Count == 0)
            sb.Append("<p style=\"margin:40px 0\">Chưa có bài viết.</p>\n");
        else
        {
            sb.Append("<div class=\"cards\">\n");
            foreach (var a in items)
            {
                var img = string.IsNullOrWhiteSpace(a.CoverImageUrl) ? s.DefaultImage : a.CoverImageUrl!;
                sb.Append("<div class=\"card\">");
                sb.Append($"<a href=\"/bai-viet/{E(a.Slug)}\" tabindex=\"-1\"><img src=\"{E(img)}\" alt=\"{E(a.Title)}\" loading=\"lazy\" width=\"1200\" height=\"630\"></a>");
                sb.Append("<div class=\"in\">");
                if (!string.IsNullOrWhiteSpace(a.Category)) sb.Append($"<span><span class=\"tag\">{E(a.Category)}</span></span>");
                sb.Append($"<h2><a href=\"/bai-viet/{E(a.Slug)}\">{E(a.Title)}</a></h2>");
                sb.Append($"<p>{E(Description(a))}</p>");
                sb.Append($"<div class=\"meta\">{Date(a.PublishedAt ?? a.CreatedAt)} · {ReadingMinutes(a.ContentMarkdown)} phút đọc</div>");
                sb.Append("</div></div>\n");
            }
            sb.Append("</div>\n");
        }
        if (totalPages > 1)
        {
            sb.Append("<nav class=\"pager\" aria-label=\"Phân trang\">");
            for (var p = 1; p <= totalPages; p++)
                sb.Append(p == page ? $"<span>{p}</span>" : $"<a href=\"{E(PageUrl(p))}\">{p}</a>");
            sb.Append("</nav>\n");
        }
        sb.Append(Cta(s));
        sb.Append("</main>\n");
        sb.Append(Footer(s));
        return sb.ToString();
    }

    public static string NotFoundPage(SiteInfo s)
    {
        var sb = new StringBuilder(Head(s, $"Không tìm thấy bài viết | {s.Brand}", "Bài viết không tồn tại hoặc đã được gỡ.",
            s.Origin + "/bai-viet", s.Origin + s.DefaultImage, "website", null, [], "noindex, follow"));
        sb.Append("<main class=\"wrap\" style=\"padding:60px 20px\"><h1>Không tìm thấy bài viết</h1><p>Bài viết không tồn tại hoặc đã được gỡ. <a href=\"/bai-viet\">Xem các bài viết khác</a>.</p></main>");
        sb.Append(Footer(s));
        return sb.ToString();
    }

    public static string Sitemap(SiteInfo s, IReadOnlyList<SeoArticle> all)
    {
        var articles = all.Where(a => a.PageType != "feature").ToList();
        var features = all.Where(a => a.PageType == "feature").ToList();
        var sb = new StringBuilder("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n");
        var latest = articles.Count == 0 ? DateTime.UtcNow : articles.Max(a => a.UpdatedAt ?? a.PublishedAt ?? a.CreatedAt);
        void Url(string loc, DateTime? mod, string freq, string prio)
        {
            sb.Append("  <url><loc>").Append(System.Security.SecurityElement.Escape(loc)).Append("</loc>");
            if (mod.HasValue) sb.Append("<lastmod>").Append(mod.Value.ToString("yyyy-MM-dd")).Append("</lastmod>");
            sb.Append("<changefreq>").Append(freq).Append("</changefreq><priority>").Append(prio).Append("</priority></url>\n");
        }
        Url(s.Origin + "/", DateTime.UtcNow, "weekly", "1.0");
        Url(s.Origin + "/bai-viet", latest, "daily", "0.9");
        Url(s.Origin + "/tinh-nang", null, "weekly", "0.9");
        foreach (var f in features)
            Url(FeatureUrl(s, f), f.UpdatedAt ?? f.PublishedAt ?? f.CreatedAt, "monthly", "0.9");
        Url(s.Origin + "/bang-gia", null, "monthly", "0.8");
        Url(s.Origin + "/tai-lieu", null, "monthly", "0.7");
        if (s.Code == "hrm")
        {
            Url(s.Origin + "/lap-dat-may-cham-cong", null, "monthly", "0.8");
            foreach (var p in Provinces) Url($"{s.Origin}/lap-dat-may-cham-cong/{p.Slug}", null, "monthly", "0.7");
        }
        if (s.Code == "hrm") Url(s.Origin + "/guide.html", null, "monthly", "0.7");
        foreach (var a in articles)
            Url(ArticleUrl(s, a), a.UpdatedAt ?? a.PublishedAt ?? a.CreatedAt, "monthly", "0.8");
        Url(s.Origin + s.Privacy, null, "yearly", "0.3");
        if (s.Terms != null) Url(s.Origin + s.Terms, null, "yearly", "0.3");
        sb.Append("</urlset>\n");
        return sb.ToString();
    }

    public static string Robots(SiteInfo s) => $"""
User-agent: *
Allow: /
Allow: /bai-viet
Allow: /tinh-nang
Allow: /bang-gia
Allow: /tai-lieu
Allow: /lap-dat-may-cham-cong
Allow: /images/
Allow: /icons/

# App SPA — không index (tránh trùng trang chủ SEO)
Disallow: /index.html
Disallow: /home.html
Disallow: /api/
Disallow: /hubs/
Disallow: /iclock/
Disallow: /admin
Disallow: /login-app
Disallow: /register
Disallow: /landing
Disallow: /main.dart.js
Disallow: /flutter.js
Disallow: /flutter_bootstrap.js
Disallow: /canvaskit/
Disallow: /o/
Disallow: /tai-lieu/tai/

Sitemap: {s.Origin}/sitemap.xml
""";
}
