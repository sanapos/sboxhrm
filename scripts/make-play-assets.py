#!/usr/bin/env python3
"""Tài sản trang Google Play cho SBOX POS / BOSS / Nhân Viên / KDS.

Ghi vào dist/play-assets/<app>/: icon-512.png, feature-1024x500.png, listing.txt
và ảnh màn hình có chú thích (phone-*.png, tablet-*.png) từ ảnh gốc trong
dist/play-assets/<app>/raw/. Tên ảnh gốc: <phone|tablet>-<số>__<chú thích>.png
Chạy lại: python scripts/make-play-assets.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
CLIENT = ROOT / "flutter_client"
OUT = ROOT / "dist" / "play-assets"
FONTS = CLIENT / "assets" / "fonts"
PRIVACY = "https://sboxpos.com/privacy-policy-pos.html"
SUPPORT = "sboxhrm@gmail.com"

APPS = {
    "pos": dict(
        name="SBOX POS", bg=("#1B5E20", "#66BB6A"), tagline="Bán hàng nhanh, quản lý cửa hàng chuẩn",
        points=["Bán tại quầy, tại bàn", "In hóa đơn, báo bếp", "Kho, khách hàng, báo cáo"],
        short="Bán hàng tại quầy, tại bàn, in hóa đơn, quản lý kho và báo cáo cho cửa hàng.",
        full="""SBOX POS là phần mềm bán hàng cho cửa hàng bán lẻ, quán ăn, cà phê, spa và dịch vụ. Dùng trên điện thoại, máy tính bảng và máy POS Android.

BÁN HÀNG
- Bán tại quầy, theo sơ đồ bàn, phòng, hoặc giao hàng
- Giảm giá, khuyến mãi, voucher, bảng giá, tích điểm
- Thanh toán tiền mặt, chuyển khoản, mã VietQR, ghi nợ
- In hóa đơn, tem nhãn, phiếu báo bếp; màn hình bếp
- Menu QR gọi món tại bàn, đơn online

QUẢN LÝ CỬA HÀNG
- Hàng hóa, topping, combo, định lượng nguyên vật liệu
- Nhập hàng, trả hàng nhập, kiểm kho, xuất hủy, seri máy
- Khách hàng, công nợ, nhà cung cấp, bảo hành
- Báo giá, hợp đồng, hóa đơn điện tử
- Ca thu ngân, thu chi, báo cáo doanh thu và lợi nhuận
- Phân quyền theo vai trò, lịch sử thao tác

YÊU CẦU
Cần tài khoản cửa hàng SBOX. Đăng ký tại sboxpos.com.

HỖ TRỢ
Email: {support}
Chính sách quyền riêng tư: {privacy}""",
    ),
    "boss": dict(
        name="SBOX BOSS", bg=("#0E1422", "#3B4A6B"), tagline="Nắm cửa hàng mọi lúc, mọi nơi",
        points=["Doanh thu, lợi nhuận", "Việc cần duyệt, cảnh báo", "Nhân sự, kho, bảng lương"],
        short="Cho chủ cửa hàng: doanh thu, việc cần duyệt, kho, nhân sự trên điện thoại.",
        full="""SBOX BOSS là ứng dụng dành cho chủ cửa hàng và quản lý, xem tình hình kinh doanh ngay trên điện thoại.

TỔNG QUAN
- Doanh thu, lợi nhuận, số đơn theo ngày, so với hôm trước
- Báo cáo cuối ngày, chi nhánh
- Cảnh báo rủi ro: hủy đơn, lệch quỹ, ca quên đóng

VIỆC CẦN XỬ LÝ
- Duyệt đơn từ nhân viên ngay trên điện thoại
- Thông báo tức thời

QUẢN LÝ
- Hàng hóa, kho, nhà cung cấp
- Nhân viên hôm nay, tổng hợp chấm công, bảng lương
- Xếp lịch, công việc, ý kiến nhân viên
- Tài khoản, phân quyền, thiết lập cửa hàng

YÊU CẦU
Dùng tài khoản chủ hoặc quản lý của cửa hàng SBOX. Các chức năng hiện theo gói dịch vụ của cửa hàng.

HỖ TRỢ
Email: {support}
Chính sách quyền riêng tư: {privacy}""",
    ),
    "staff": dict(
        name="SBOX Nhân Viên", bg=("#00594F", "#35CDAE"), tagline="Mọi việc của nhân viên trong một ứng dụng",
        points=["Chấm công trên điện thoại", "Lịch làm, phiếu lương", "Đơn từ, gọi món"],
        short="Cho nhân viên: chấm công, xem lịch, phiếu lương, gửi đơn từ, gọi món.",
        full="""SBOX Nhân Viên là ứng dụng cho nhân viên của các cửa hàng, doanh nghiệp dùng hệ thống SBOX.

HẰNG NGÀY
- Chấm công trên điện thoại theo quy định của công ty
- Xem lịch làm việc, đăng ký và đổi ca
- Nhận thông báo, tin nội bộ

ĐƠN TỪ VÀ THU NHẬP
- Xin nghỉ phép, tăng ca, sửa giờ chấm công, ứng lương, công tác phí
- Theo dõi trạng thái duyệt
- Xem phiếu lương, thưởng phạt

CÔNG VIỆC
- Danh sách việc được giao, gửi ý kiến
- Gọi món và theo dõi bếp cho nhân viên phục vụ

YÊU CẦU
Cần tài khoản do công ty hoặc cửa hàng cấp.

HỖ TRỢ
Email: {support}
Chính sách quyền riêng tư: {privacy}""",
    ),
    "kds": dict(
        name="SBOX KDS", bg=("#B23A0E", "#FF9A4A"), tagline="Màn hình bếp cho nhà hàng, quán ăn",
        points=["Nhận món tức thời", "Gộp món, theo bàn", "Báo món xong về quầy"],
        short="Màn hình bếp: nhận món từ quầy, theo dõi trạng thái, báo món xong.",
        full="""SBOX KDS là ứng dụng màn hình bếp, kết nối với phần mềm bán hàng SBOX POS. Dùng trên máy tính bảng hoặc màn hình Android đặt trong bếp, quầy pha chế.

TÍNH NĂNG
- Nhận món ngay khi thu ngân hoặc phục vụ báo bếp
- Xem theo bàn hoặc gộp các món giống nhau
- Chuyển trạng thái chờ, đang làm, làm xong
- Cảnh báo món làm trễ, âm thanh khi có món mới
- Hiện phần bổ sung khi khách thêm topping, ghi chú
- Giao diện sáng, tối cho bếp

YÊU CẦU
Cần tài khoản cửa hàng SBOX có chức năng màn hình bếp.

HỖ TRỢ
Email: {support}
Chính sách quyền riêng tư: {privacy}""",
    ),
}


def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def gradient(size, low, high):
    w, h = size
    a, b = rgb(low), rgb(high)
    img = Image.new("RGB", size)
    px = img.load()
    for y in range(h):
        for x in range(w):
            t = (x / w + 1 - y / h) / 2
            px[x, y] = tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))
    return img


def font(style, size):
    return ImageFont.truetype(str(FONTS / f"BeVietnamPro-{style}.ttf"), size)


def rounded(img, radius):
    mask = Image.new("L", (img.width * 4, img.height * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, mask.width, mask.height), radius * 4, fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask.resize(img.size, Image.LANCZOS))
    return out


def wrap(draw, text, fnt, width):
    lines, cur = [], ""
    for word in text.split():
        probe = (cur + " " + word).strip()
        if draw.textlength(probe, font=fnt) <= width:
            cur = probe
        else:
            lines.append(cur)
            cur = word
    return lines + [cur]


def feature(app, cfg, icon):
    img = gradient((1024, 500), *cfg["bg"])
    d = ImageDraw.Draw(img)
    badge = rounded(icon.resize((168, 168), Image.LANCZOS), 38)
    img.paste(badge, (64, 72), badge)
    d.text((64, 262), cfg["name"], font=font("ExtraBold", 54), fill="white")
    y = 338
    for line in wrap(d, cfg["tagline"], font("Medium", 25), 470):
        d.text((64, y), line, font=font("Medium", 25), fill=(255, 255, 255, 235))
        y += 36
    y = 118
    for point in cfg["points"]:
        d.rounded_rectangle((566, y, 964, y + 78), 20, fill=tuple(min(255, c + 26) for c in rgb(cfg["bg"][0])))
        d.ellipse((588, y + 29, 608, y + 49), fill="white")
        d.text((626, y + 24), point, font=font("SemiBold", 25), fill="white")
        y += 96
    img.save(OUT / app / "feature-1024x500.png", optimize=True)


def framed(cfg, raw, caption, size):
    w, h = size
    img = gradient(size, *cfg["bg"])
    d = ImageDraw.Draw(img)
    fnt = font("Bold", 56 if h > w else 50)
    lines = wrap(d, caption, fnt, w - 140)
    y = 72
    for line in lines:
        d.text(((w - d.textlength(line, font=fnt)) / 2, y), line, font=fnt, fill="white")
        y += int(fnt.size * 1.28)
    top = y + 36
    box_w, box_h = w - 120, h - top - 60
    scale = min(box_w / raw.width, box_h / raw.height)
    shot = raw.convert("RGB").resize((int(raw.width * scale), int(raw.height * scale)), Image.LANCZOS)
    shot = rounded(shot, 26 if h > w else 18)
    img.paste(shot, ((w - shot.width) // 2, top), shot)
    return img


def main():
    for app, cfg in APPS.items():
        folder = OUT / app
        (folder / "raw").mkdir(parents=True, exist_ok=True)
        icon = Image.open(CLIENT / "android" / "app" / "src" / app / "ic_launcher-playstore.png").convert("RGB")
        icon.resize((512, 512), Image.LANCZOS).save(folder / "icon-512.png", optimize=True)
        feature(app, cfg, icon)
        full = cfg["full"].format(support=SUPPORT, privacy=PRIVACY)
        assert len(cfg["short"]) <= 80, (app, len(cfg["short"]))
        assert len(full) <= 4000, app
        (folder / "listing.txt").write_text(
            f"TÊN: {cfg['name']}\n\nMÔ TẢ NGẮN:\n{cfg['short']}\n\nMÔ TẢ ĐẦY ĐỦ:\n{full}\n", encoding="utf-8")
        for raw_path in sorted((folder / "raw").glob("*.png")):
            stem, _, caption = raw_path.stem.partition("__")
            raw = Image.open(raw_path)
            # Máy bảng: ảnh ngang 16:9, ảnh dọc 1200x1920; điện thoại 9:16.
            size = (1080, 1920) if not stem.startswith("tablet") else ((1920, 1080) if raw.width > raw.height else (1200, 1920))
            framed(cfg, raw, caption, size).save(folder / f"{stem}.png", optimize=True)
        print(app, len(cfg["short"]), len(full), sorted(p.name for p in folder.glob("*.png")))


if __name__ == "__main__":
    main()
