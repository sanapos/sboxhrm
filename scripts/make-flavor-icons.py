#!/usr/bin/env python3
"""Icon launcher cho flavor boss / staff / kds / pos: lấy chữ S từ logo gốc flutter_client/assets/logo.png,
đặt lên nền màu của flavor.

Ghi mipmap-*/ic_launcher(_round).png và ic_launcher-playstore.png (512px, ảnh vuông cho Play)
vào android/app/src/<flavor>/, logo trong app vào assets/sbox_<flavor>_logo.png. Chạy lại: python scripts/make-flavor-icons.py [ảnh preview]
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
CLIENT = ROOT / "flutter_client"
DENSITIES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
SIZE = 1024

# Vùng chữ S trong huy hiệu gốc (tỉ lệ cạnh) — bỏ phần viền và đốm sáng ở góc.
S_REGION = (0.17, 0.14, 0.82, 0.78)
S_SCALE = 0.95
S_CENTER = (0.5, 0.5)
ROUND_INSET = 12

FLAVORS = {
    "boss": dict(bg=("#0E1422", "#3B4A6B"), s=("#C4922F", "#FFE394")),
    "staff": dict(bg=("#00594F", "#35CDAE"), s=("#CFEFE8", "#FFFFFF")),
    "kds": dict(bg=("#B23A0E", "#FF9A4A"), s=("#FFE6D6", "#FFFFFF")),
    # SBOX POS giữ logo chữ assets/sbox_pos_logo.png, chỉ thêm icon và logo chữ S (sbox_pos_mark.png).
    "pos": dict(bg=("#1B5E20", "#66BB6A"), s=("#E3F4E4", "#FFFFFF")),
}
IOS_FLAVORS = {"pos", "boss", "staff"}


def rgb(hex_color):
    return np.array([int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5)])


def smoothstep(x, lo, hi):
    t = np.clip((x - lo) / (hi - lo), 0, 1)
    return t * t * (3 - 2 * t)


def ramp(t, low, high):
    return rgb(low) + (rgb(high) - rgb(low)) * t[..., None]


def to_image(color, alpha):
    data = np.dstack([color, alpha])
    return Image.fromarray((data * 255).round().astype("uint8"), "RGBA")


def gradient(cfg):
    """Nền chéo: sáng ở góc trên phải, tối ở góc dưới trái."""
    y, x = np.mgrid[0:1:SIZE * 1j, 0:1:SIZE * 1j]
    return to_image(ramp((x + 1 - y) / 2, *cfg["bg"]), np.ones((SIZE, SIZE)))


def letter_layer(badge, cfg):
    """Tách chữ S (kênh R cao, nền xanh có R thấp), tô dải màu flavor, đặt giữa icon."""
    # Làm mịn trước khi tô: ảnh gốc có nhiễu, tô thẳng dải màu tương phản sẽ lấm tấm.
    red = np.asarray(badge.convert("RGB").filter(ImageFilter.GaussianBlur(3)), dtype=float)[..., 0] / 255
    sharp = np.asarray(badge.convert("RGB"), dtype=float)[..., 0] / 255
    letter = to_image(ramp(smoothstep(red, 0.72, 1.0), *cfg["s"]), smoothstep(sharp, 0.62, 0.86))
    x0, y0, x1, y1 = [int(v * SIZE) for v in S_REGION]
    part = letter.crop((x0, y0, x1, y1))
    w, h = int(part.width * S_SCALE), int(part.height * S_SCALE)
    part = part.resize((w, h), Image.LANCZOS)
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    layer.paste(part, (int(S_CENTER[0] * SIZE - w / 2), int(S_CENTER[1] * SIZE - h / 2)))
    return layer


def circle_mask():
    k = 4
    mask = Image.new("L", (SIZE * k, SIZE * k), 0)
    edge = (SIZE - ROUND_INSET) * k
    ImageDraw.Draw(mask).ellipse([ROUND_INSET * k, ROUND_INSET * k, edge, edge], fill=255)
    return mask.resize((SIZE, SIZE), Image.LANCZOS)


def clipped(layer, mask):
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out.paste(layer, (0, 0), mask)
    return out


def build(badge, cfg):
    shape = badge.getchannel("A")
    art = Image.alpha_composite(gradient(cfg), letter_layer(badge, cfg))

    # Viền sáng mảnh theo dáng huy hiệu, giống logo gốc.
    rim = ImageChops.subtract(shape, shape.filter(ImageFilter.MinFilter(9))).point(lambda v: v // 3)
    glow = to_image(np.ones((SIZE, SIZE, 3)) * rgb(cfg["bg"][1]), np.asarray(rim, dtype=float) / 255)
    square = clipped(Image.alpha_composite(art, glow), shape)

    round_icon = clipped(art, circle_mask())

    # Play tự bo góc: cần ảnh vuông kín nền, không trong suốt.
    store = art.convert("RGB").resize((512, 512), Image.LANCZOS)
    return square, round_icon, store


def load_badge():
    logo = Image.open(CLIENT / "assets" / "logo.png").convert("RGBA")
    src = logo.crop(logo.getchannel("A").point(lambda v: 255 if v > 200 else 0).getbbox())
    side = max(src.size)
    fitted = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    fitted.paste(src, ((side - src.width) // 2, (side - src.height) // 2))
    return fitted.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    badge = load_badge()
    results = {}
    for flavor, cfg in FLAVORS.items():
        square, round_icon, store = build(badge, cfg)
        base = CLIENT / "android" / "app" / "src" / flavor
        for density, px in DENSITIES.items():
            folder = base / "res" / f"mipmap-{density}"
            folder.mkdir(parents=True, exist_ok=True)
            square.resize((px, px), Image.LANCZOS).save(folder / "ic_launcher.png", optimize=True)
            round_icon.resize((px, px), Image.LANCZOS).save(folder / "ic_launcher_round.png", optimize=True)
        store.save(base / "ic_launcher-playstore.png", optimize=True)
        if flavor in IOS_FLAVORS:
            # App Store cần ảnh 1024px vuông kín nền, không có kênh alpha; workflow iOS tự sinh các cỡ khác.
            out = CLIENT / "ios" / "flavor_icons" / f"{flavor}-1024.png"
            out.parent.mkdir(parents=True, exist_ok=True)
            Image.alpha_composite(gradient(FLAVORS[flavor]), letter_layer(badge, FLAVORS[flavor])).convert("RGB").save(out, optimize=True)
        square.resize((512, 512), Image.LANCZOS).save(CLIENT / "assets" / ("sbox_pos_mark.png" if flavor == "pos" else f"sbox_{flavor}_logo.png"), optimize=True)
        results[flavor] = (square, round_icon, store)
    write_status_icon(badge)
    if len(sys.argv) > 1:
        preview(results, Path(sys.argv[1]))


def write_status_icon(badge):
    """Icon thanh thông báo: Android chỉ lấy kênh alpha — chữ S trắng trên nền trong suốt (24dp), dùng chung mọi flavor."""
    alpha = letter_layer(badge, FLAVORS["staff"]).getchannel("A")
    white = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    white.putalpha(alpha)
    res = CLIENT / "android" / "app" / "src" / "main" / "res"
    for density, launcher_px in DENSITIES.items():
        folder = res / f"drawable-{density}"
        folder.mkdir(parents=True, exist_ok=True)
        px = launcher_px // 2
        white.resize((px, px), Image.LANCZOS).save(folder / "ic_stat_sbox.png", optimize=True)


def preview(results, out):
    """Bảng xem thử: HRM để so sánh, cỡ launcher thật trên nền sáng và tối, ảnh Play."""
    hrm = Image.open(CLIENT / "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png").convert("RGBA")
    rows = [(hrm, hrm, None)] + list(results.values())
    sheet = Image.new("RGB", (1460, 300 * len(rows)), "#FFFFFF")
    ImageDraw.Draw(sheet).rectangle([640, 0, 1180, sheet.height], fill="#20242C")
    for row, (square, round_icon, store) in enumerate(rows):
        y = row * 300 + 25
        big = square.resize((250, 250), Image.LANCZOS)
        sheet.paste(big, (20, y), big)
        for offset in (0, 640):
            x = 290 + offset
            for px in (96, 72, 48):
                icon = square.resize((px, px), Image.LANCZOS)
                sheet.paste(icon, (x, y + 20), icon)
                small = round_icon.resize((px, px), Image.LANCZOS)
                sheet.paste(small, (x, y + 130), small)
                x += px + 16
        if store:
            sheet.paste(store.resize((250, 250), Image.LANCZOS), (1195, y))
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)


if __name__ == "__main__":
    main()
