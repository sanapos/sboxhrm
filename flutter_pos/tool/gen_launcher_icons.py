# -*- coding: utf-8 -*-
"""Generate mipmap ic_launcher.png from assets/logo.png (SBOX mark).

- Nền ngoài trong suốt (giữ squircle xanh + chữ S của logo).
- Logo chiếm ~92% khung (to hơn bản cũ pad 12%).
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
LOGO = ROOT / "assets" / "logo.png"
RES = ROOT / "android" / "app" / "src" / "main" / "res"
SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}
# Adaptive foreground: 108dp canvas, safe zone ~66dp center.
ADAPTIVE_FG = 432  # xxxhdpi 108*4
# Pad nhỏ → logo to; 0.04 = ~92% khung.
PAD_RATIO = 0.04


def _knockout_dark_bg(im: Image.Image, threshold: int = 28) -> Image.Image:
    """Đổi nền đen/near-black thành alpha=0."""
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            if r <= threshold and g <= threshold and b <= threshold:
                px[x, y] = (0, 0, 0, 0)
    return im


def _prepare_logo() -> Image.Image:
    src = Image.open(LOGO).convert("RGBA")
    src = _knockout_dark_bg(src)
    bbox = src.getbbox()
    if bbox:
        src = src.crop(bbox)
    return src


def make_icon(size: int, src: Image.Image, pad_ratio: float = PAD_RATIO) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pad = max(1, int(size * pad_ratio))
    inner = size - pad * 2
    logo = src.copy()
    logo.thumbnail((inner, inner), Image.Resampling.LANCZOS)
    x = (size - logo.width) // 2
    y = (size - logo.height) // 2
    canvas.paste(logo, (x, y), logo)
    return canvas


def main() -> None:
    src = _prepare_logo()
    for folder, size in SIZES.items():
        out = RES / folder / "ic_launcher.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        make_icon(size, src).save(out, format="PNG", optimize=True)
        print(out, out.stat().st_size)

    # Adaptive icon foreground (Android 8+) — logo to hơn trong safe zone.
    anydpi = RES / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    fg_dir = RES / "drawable"
    fg_dir.mkdir(parents=True, exist_ok=True)
    fg = make_icon(ADAPTIVE_FG, src, pad_ratio=0.08)
    fg_path = fg_dir / "ic_launcher_foreground.png"
    fg.save(fg_path, format="PNG", optimize=True)
    print(fg_path, fg_path.stat().st_size)

    (anydpi / "ic_launcher.xml").write_text(
        """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@android:color/transparent"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
</adaptive-icon>
""",
        encoding="utf-8",
    )
    print(anydpi / "ic_launcher.xml")


if __name__ == "__main__":
    main()
