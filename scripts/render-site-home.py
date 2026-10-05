"""
Dựng trang chủ SEO riêng cho từng tên miền ngay lúc deploy (bot không chạy JavaScript vẫn thấy đúng site).

home.html dùng chung cho sboxhrm.com (HRM) và sboxpos.com (POS); trước đây meta / canonical cố định là POS và
JavaScript mới đổi sang HRM → Google coi sboxhrm.com là bản trùng của sboxpos.com. Script này:
  - đặt <html data-site>, meta / canonical / Open Graph / Twitter / JSON-LD đúng site (giá trị khớp site-seo.js);
  - bỏ khối của site kia (mỗi trang chỉ còn một H1);
  - thêm liên kết «Bài viết» + khối «Bài viết mới» (/bai-viet, dựng phía server);
  - menu «Tính năng» / «Gói dịch vụ» trỏ /tinh-nang, /bang-gia; khối «Giải pháp» liên kết các trang tính năng
    và khối «Tài liệu miễn phí» (/tai-lieu) — liên kết nội bộ bot đọc được;
  - FAQ hiển thị tĩnh + JSON-LD FAQPage khớp đúng nội dung hiển thị;
  - ghi robots.txt + sitemap.xml tĩnh đúng site (dự phòng khi nginx chưa trỏ về API).

Dùng: python scripts/render-site-home.py --site hrm|pos --web-dir flutter_client/build/web
"""
import argparse
import json
import pathlib
import re
import sys

from bs4 import BeautifulSoup

SITES = {
    "hrm": {
        "origin": "https://sboxhrm.com",
        "brand": "SBOX HRM",
        # Giữ khớp homeSeo() trong flutter_client/web/site-seo.js (JS ghi đè meta lúc chạy).
        "title": "Phần mềm chấm công, tính lương & quản lý nhân sự | SBOX HRM",
        "description": "Phần mềm chấm công khuôn mặt, GPS, WiFi và máy ZKTeco; xếp ca, tính lương, BHXH, thuế TNCN tự động cho nhà hàng, chuỗi cửa hàng, nhà máy. Dùng thử miễn phí!",
        "keywords": "phần mềm chấm công, phần mềm tính lương, phần mềm quản lý nhân sự, phần mềm HRM, phần mềm chấm công miễn phí, app chấm công, chấm công khuôn mặt, chấm công qua điện thoại, chấm công GPS, chấm công WiFi, chấm công online, chấm công ZKTeco, máy chấm công khuôn mặt, máy chấm công vân tay, lắp đặt máy chấm công, phần mềm bảng lương, lương sản phẩm, lương theo ca, quản lý ca làm việc, nghỉ phép online, BHXH, thuế TNCN, phần mềm nhân sự nhà hàng, chuỗi cửa hàng, nhà máy, doanh nghiệp vừa và nhỏ, HRM Việt Nam, SBOX HRM, ADMS",
        "og_image": "https://sboxhrm.com/images/landing/screenshot-01.jpg",
        "og_image_alt": "Giao diện SBOX HRM – phần mềm quản lý nhân sự và chấm công",
        "theme": "#0C56D0",
        "articles_title": "Kiến thức chấm công & tính lương",
        "articles_sub": "Hướng dẫn chấm công, tính lương, bảo hiểm và quản lý nhân sự cho doanh nghiệp Việt Nam.",
        "solutions_title": "Giải pháp theo nhu cầu",
        "solutions_sub": "Chọn đúng phần bạn cần — mọi tính năng dùng chung một dữ liệu nhân viên, ca và bảng công.",
        # Khớp các trang type: feature trong src/ZKTecoADMS.Api/Seo/Seed/hrm-tn-*.md
        "solutions": [
            ("phan-mem-cham-cong-zkteco", "Chấm công máy ZKTeco qua Internet", "Máy ZKTeco tự đẩy dữ liệu qua ADMS, không cần IP tĩnh, mất mạng gửi bù."),
            ("cham-cong-khuon-mat-dien-thoai", "Chấm công khuôn mặt trên điện thoại", "Khuôn mặt + GPS + WiFi + khóa thiết bị — chống chấm hộ, không cần mua máy."),
            ("phan-mem-tinh-luong", "Tính lương tự động", "Ngày công, tăng ca, ngày lễ, phụ cấp, BHXH, thuế TNCN — phiếu lương trên app."),
            ("quan-ly-ca-lam-viec", "Xếp ca, quản lý ca làm việc", "Ca xoay, ca gãy, ca đêm; nhân viên đăng ký và đổi ca trên điện thoại."),
            ("quan-ly-nghi-phep-tang-ca", "Nghỉ phép, tăng ca online", "Đơn từ trên app, duyệt nhanh, tự trừ phép năm, tự vào bảng lương."),
            ("phan-mem-quan-ly-nhan-su", "Quản lý nhân sự", "Hồ sơ, phòng ban, sơ đồ tổ chức, tài liệu, tài sản cấp phát."),
        ],
        "resources_title": "Tài liệu nhân sự miễn phí",
        "resources": ["Mẫu bảng lương Excel 2026 tự tính BHXH, thuế TNCN", "Mẫu bảng chấm công theo tháng", "Checklist tiếp nhận nhân viên mới"],
        # Bổ sung vào FAQ trang chủ (FAQPage dựng lại từ đúng danh sách hiển thị).
        "faq_extra": [
            ("Phần mềm có tương thích với tất cả các dòng máy chấm công ZKTeco không?",
             "SBOX HRM kết nối các máy ZKTeco có chức năng ADMS / Push / Cloud Server (phần lớn máy vân tay, khuôn mặt đời mới). Máy đời cũ không có ADMS cần chuyển sang chấm công điện thoại; một số dòng firmware rút gọn chỉ hỗ trợ một phần lệnh từ xa. Gửi model máy qua Zalo 0973 024 042 để được kiểm tra miễn phí."),
            ("Mất mạng Internet thì dữ liệu chấm công có bị mất không?",
             "Không. Máy chấm công vẫn lưu bản ghi khi mất mạng và tự gửi bù lên SBOX khi có mạng lại."),
            ("Chấm công bằng điện thoại có chống được chấm công hộ không?",
             "Có. Mỗi lần chấm được xác minh khuôn mặt, vị trí GPS hoặc WiFi cửa hàng và đúng điện thoại đã được quản lý duyệt; ảnh chấm công được lưu để đối chiếu."),
            ("Phần mềm chấm công SBOX HRM có miễn phí không?",
             "Đăng ký là dùng thử miễn phí ngay, không cần thẻ thanh toán — chấm công, xếp ca và bảng lương trên dữ liệu thật. Khi dùng chính thức, chọn gói theo số nhân viên tại trang Bảng giá."),
            ("Có chấm công bằng GPS, WiFi trên điện thoại không cần máy chấm công không?",
             "Có. App chấm công SBOX HRM (Android, iOS) cho phép chấm công online bằng khuôn mặt kèm vị trí GPS hoặc WiFi của chi nhánh — phù hợp cửa hàng nhỏ, nhân viên thị trường, công trình."),
            ("Tính được lương theo ca, lương sản phẩm và tăng ca không?",
             "Được. Bảng lương tự tính theo ngày công, giờ công, lương theo ca, lương sản phẩm theo sản lượng, tăng ca, ngày lễ, phụ cấp, thưởng phạt, BHXH và thuế TNCN."),
            ("Quản lý chuỗi nhiều chi nhánh, cửa hàng được không?",
             "Được. Mỗi chi nhánh có ca, vị trí chấm công và quản lý riêng; chủ doanh nghiệp xem bảng công, bảng lương tập trung của cả chuỗi nhà hàng, cửa hàng hoặc nhà máy."),
            ("Có xuất bảng công, bảng lương ra Excel không?",
             "Có. Bảng công, bảng lương, phiếu lương và các báo cáo đều xuất được Excel để gửi kế toán hoặc lưu trữ."),
        ],
    },
    "pos": {
        "origin": "https://sboxpos.com",
        "brand": "SBOX POS",
        "title": "Phần mềm bán hàng POS cho quán cafe, nhà hàng | SBOX POS",
        "description": "Phần mềm bán hàng SBOX POS: sơ đồ bàn, gọi món QR, phiếu bếp, quản lý kho, giá vốn, báo cáo doanh thu realtime. Dùng thử miễn phí, không cần thẻ — đăng ký ngay!",
        "keywords": "phần mềm POS, phần mềm bán hàng, POS đa ngành, POS F&B, POS nhà hàng, POS cà phê, POS bán lẻ, quản lý cửa hàng, sơ đồ bàn, in hóa đơn nhiệt, phiếu bếp, quản lý kho, báo cáo doanh thu, phần mềm quản lý siêu thị mini, phần mềm khuyến mãi, chương trình khuyến mãi, mua X tặng Y, in tem mã vạch, tem cân điện tử, bán hàng theo cân, quản lý hạn sử dụng, cảnh báo tồn kho, bảng giá sỉ lẻ, SBOX POS, máy POS Android",
        "og_image": "https://sboxpos.com/images/landing/pos/sbox-pos-og.jpg?v=3",
        "og_image_alt": "SBOX POS – phần mềm bán hàng trên máy POS, tablet và web",
        "theme": "#2E7D32",
        "articles_title": "Kiến thức bán hàng & quản lý cửa hàng",
        "articles_sub": "Kinh nghiệm vận hành quán cà phê, nhà hàng, cửa hàng bán lẻ: kho, giá vốn, sơ đồ bàn, khuyến mãi.",
        "solutions_title": "Giải pháp theo ngành",
        "solutions_sub": "SBOX POS có sẵn nghiệp vụ riêng cho từng mô hình kinh doanh.",
        # Khớp các trang type: feature trong src/ZKTecoADMS.Api/Seo/Seed/pos-tn-*.md
        "solutions": [
            ("phan-mem-quan-ly-quan-cafe", "Quán cà phê, trà sữa", "Order nhanh, size – topping, phiếu pha chế, định lượng và lãi từng ly."),
            ("phan-mem-quan-ly-nha-hang", "Nhà hàng, quán ăn", "Sơ đồ bàn, order tại bàn, phiếu bếp / màn hình bếp, đặt bàn, tách gộp bill."),
            ("phan-mem-ban-hang-cua-hang-ban-le", "Cửa hàng bán lẻ, tạp hóa", "Mã vạch, tồn kho, giá vốn, nhà cung cấp, công nợ, tích điểm, bảo hành."),
            ("phan-mem-quan-ly-spa-salon", "Spa, salon, phòng gym", "Lịch hẹn theo kỹ thuật viên, gói liệu trình trừ buổi, hoa hồng nhân viên."),
            ("goi-mon-qr-tai-ban", "Gọi món QR tại bàn", "Khách quét QR xem menu và gọi món, đơn về thẳng thu ngân và bếp."),
            ("phan-mem-quan-ly-kho-hang", "Quản lý kho hàng", "Nhập – xuất – tồn, giá vốn bình quân, kiểm kê, chuyển kho chi nhánh."),
        ],
        "resources_title": "Tài liệu quản lý cửa hàng miễn phí",
        "resources": ["Mẫu quản lý kho nhập – xuất – tồn", "Bảng định lượng & giá vốn món", "Biên bản chốt ca thu ngân"],
        # FAQ tĩnh của POS (trước đây JS mới chèn — bot không thấy). Giữ khớp POS_FAQ trong home.html.
        "faq_static": [
            ("SBOX POS là phần mềm gì?", "SBOX POS là phần mềm bán hàng tại quầy: sơ đồ bàn, in hóa đơn/phiếu bếp, quản lý kho và báo cáo doanh thu — chạy trên web, máy POS Android (Sunmi) và tablet."),
            ("Có in hóa đơn nhiệt và phiếu bếp không?", "Có. In qua máy in LAN/USB, Print Agent Windows hoặc máy POS Sunmi. Hóa đơn thu ngân và phiếu chế biến bếp tách riêng."),
            ("Phù hợp ngành nào?", "SBOX POS là phần mềm đa ngành: nhà hàng, quán cà phê, trà sữa, karaoke, bán lẻ / tạp hóa, thời trang, siêu thị mini, spa / salon, nhà thuốc và chuỗi cửa hàng — sơ đồ bàn hoặc bán nhanh tại quầy."),
            ("Có quản lý kho không?", "Có. Nhập xuất tồn realtime, gắn với đơn bán, theo dõi lô/HSD và báo cáo tồn theo cửa hàng."),
            ("Có tạo chương trình khuyến mãi tự động không?", "Có. Giảm theo khung giờ (giờ vàng rau, cá), mua X tặng Y, mua nhiều giảm theo bậc, đồng giá combo, giảm theo tổng hóa đơn, mua kèm giá ưu đãi và hàng cận hạn tự giảm — máy bán tự áp chương trình có lợi nhất và có báo cáo hiệu quả từng chương trình."),
            ("Bán hàng cân như rau, thịt có in tem được không?", "Được. Nhập khối lượng từng gói (vd 0,45 kg thịt), hệ thống tính tiền theo đơn giá/kg và in tem mã cân EAN-13 kèm hạn dùng; quét tem ở quầy ra đúng hàng và khối lượng. Hàng có sẵn mã vạch in tem EAN-13 trực tiếp."),
            ("Có cảnh báo hàng sắp hết hạn và tồn kho thấp không?", "Có. Theo dõi lô / hạn sử dụng khi nhập hàng, không cho bán lô đã quá hạn, gửi thông báo mỗi sáng về hàng sắp hết hạn và hàng dưới tồn tối thiểu, kèm danh sách gợi ý nhập hàng."),
            ("Có gọi món bằng mã QR tại bàn không?", "Có. Mỗi bàn một mã QR, khách quét để xem thực đơn và gọi món; đơn hiện ngay trên máy thu ngân và bếp, có thể bật bước xác nhận đơn."),
            ("Có xuất hóa đơn điện tử không?", "Có. SBOX POS kết nối nhà cung cấp hóa đơn điện tử để xuất hóa đơn ngay từ đơn bán, phù hợp hộ kinh doanh và doanh nghiệp."),
            ("Có quản lý nhiều chi nhánh không?", "Có. Mỗi chi nhánh có thực đơn, bảng giá, kho và nhân viên riêng; chủ cửa hàng xem báo cáo toàn chuỗi hoặc từng điểm."),
            ("Có kèm chấm công nhân viên không?", "Có thể bật module chấm công, ca làm và tính lương cho thu ngân / phục vụ trên cùng hệ thống."),
            ("Có dùng thử miễn phí không?", "Có. Đăng ký tại sboxpos.com hoặc tải APK SBOX POS cho máy Android / máy POS, không cần thẻ thanh toán."),
        ],
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

SOLUTIONS_SECTION = """
<section id="giai-phap" class="site-solutions" style="padding:64px 20px;background:#F8FAFC">
  <div style="max-width:1120px;margin:0 auto">
    <h2 class="section-title">{title}</h2>
    <p style="color:#475569;margin:6px 0 24px">{sub}</p>
    <div class="sol-grid" style="display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:16px">{cards}</div>
    <p style="margin-top:22px"><a href="/tinh-nang" style="font-weight:700">Xem tất cả tính năng →</a> &nbsp;·&nbsp; <a href="/bang-gia" style="font-weight:700">Bảng giá →</a></p>
    <div style="margin-top:34px;border-radius:16px;padding:22px 24px;background:#fff;border:1px solid #e2e8f0;display:flex;flex-wrap:wrap;gap:16px;align-items:center;justify-content:space-between">
      <div><strong style="font-size:18px">{res_title}</strong><div style="color:#475569;margin-top:4px">{res_items}</div></div>
      <a href="/tai-lieu" style="background:{color};color:#fff;padding:11px 20px;border-radius:10px;font-weight:700;text-decoration:none">Tải miễn phí</a>
    </div>
  </div>
</section>
"""

LOCAL_SECTION = """
<section id="lap-dat" class="site-local" style="padding:56px 20px;background:#fff">
  <div style="max-width:1120px;margin:0 auto">
    <h2 class="section-title">Lắp đặt máy chấm công vân tay, khuôn mặt toàn quốc</h2>
    <p style="color:#475569;margin:6px 0 8px">Cung cấp máy chấm công ZKTeco giá tốt, <strong>miễn phí lắp đặt</strong> tận nơi và <strong>tặng phần mềm chấm công</strong> SBOX HRM khi mua máy — hoặc chấm công qua điện thoại không cần mua máy.</p>
    <p style="margin:0 0 18px"><a href="/lap-dat-may-cham-cong" style="font-weight:700">Xem dịch vụ lắp đặt & nhận báo giá →</a></p>
    <details class="local-more desk-open"><summary>Xem 34 tỉnh, thành có lắp đặt tận nơi</summary>
    {groups}
    </details>
  </div>
</section>
"""

SOLUTION_CARD = (
    '<a href="/tinh-nang/{slug}" style="display:block;border:1px solid #e2e8f0;border-radius:14px;padding:18px 20px;'
    'background:#fff;text-decoration:none;color:#0f172a"><h3 style="margin:0 0 6px;font-size:18px;color:{color}">{title}</h3>'
    '<span style="font-size:15px;color:#475569;line-height:1.5">{desc}</span></a>'
)


ROBOTS = """User-agent: *
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

Sitemap: {origin}/sitemap.xml
"""


def sitemap(site, cfg):
    o = cfg["origin"]
    urls = [(o + "/", "weekly", "1.0"), (o + "/bai-viet", "daily", "0.9"), (o + "/tinh-nang", "weekly", "0.9")]
    urls += [(o + "/tinh-nang/" + slug, "monthly", "0.9") for slug, _, _ in cfg["solutions"]]
    urls += [(o + "/bang-gia", "monthly", "0.8"), (o + "/tai-lieu", "monthly", "0.7")]
    if site == "hrm":
        urls += [(o + "/lap-dat-may-cham-cong", "monthly", "0.8")]
        urls += [(o + "/lap-dat-may-cham-cong/" + slug, "monthly", "0.7") for slug, _, _ in provinces()]
    if site == "hrm":
        urls += [(o + "/guide.html", "monthly", "0.7"), (o + "/privacy-policy.html", "yearly", "0.3")]
    else:
        urls += [(o + "/privacy-policy-pos.html", "yearly", "0.3"), (o + "/terms-pos.html", "yearly", "0.3")]
    rows = "\n".join(f"  <url><loc>{u}</loc><changefreq>{f}</changefreq><priority>{p}</priority></url>" for u, f, p in urls)
    return f'<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n{rows}\n</urlset>\n'


def provinces():
    """Đọc danh sách tỉnh từ SeoLocal.cs (một nguồn duy nhất cho trang /lap-dat-may-cham-cong)."""
    cs = pathlib.Path(__file__).resolve().parent.parent / "src" / "ZKTecoADMS.Api" / "Seo" / "SeoLocal.cs"
    if not cs.exists():
        return []
    return re.findall(r'new\("([a-z0-9-]+)", "([^"]+)", "([^"]+)", \[', cs.read_text(encoding="utf-8"))


def esc(t):
    return (t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;"))


def faq_ld(items):
    return {"@type": "FAQPage", "mainEntity": [
        {"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in items]}


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

    # FAQ hiển thị tĩnh (bot đọc được) + FAQPage khớp đúng danh sách hiển thị.
    faq_list = soup.find(id="faq-list")
    if faq_list is not None:
        if site == "pos":
            faq_list.clear()
            for i, (q, a) in enumerate(cfg["faq_static"]):
                faq_list.append(BeautifulSoup(
                    f'<details{" open" if i == 0 else ""}><summary>{esc(q)}</summary><p>{esc(a)}</p></details>', "html.parser"))
        else:
            for q, a in cfg["faq_extra"]:
                faq_list.append(BeautifulSoup(f"<details><summary>{esc(q)}</summary><p>{esc(a)}</p></details>", "html.parser"))
    faq_items = [(d.summary.get_text(" ", strip=True), d.p.get_text(" ", strip=True))
                 for d in (faq_list.find_all("details") if faq_list is not None else []) if d.summary and d.p]

    ld = soup.find("script", attrs={"type": "application/ld+json"})
    if ld is not None:
        graph = pos_json_ld(cfg) if site == "pos" else json.loads(ld.string)
        nodes = [n for n in graph.get("@graph", []) if n.get("@type") != "FAQPage"]
        if faq_items:
            node = faq_ld(faq_items)
            node["@id"] = o + "/#faq"
            nodes.append(node)
        graph["@graph"] = nodes
        ld.string = json.dumps(graph, ensure_ascii=False, indent=2)

    # POS: JS cũ chèn lại FAQ ngắn hơn → bỏ để giữ đúng danh sách tĩnh (khớp FAQPage).
    if site == "pos":
        for sc in soup.find_all("script"):
            if sc.string and "applyFaq(POS_FAQ);" in sc.string:
                sc.string = sc.string.replace("applyFaq(POS_FAQ);", "/* FAQ POS dựng tĩnh lúc deploy */")

    # Bỏ khối của site kia → mỗi trang một H1, nội dung tĩnh đúng chủ đề.
    if site == "hrm":
        for el in soup.select(".site-pos-feature, .pos-hero-banner, .logo-pos"):
            el.decompose()
    else:
        for el in soup.select(".site-hrm-nav, .hero-inner, .stats, .logo-hrm"):
            el.decompose()

    # Liên kết «Bài viết» (bot đọc được) + khối bài viết mới.
    # Menu trỏ sang trang SEO riêng (bot theo được liên kết nội bộ).
    for a in soup.select('ul.nav-links a[href="#features"], a.nav-drawer-link[href="#features"]'):
        a["href"] = "/tinh-nang"
    for a in soup.select('ul.nav-links a[href="#pricing"], a.nav-drawer-link[href="#pricing"]'):
        a["href"] = "/bang-gia"
    for ul in soup.select("ul.nav-links"):
        li = soup.new_tag("li")
        a = soup.new_tag("a", href="/bai-viet")
        a.string = "Bài viết"
        li.append(a)
        li2 = soup.new_tag("li")
        a2 = soup.new_tag("a", href="/tai-lieu")
        a2.string = "Tài liệu"
        li2.append(a2)
        contact = ul.find("a", href="#contact")
        if contact:
            contact.parent.insert_before(li)
            contact.parent.insert_before(li2)
        else:
            ul.append(li)
            ul.append(li2)
    for actions in soup.select("div.nav-drawer-actions"):
        for href, text in (("/bai-viet", "Bài viết"), ("/tai-lieu", "Tài liệu miễn phí")):
            a = soup.new_tag("a", href=href, attrs={"class": "nav-drawer-link"})
            a.string = text
            actions.insert_before(a)
    faq = soup.find(id="faq")
    section = BeautifulSoup(ARTICLES_SECTION.format(
        title=cfg["articles_title"], sub=cfg["articles_sub"], color=cfg["theme"]), "html.parser")
    if faq is not None:
        faq.insert_before(section)

    cards = "".join(SOLUTION_CARD.format(slug=sl, title=esc(t), desc=esc(d), color=cfg["theme"]) for sl, t, d in cfg["solutions"])
    solutions = BeautifulSoup(SOLUTIONS_SECTION.format(
        title=cfg["solutions_title"], sub=cfg["solutions_sub"], cards=cards, color=cfg["theme"],
        res_title=cfg["resources_title"], res_items=" · ".join(esc(x) for x in cfg["resources"])), "html.parser")
    features = soup.find(id="features")
    if features is not None:
        features.insert_after(solutions)
    elif faq is not None:
        faq.insert_before(solutions)

    # HRM: liên kết tới 34 trang lắp đặt máy chấm công theo tỉnh (bot đọc được).
    prov = provinces() if site == "hrm" else []
    if prov:
        regions = {}
        for slug, name, region in prov:
            regions.setdefault(region, []).append((slug, name))
        groups = "".join(
            f'<p style="margin:0 0 10px;line-height:1.9"><strong>{esc(r)}:</strong> '
            + " · ".join(f'<a href="/lap-dat-may-cham-cong/{sl}" style="color:#334155">Máy chấm công {esc(n)}</a>' for sl, n in items)
            + "</p>"
            for r, items in regions.items())
        local = BeautifulSoup(LOCAL_SECTION.format(groups=groups), "html.parser")
        anchor = soup.find(id="giai-phap")
        if anchor is not None:
            anchor.insert_after(local)

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
