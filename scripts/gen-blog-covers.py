"""
Sinh ảnh bìa 1200×630 riêng cho từng bài / trang tính năng HRM (Seo/Seed/hrm-*.md) và ghi lại dòng «cover:».

Trước đây nhiều bài dùng chung một ảnh chụp màn hình → ảnh xem trước (og:image), Google Ảnh và Discover bị trùng.
Mỗi ảnh: nền màu theo chuyên mục, nhãn chuyên mục, tiêu đề bài, logo + sboxhrm.com, bên phải là ảnh màn hình app.
Chạy lại an toàn (ảnh nguồn chọn theo chuyên mục + slug, không phụ thuộc dòng cover cũ).

Dùng: python scripts/gen-blog-covers.py            (sinh ảnh + cập nhật cover trong .md)
      python scripts/gen-blog-covers.py --only slug-a,slug-b
"""
import argparse
import pathlib
import re
import sys
import zlib

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
SEED = ROOT / "src" / "ZKTecoADMS.Api" / "Seo" / "Seed"
WEB_IMG = ROOT / "flutter_client" / "web" / "images"
OUT = WEB_IMG / "blog"
W, H = 1200, 630

FONT_BOLD = "C:/Windows/Fonts/segoeuib.ttf"
FONT_REG = "C:/Windows/Fonts/segoeui.ttf"

# Màu nền (trên, dưới) theo chuyên mục — bài cùng chuyên mục cùng tông, khác chuyên mục dễ phân biệt.
PALETTE = {
    "Máy chấm công": ("#0C56D0", "#062C6E"),
    "Chấm công": ("#1565C0", "#0B2F5E"),
    "Chấm công điện thoại": ("#00838F", "#004D52"),
    "Tính lương": ("#2E7D32", "#123D16"),
    "Theo ngành": ("#6A1B9A", "#33094D"),
    "Ca làm việc": ("#EF6C00", "#8A3A00"),
    "Nghỉ phép": ("#C62828", "#661212"),
    "Đơn từ & phê duyệt": ("#C62828", "#661212"),
    "Quản lý nhân sự": ("#37474F", "#151D21"),
    "Nhân sự": ("#37474F", "#151D21"),
}
DEFAULT_COLORS = ("#0C56D0", "#062C6E")

SHOTS = [f"landing/screenshot-0{i}.jpg" for i in range(1, 8)]
MOBILE = sorted(str(p.relative_to(WEB_IMG)).replace("\\", "/") for p in (WEB_IMG / "landing" / "mobile").glob("mobile-0*.png"))
# Ảnh màn hình ưu tiên theo chuyên mục; trong nhóm chọn theo slug để các bài khác nhau ra ảnh khác nhau.
SHOT_POOL = {
    "Chấm công điện thoại": [m for m in MOBILE if "checkin" in m or "attendance" in m or "fingerprint" in m],
    "Ca làm việc": [m for m in MOBILE if "schedule" in m] + SHOTS[3:5],
    "Quản lý nhân sự": [m for m in MOBILE if "profile" in m] + SHOTS[5:7],
    "Nhân sự": [m for m in MOBILE if "profile" in m],
}


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def front_matter(text):
    m = re.match(r"---\n(.*?)\n---\n", text.replace("\r\n", "\n").lstrip("\ufeff"), re.S)
    if not m:
        return None
    meta = {}
    for line in m.group(1).split("\n"):
        k, sep, v = line.partition(":")
        if sep:
            meta[k.strip()] = v.strip()
    return meta


def wrap(draw, text, font, width):
    lines, cur = [], ""
    for word in text.split():
        trial = (cur + " " + word).strip()
        if draw.textlength(trial, font=font) <= width:
            cur = trial
        else:
            if cur:
                lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    return lines


def fit_title(draw, title, width, max_lines=4):
    for size in range(64, 33, -2):
        font = ImageFont.truetype(FONT_BOLD, size)
        lines = wrap(draw, title, font, width)
        if len(lines) <= max_lines:
            return font, lines, size
    font = ImageFont.truetype(FONT_BOLD, 34)
    lines = wrap(draw, title, font, width)[:max_lines]
    lines[-1] = lines[-1].rstrip(" ,.:") + "…"
    return font, lines, 34


def gradient(top, bottom):
    t, b = hex_rgb(top), hex_rgb(bottom)
    col = Image.new("RGB", (1, H))
    for y in range(H):
        k = y / (H - 1)
        col.putpixel((0, y), tuple(round(t[i] + (b[i] - t[i]) * k) for i in range(3)))
    return col.resize((W, H))


def rounded(im, radius):
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, im.size[0] - 1, im.size[1] - 1), radius, fill=255)
    out = Image.new("RGBA", im.size)
    out.paste(im, (0, 0), mask)
    return out


def phone(shot_path):
    """Ảnh màn hình trong khung điện thoại bo góc, kèm bóng đổ."""
    pw, ph = 300, 560
    shot = Image.open(WEB_IMG / shot_path).convert("RGB")
    scale = max((pw - 20) / shot.width, (ph - 20) / shot.height)
    shot = shot.resize((round(shot.width * scale), round(shot.height * scale)), Image.LANCZOS)
    shot = shot.crop((0, 0, pw - 20, ph - 20))
    frame = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
    ImageDraw.Draw(frame).rounded_rectangle((0, 0, pw - 1, ph - 1), 38, fill=(17, 24, 39, 255))
    frame.alpha_composite(rounded(shot, 30), (10, 10))
    shadow = Image.new("RGBA", (pw + 80, ph + 80), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((40, 50, pw + 40, ph + 50), 38, fill=(0, 0, 0, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))
    shadow.alpha_composite(frame, (40, 40))
    return shadow


def cover(meta):
    slug, title, cat = meta["slug"], meta["title"], meta.get("category") or ""
    top, bottom = PALETTE.get(cat, DEFAULT_COLORS)
    im = gradient(top, bottom).convert("RGBA")
    d = ImageDraw.Draw(im)
    # Họa tiết vòng tròn mờ phía sau điện thoại.
    deco = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dd = ImageDraw.Draw(deco)
    dd.ellipse((780, -120, 1320, 420), fill=(255, 255, 255, 22))
    dd.ellipse((860, 330, 1260, 730), fill=(255, 255, 255, 14))
    im.alpha_composite(deco)

    pool = SHOT_POOL.get(cat) or (SHOTS + MOBILE)
    shot = pool[zlib.crc32(slug.encode()) % len(pool)]
    ph = phone(shot)
    im.alpha_composite(ph, (W - ph.width + 10, H - ph.height + 130))

    x, text_w = 64, 700
    # Nhãn chuyên mục (trang tính năng: «Tính năng»).
    label = ("Tính năng · " if meta.get("type") == "feature" else "") + (cat or "Bài viết")
    f_lab = ImageFont.truetype(FONT_BOLD, 24)
    lw = d.textlength(label, font=f_lab)
    d.rounded_rectangle((x, 64, x + lw + 32, 64 + 44), 22, fill=(255, 255, 255, 235))
    d.text((x + 16, 64 + 7), label, font=f_lab, fill=hex_rgb(top))

    font, lines, size = fit_title(d, title, text_w)
    y = 140
    for line in lines:
        d.text((x, y), line, font=font, fill="white")
        y += round(size * 1.22)

    logo = Image.open(WEB_IMG / "landing" / "sbox-logo-white.png").convert("RGBA")
    logo.thumbnail((56, 56))
    im.alpha_composite(logo, (x, H - 64 - logo.height + 6))
    f_brand = ImageFont.truetype(FONT_BOLD, 28)
    f_site = ImageFont.truetype(FONT_REG, 24)
    d.text((x + logo.width + 14, H - 98), "SBOX HRM", font=f_brand, fill="white")
    d.text((x + logo.width + 14, H - 64), "sboxhrm.com · Dùng thử miễn phí", font=f_site, fill=(255, 255, 255, 210))
    return im.convert("RGB")


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", help="danh sách slug, phân cách bằng dấu phẩy")
    args = ap.parse_args()
    only = set(args.only.split(",")) if args.only else None
    OUT.mkdir(parents=True, exist_ok=True)
    n = 0
    for md in sorted(SEED.glob("hrm-*.md")):
        text = md.read_text(encoding="utf-8")
        meta = front_matter(text)
        if not meta or not meta.get("slug") or (only and meta["slug"] not in only):
            continue
        cover(meta).save(OUT / f"{meta['slug']}.jpg", "JPEG", quality=84, optimize=True, progressive=True)
        url = f"/images/blog/{meta['slug']}.jpg"
        # [^\r\n] — một phần file Seed dùng CRLF, giữ nguyên kiểu xuống dòng.
        new = re.sub(r"(?m)^cover:[^\r\n]*", f"cover: {url}", text, count=1)
        if "\ncover:" not in text:
            nl = "\r\n" if "\r\n" in text else "\n"
            new = re.sub(r"(?m)^(category:[^\r\n]*)", lambda m: m.group(1) + nl + f"cover: {url}", text, count=1)
        if new != text:
            md.write_text(new, encoding="utf-8", newline="")
        n += 1
    print(f"gen-blog-covers: {n} ảnh → {OUT}")


if __name__ == "__main__":
    main()
