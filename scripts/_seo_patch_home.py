# -*- coding: utf-8 -*-
from pathlib import Path

p = Path("flutter_client/web/home.html")
t = p.read_text(encoding="utf-8")

t = t.replace(
    "<title>SBOX HRM – Phần mềm quản lý nhân sự thông minh</title>",
    "<title>SBOX HRM – Phần mềm quản lý nhân sự, chấm công khuôn mặt &amp; bảng lương</title>",
)
t = t.replace(
    'content="SBOX HRM – Giải pháp quản lý nhân sự toàn diện: chấm công khuôn mặt, lịch ca, bảng lương, hồ sơ nhân viên trên nền tảng di động và web."',
    'content="SBOX HRM – Phần mềm quản lý nhân sự cho doanh nghiệp Việt Nam: chấm công khuôn mặt AI, ZKTeco ADMS, quản lý ca, bảng lương tự động, báo cáo realtime. Dùng thử miễn phí trên web và Android."',
)
t = t.replace(
    'content="SBOX HRM, phần mềm nhân sự, chấm công khuôn mặt, ZKTeco, bảng lương, quản lý ca, HRM Việt Nam"',
    'content="phần mềm quản lý nhân sự, phần mềm chấm công, chấm công khuôn mặt, chấm công ZKTeco, phần mềm bảng lương, quản lý ca làm việc, HRM Việt Nam, SBOX HRM, ADMS"',
)

t = t.replace('href="https://sboxhrm.com/home.html"', 'href="https://sboxhrm.com/"')
t = t.replace('content="https://sboxhrm.com/home.html"', 'content="https://sboxhrm.com/"')
t = t.replace('"url": "https://sboxhrm.com/home.html"', '"url": "https://sboxhrm.com/"')
t = t.replace('href="/home.html"', 'href="/"')

t = t.replace(
    '<meta property="og:title" content="SBOX HRM – Phần mềm quản lý nhân sự thông minh" />',
    '<meta property="og:title" content="SBOX HRM – Phần mềm quản lý nhân sự &amp; chấm công" />',
)

old_ld_start = t.find('<script type="application/ld+json">')
old_ld_end = t.find("</script>", old_ld_start) + len("</script>")
if old_ld_start < 0:
    raise SystemExit("no json-ld")

new_ld = r'''<script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "WebSite",
        "@id": "https://sboxhrm.com/#website",
        "url": "https://sboxhrm.com/",
        "name": "SBOX HRM",
        "description": "Phần mềm quản lý nhân sự – chấm công khuôn mặt, ZKTeco, ca làm, bảng lương",
        "inLanguage": "vi-VN",
        "publisher": { "@id": "https://sboxhrm.com/#organization" }
      },
      {
        "@type": "Organization",
        "@id": "https://sboxhrm.com/#organization",
        "name": "SBOX HRM",
        "url": "https://sboxhrm.com/",
        "logo": "https://sboxhrm.com/icons/Icon-512.png",
        "email": "support@sboxhrm.com",
        "telephone": "+84-973-024-042",
        "address": {
          "@type": "PostalAddress",
          "streetAddress": "184 Nam Cao",
          "addressLocality": "Hòa Khánh",
          "addressRegion": "Đà Nẵng",
          "addressCountry": "VN"
        },
        "sameAs": [
          "https://play.google.com/store/apps/details?id=sbox.sana.vn"
        ]
      },
      {
        "@type": "SoftwareApplication",
        "name": "SBOX HRM",
        "applicationCategory": "BusinessApplication",
        "operatingSystem": "Android, Web",
        "offers": { "@type": "Offer", "price": "0", "priceCurrency": "VND", "description": "Dùng thử miễn phí" },
        "description": "Phần mềm quản lý nhân sự: chấm công khuôn mặt AI, ZKTeco ADMS, quản lý ca, bảng lương tự động, phê duyệt đơn từ, báo cáo realtime.",
        "screenshot": "https://sboxhrm.com/images/landing/screenshot-01.jpg",
        "downloadUrl": "https://play.google.com/store/apps/details?id=sbox.sana.vn",
        "url": "https://sboxhrm.com/"
      },
      {
        "@type": "FAQPage",
        "@id": "https://sboxhrm.com/#faq",
        "mainEntity": [
          {
            "@type": "Question",
            "name": "SBOX HRM là phần mềm gì?",
            "acceptedAnswer": {
              "@type": "Answer",
              "text": "SBOX HRM là phần mềm quản lý nhân sự cho doanh nghiệp Việt Nam: chấm công khuôn mặt/GPS, kết nối máy ZKTeco, quản lý ca làm việc, bảng lương tự động và báo cáo realtime trên web lẫn Android."
            }
          },
          {
            "@type": "Question",
            "name": "SBOX HRM có hỗ trợ máy chấm công ZKTeco không?",
            "acceptedAnswer": {
              "@type": "Answer",
              "text": "Có. SBOX đồng bộ máy ZKTeco qua ADMS/PUSH (cổng 7070), quản lý nhân viên trên máy, vân tay và khuôn mặt từ phần mềm."
            }
          },
          {
            "@type": "Question",
            "name": "Có dùng thử miễn phí không?",
            "acceptedAnswer": {
              "@type": "Answer",
              "text": "Có. Bạn có thể đăng ký dùng thử miễn phí trên sboxhrm.com hoặc tải app Android trên Google Play."
            }
          },
          {
            "@type": "Question",
            "name": "Chấm công trên điện thoại có cần GPS không?",
            "acceptedAnswer": {
              "@type": "Answer",
              "text": "Chấm công mobile hỗ trợ nhận diện khuôn mặt, xác minh GPS/WiFi theo cấu hình cửa hàng để đảm bảo chấm đúng địa điểm."
            }
          }
        ]
      }
    ]
  }
  </script>'''

t = t[:old_ld_start] + new_ld + t[old_ld_end:]

if "hreflang" not in t:
    t = t.replace(
        '<link rel="canonical" href="https://sboxhrm.com/" />',
        '<link rel="canonical" href="https://sboxhrm.com/" />\n'
        '  <link rel="alternate" hreflang="vi" href="https://sboxhrm.com/" />\n'
        '  <link rel="alternate" hreflang="x-default" href="https://sboxhrm.com/" />',
    )

faq_html = """
<!-- FAQ SEO -->
<section id="faq" style="background:#fff;padding:80px 24px">
  <div style="max-width:900px;margin:0 auto">
    <div class="section-center">
      <div class="section-tag">Hỏi đáp</div>
      <h2 class="section-title">Câu hỏi thường gặp về phần mềm quản lý nhân sự SBOX</h2>
      <p class="section-sub">Giải đáp nhanh trước khi dùng thử phần mềm chấm công và bảng lương.</p>
    </div>
    <div style="display:grid;gap:16px;margin-top:28px">
      <details style="border:1px solid #E2E8F0;border-radius:12px;padding:16px 18px;background:#F8FAFF">
        <summary style="font-weight:700;cursor:pointer;color:#0F172A">SBOX HRM là phần mềm gì?</summary>
        <p style="margin-top:10px;color:#475569;line-height:1.6">SBOX HRM là phần mềm quản lý nhân sự cho doanh nghiệp Việt Nam: chấm công khuôn mặt/GPS, kết nối máy ZKTeco, quản lý ca làm việc, bảng lương tự động và báo cáo realtime trên web lẫn Android.</p>
      </details>
      <details style="border:1px solid #E2E8F0;border-radius:12px;padding:16px 18px;background:#F8FAFF">
        <summary style="font-weight:700;cursor:pointer;color:#0F172A">Có hỗ trợ máy chấm công ZKTeco không?</summary>
        <p style="margin-top:10px;color:#475569;line-height:1.6">Có. Đồng bộ qua ADMS/PUSH (IP máy chủ và cổng 7070), quản lý nhân viên, vân tay và khuôn mặt từ phần mềm.</p>
      </details>
      <details style="border:1px solid #E2E8F0;border-radius:12px;padding:16px 18px;background:#F8FAFF">
        <summary style="font-weight:700;cursor:pointer;color:#0F172A">Có dùng thử miễn phí không?</summary>
        <p style="margin-top:10px;color:#475569;line-height:1.6">Có. Đăng ký tại sboxhrm.com hoặc tải app Android trên Google Play để dùng thử.</p>
      </details>
      <details style="border:1px solid #E2E8F0;border-radius:12px;padding:16px 18px;background:#F8FAFF">
        <summary style="font-weight:700;cursor:pointer;color:#0F172A">Chấm công mobile có cần GPS không?</summary>
        <p style="margin-top:10px;color:#475569;line-height:1.6">Hỗ trợ khuôn mặt kèm xác minh GPS/WiFi theo cấu hình cửa hàng để chấm đúng địa điểm.</p>
      </details>
    </div>
  </div>
</section>

"""

if 'id="faq"' not in t:
    t = t.replace("<!-- CONTACT -->", faq_html + "<!-- CONTACT -->")

if 'href="#faq"' not in t:
    t = t.replace(
        '<li><a href="#howto">Hướng dẫn</a></li>',
        '<li><a href="#howto">Hướng dẫn</a></li>\n    <li><a href="#faq">Hỏi đáp</a></li>',
    )
    t = t.replace(
        '<a href="#howto" class="nav-drawer-link">Hướng dẫn</a>',
        '<a href="#howto" class="nav-drawer-link">Hướng dẫn</a>\n  <a href="#faq" class="nav-drawer-link">Hỏi đáp</a>',
    )

p.write_text(t, encoding="utf-8", newline="\n")
print("OK")
for line in t.splitlines():
    if "<title>" in line or "canonical" in line or "FAQPage" in line:
        print(line[:140])
