"""Ảnh App Store SBOX BOSS từ ảnh dựng bằng code (flutter_client/build/store_shots/raw):
iPhone 6.9" 1320x2868, iPad 13" 2064x2752 (dọc). Nền xanh đen logo, vạch vàng, chữ trắng.
Ảnh iPad là màn BOSS dựng ở cỡ iPad thật (1032x1376 pt), không ghép màn điện thoại."""
import importlib.util
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
RAW = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "flutter_client" / "build" / "store_shots" / "raw"
OUT = ROOT / "dist" / "app-store-assets" / "boss"
spec = importlib.util.spec_from_file_location("play", ROOT / "scripts" / "make-play-assets.py")
play = importlib.util.module_from_spec(spec)
spec.loader.exec_module(play)
BG = ("#16203A", "#2C3C5E")
GOLD = "#EFC66A"

SHOTS = [
    ("1-tong-quan", "Doanh thu hôm nay, việc cần xử lý"),
    ("2-can-duyet", "Duyệt yêu cầu của nhân viên ngay trên máy"),
    ("4-kinh-doanh", "Báo cáo kinh doanh, lợi nhuận"),
    ("5-quan-ly", "Quản lý bán hàng, tiền, kho, nhân viên"),
    ("6-thu-chi", "Phiếu thu chi, sổ quỹ"),
]


def caption(d, text, w, y, size):
    fnt = play.font("Bold", size)
    for line in play.wrap(d, text, fnt, w - 180):
        d.text(((w - d.textlength(line, font=fnt)) / 2, y), line, font=fnt, fill="white")
        y += int(size * 1.28)
    return y


def compose(raw, cap, size, cap_size, radius, side):
    w, h = size
    img = play.gradient(size, *BG)
    d = ImageDraw.Draw(img)
    bar = int(w * 0.09)
    d.rounded_rectangle(((w - bar) // 2, 80, (w + bar) // 2, 94), 7, fill=GOLD)
    top = caption(d, cap, w, 150, cap_size) + 50
    bw, bh = w - 2 * side, h - top
    s = min(bw / raw.width, (bh + radius) / raw.height)
    shot = raw.convert("RGB").resize((int(raw.width * s), int(raw.height * s)), Image.LANCZOS)
    shot = play.rounded(shot, radius)
    # Khung chạm đáy ảnh: phần bo góc dưới nằm ngoài, giống máy thật nhô lên từ cạnh dưới.
    img.paste(shot, ((w - shot.width) // 2, top), shot)
    return img.convert("RGB")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for old in list(OUT.glob("iphone69-*.png")) + list(OUT.glob("ipad13-*.png")):
        old.unlink()
    n = 0
    for i, (name, cap) in enumerate(SHOTS, 1):
        p = RAW / f"iphone69-{name}.png"
        if p.exists():
            compose(Image.open(p), cap, (1320, 2868), 92, 64, 110).save(OUT / f"iphone69-{i}.png", optimize=True)
            n += 1
        p = RAW / f"ipad13-{name}.png"
        if p.exists():
            compose(Image.open(p), cap, (2064, 2752), 104, 44, 120).save(OUT / f"ipad13-{i}.png", optimize=True)
            n += 1
    ims = []
    for f in sorted(OUT.glob("*.png")):
        im = Image.open(f)
        print(f.name, im.size, im.mode)
        t = im.copy()
        t.thumbnail((480, 480))
        ims.append(t)
    sheet = Image.new("RGB", (sum(i.width for i in ims) + 10 * len(ims), 490), "gray")
    x = 0
    for t in ims:
        sheet.paste(t, (x, 0))
        x += t.width + 10
    sheet.save(RAW.parent / "store_sheet.png")
    print("ok", n)


main()
