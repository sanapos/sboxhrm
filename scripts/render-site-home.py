"""
Dựng trang chủ SEO riêng cho từng tên miền ngay lúc deploy (bot không chạy JavaScript vẫn thấy đúng site).

home.html dùng chung cho sboxhrm.com (HRM) và sboxpos.com (POS); trước đây meta / canonical cố định là POS và
JavaScript mới đổi sang HRM → Google coi sboxhrm.com là bản trùng của sboxpos.com. Script này:
  - đặt <html data-site>, meta / canonical / Open Graph / Twitter / JSON-LD đúng site (giá trị khớp site-seo.js);
  - bỏ khối của site kia (mỗi trang chỉ còn một H1);
  - thêm liên kết «Bài viết» + khối «Bài viết mới» (/bai-viet, dựng phía server);
  - ghi robots.txt + sitemap.xml tĩnh đúng site (dự phòng khi nginx chưa trỏ về API).

Dùng: python scripts/render-site-home.py --site hrm|pos --web-dir flutter_client/build/web
"""
import argparse
import json
import pathlib
import sys

from bs4 import BeautifulSoup

SITES = {
    "hrm": {
        "origin": "https://sboxhrm.com",
        "brand": "SBOX HRM",
        "title": "Phần mềm chấm công & tính lương ZKTeco | SBOX HRM",
        "description": "Phần mềm chấm công khuôn mặt AI, kết nối máy ZKTeco ADMS, quản lý ca và bảng lương tự động cho doanh nghiệp Việt Nam. Dùng thử miễn phí trên web & Android — SBOX HRM.",
        "keywords": "phần mềm chấm công, phần mềm tính lương, chấm công khuôn mặt, chấm công ZKTeco, phần mềm bảng lương, quản lý ca làm việc, phần mềm quản lý nhân sự, HRM Việt Nam, SBOX HRM, ADMS",
        "og_image": "https://sboxhrm.com/images/landing/screenshot-01.jpg",
        "og_image_alt": "Giao diện SBOX HRM – phần mềm quản lý nhân sự và chấm công",
        "theme": "#0C56D0",
        "articles_title": "Kiến thức chấm công & tính lương",
        "articles_sub": "Hướng dẫn chấm công, tính lương, bảo hiểm và quản lý nhân sự cho doanh nghiệp Việt Nam.",
    },
    "pos": {
        "origin": "https://sboxpos.com",
        "brand": "SBOX POS",
        "title": "Phần mềm POS bán hàng, quản lý cửa hàng & kho | SBOX POS",
        "description": "Phần mềm POS bán hàng SBOX: bán tại quầy, sơ đồ bàn, in hóa đơn nhiệt và phiếu bếp, quản lý kho, báo cáo doanh thu realtime. POS đa ngành — dùng thử miễn phí trên web và máy POS Android.",
        "keywords": "phần mềm POS, phần mềm bán hàng, POS đa ngành, POS F&B, POS nhà hàng, POS cà phê, POS bán lẻ, quản lý cửa hàng, sơ đồ bàn, in hóa đơn nhiệt, phiếu bếp, quản lý kho, báo cáo doanh thu, SBOX POS, máy POS Android",
        "og_image": "https://sboxpos.com/images/landing/pos/sbox-pos-og.jpg?v=3",
        "og_image_alt": "SBOX POS – phần mềm bán hàng trên máy POS, tablet và web",
        "theme": "#2E7D32",
        "articles_title": "Kiến thức bán hàng & quản lý cửa hàng",
        "articles_sub": "Kinh nghiệm vận hành quán cà phê, nhà hàng, cửa hàng bán lẻ: kho, giá vốn, sơ đồ bàn, khuyến mãi.",
    },
}


def set_attr(soup, selector, attr, value):
    for el in soup.select(selector):
        el[attr] = value


def pos_json_ld(cfg):
    o = cfg["origin"]
    return {
        "@context": "https://schema.org",
        "@graph": [
            {"@type": "WebSite", "@id": o + "/#website", "url": o + "/", "name": cfg["brand"], "inLanguage": "vi-VN",
             "publisher": {"@id": o + "/#organization"}},
            {"@type": "Organization", "@id": o + "/#organization", "name": cfg["brand"], "url": o + "/",
             "logo": {"@type": "ImageObject", "url": o + "/images/landing/sbox-pos-logo.png"},
             "contactPoint": {"@type": "ContactPoint", "telephone": "+84973024042", "contactType": "customer support",
                              "areaServed": "VN", "availableLanguage": ["vi"]}},
            {"@type": "SoftwareApplication", "name": cfg["brand"], "applicationCategory": "BusinessApplication",
             "operatingSystem": "Web, Android, iOS", "url": o + "/", "description": cfg["description"],
             "image": cfg["og_image"],
             "offers": {"@type": "Offer", "price": "0", "priceCurrency": "VND", "description": "Dùng thử miễn phí"}},
        ],
    }


ARTICLES_SECTION = """
<section id="articles" class="site-articles" style="padding:64px 20px;background:#fff">
  <div style="max-width:1120px;margin:0 auto">
    <h2 class="section-title">{title}</h2>
    <p style="color:#475569;margin:6px 0 24px">{sub}</p>
    <div id="articles-grid" style="display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:20px"></div>
    <p style="margin-top:22px"><a href="/bai-viet" style="font-weight:700">Xem tất cả bài viết →</a></p>
  </div>
</section>
<script>
(function () {{
  fetch('/api/public/articles?take=6').then(function (r) {{ return r.json(); }}).then(function (res) {{
    var grid = document.getElementById('articles-grid');
    if (!grid || !res || !res.data || !res.data.length) {{ var s = document.getElementById('articles'); if (s && grid && !grid.children.length) s.style.display = res && res.data && res.data.length ? '' : 'none'; return; }}
    function esc(t) {{ return String(t || '').replace(/[&<>"]/g, function (c) {{ return {{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}}[c]; }}); }}
    grid.innerHTML = res.data.map(function (a) {{
      return '<a href="' + esc(a.url) + '" style="display:flex;flex-direction:column;border:1px solid #e2e8f0;border-radius:14px;overflow:hidden;text-decoration:none;color:#0f172a;background:#fff">' +
        '<img src="' + esc(a.coverImageUrl) + '" alt="' + esc(a.title) + '" loading="lazy" style="width:100%;aspect-ratio:1200/630;object-fit:cover;background:#f1f5f9">' +
        '<span style="padding:14px 16px 16px;display:flex;flex-direction:column;gap:6px">' +
        (a.category ? '<span style="font-size:12px;font-weight:700;color:{color}">' + esc(a.category) + '</span>' : '') +
        '<strong style="font-size:17px;line-height:1.35">' + esc(a.title) + '</strong>' +
        '<span style="font-size:14px;color:#475569;line-height:1.5">' + esc(a.description) + '</span></span></a>';
    }}).join('');
  }}).catch(function () {{}});
}})();
</script>
"""

ROBOTS = """User-agent: *
Allow: /
Allow: /bai-viet
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

Sitemap: {origin}/sitemap.xml
"""


def sitemap(site, cfg):
    o = cfg["origin"]
    urls = [(o + "/", "weekly", "1.0"), (o + "/bai-viet", "daily", "0.9")]
    if site == "hrm":
        urls += [(o + "/guide.html", "monthly", "0.7"), (o + "/privacy-policy.html", "yearly", "0.3")]
    else:
        urls += [(o + "/privacy-policy-pos.html", "yearly", "0.3"), (o + "/terms-pos.html", "yearly", "0.3")]
    rows = "\n".join(f"  <url><loc>{u}</loc><changefreq>{f}</changefreq><priority>{p}</priority></url>" for u, f, p in urls)
    return f'<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n{rows}\n</urlset>\n'


def render(site, web_dir):
    cfg = SITES[site]
    home = web_dir / "home.html"
    soup = BeautifulSoup(home.read_text(encoding="utf-8"), "html.parser")
    o = cfg["origin"]

    soup.html["data-site"] = site
    if soup.title:
        soup.title.string = cfg["title"]
    set_attr(soup, 'meta[name="description"]', "content", cfg["description"])
    set_attr(soup, 'meta[name="keywords"]', "content", cfg["keywords"])
    set_attr(soup, 'meta[name="author"]', "content", cfg["brand"])
    set_attr(soup, 'link[rel="canonical"]', "href", o + "/")
    set_attr(soup, 'link[rel="alternate"][hreflang]', "href", o + "/")
    set_attr(soup, 'meta[property="og:site_name"]', "content", cfg["brand"])
    set_attr(soup, 'meta[property="og:url"]', "content", o + "/")
    set_attr(soup, 'meta[property="og:title"]', "content", cfg["title"])
    set_attr(soup, 'meta[property="og:description"]', "content", cfg["description"])
    set_attr(soup, 'meta[property="og:image"]', "content", cfg["og_image"])
    set_attr(soup, 'meta[property="og:image:secure_url"]', "content", cfg["og_image"])
    set_attr(soup, 'meta[property="og:image:alt"]', "content", cfg["og_image_alt"])
    set_attr(soup, 'meta[name="twitter:title"]', "content", cfg["title"])
    set_attr(soup, 'meta[name="twitter:description"]', "content", cfg["description"])
    set_attr(soup, 'meta[name="twitter:image"]', "content", cfg["og_image"])
    set_attr(soup, 'meta[itemprop="name"]', "content", cfg["title"])
    set_attr(soup, 'meta[itemprop="description"]', "content", cfg["description"])
    set_attr(soup, 'meta[itemprop="image"]', "content", cfg["og_image"])
    set_attr(soup, 'meta[name="theme-color"]', "content", cfg["theme"])
    if site == "hrm":
        # Ảnh og của HRM là JPG khác kích thước — bỏ khai báo cứng 1200×630 / jpeg của POS.
        for p in ("og:image:width", "og:image:height"):
            for el in soup.select(f'meta[property="{p}"]'):
                el.decompose()

    if site == "pos":
        ld = soup.find("script", attrs={"type": "application/ld+json"})
        if ld is not None:
            ld.string = json.dumps(pos_json_ld(cfg), ensure_ascii=False, indent=2)

    # Bỏ khối của site kia → mỗi trang một H1, nội dung tĩnh đúng chủ đề.
    if site == "hrm":
        for el in soup.select(".site-pos-feature, .pos-hero-banner, .logo-pos"):
            el.decompose()
    else:
        for el in soup.select(".site-hrm-nav, .hero-inner, .stats, .logo-hrm"):
            el.decompose()

    # Liên kết «Bài viết» (bot đọc được) + khối bài viết mới.
    for ul in soup.select("ul.nav-links"):
        li = soup.new_tag("li")
        a = soup.new_tag("a", href="/bai-viet")
        a.string = "Bài viết"
        li.append(a)
        contact = ul.find("a", href="#contact")
        (contact.parent.insert_before(li) if contact else ul.append(li))
    for actions in soup.select("div.nav-drawer-actions"):
        a = soup.new_tag("a", href="/bai-viet", attrs={"class": "nav-drawer-link"})
        a.string = "Bài viết"
        actions.insert_before(a)
    faq = soup.find(id="faq")
    section = BeautifulSoup(ARTICLES_SECTION.format(
        title=cfg["articles_title"], sub=cfg["articles_sub"], color=cfg["theme"]), "html.parser")
    if faq is not None:
        faq.insert_before(section)

    h1 = [h.get_text(" ", strip=True) for h in soup.find_all("h1")]
    home.write_text(str(soup), encoding="utf-8")
    (web_dir / "robots.txt").write_text(ROBOTS.format(origin=o), encoding="utf-8")
    (web_dir / "sitemap.xml").write_text(sitemap(site, cfg), encoding="utf-8")
    print(f"render-site-home: site={site} h1={h1}")
    if len(h1) != 1:
        print("render-site-home: CẢNH BÁO — trang chủ nên có đúng 1 thẻ H1", file=sys.stderr)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--site", required=True, choices=["hrm", "pos"])
    ap.add_argument("--web-dir", required=True)
    args = ap.parse_args()
    render(args.site, pathlib.Path(args.web_dir))
