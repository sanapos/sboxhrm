#!/usr/bin/env python3
"""App Store screenshots for SBOX POS, built from dist/play-assets/pos/raw.

Writes dist/app-store-assets/pos/iphone-*.png (1206x2622) and ipad-*.png
(2752x2064). Apple rejects transparent PNGs, so every output is plain RGB.
Run: python scripts/make-appstore-assets.py
"""
import importlib.util
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "dist" / "play-assets" / "pos" / "raw"
OUT = ROOT / "dist" / "app-store-assets" / "pos"

_spec = importlib.util.spec_from_file_location("play_assets", ROOT / "scripts" / "make-play-assets.py")
play = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(play)

BG = play.APPS["pos"]["bg"]
IPHONE = (1206, 2622)
IPAD = (2752, 2064)
# phone-2 has a black band left by the render, so it is not used.
IPHONE_SHOTS = ("phone-1", "phone-3", "phone-4")


def compose(raw, caption, size, font_size, radius):
    w, h = size
    img = play.gradient(size, *BG)
    d = ImageDraw.Draw(img)
    fnt = play.font("Bold", font_size)
    y = int(font_size * 1.3)
    for line in play.wrap(d, caption, fnt, w - 160):
        d.text(((w - d.textlength(line, font=fnt)) / 2, y), line, font=fnt, fill="white")
        y += int(font_size * 1.28)
    top = y + int(font_size * 0.6)
    box_w, box_h = w - 160, h - top - 80
    scale = min(box_w / raw.width, box_h / raw.height)
    shot = raw.convert("RGB").resize((int(raw.width * scale), int(raw.height * scale)), Image.LANCZOS)
    shot = play.rounded(shot, radius)
    img.paste(shot, ((w - shot.width) // 2, top), shot)
    return img.convert("RGB")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    n_phone = n_tablet = 0
    for path in sorted(RAW.glob("*.png")):
        stem, _, caption = path.stem.partition("__")
        raw = Image.open(path)
        if stem.startswith("phone"):
            if stem not in IPHONE_SHOTS:
                continue
            n_phone += 1
            compose(raw, caption, IPHONE, 76, 44).save(OUT / f"iphone-{n_phone}.png", optimize=True)
        else:
            n_tablet += 1
            compose(raw, caption, IPAD, 92, 32).save(OUT / f"ipad-{n_tablet}.png", optimize=True)
    for path in sorted(OUT.glob("*.png")):
        im = Image.open(path)
        print(path.name, im.size, im.mode, path.stat().st_size // 1024, "KB")


if __name__ == "__main__":
    main()
