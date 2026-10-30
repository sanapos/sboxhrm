"""PNG ảnh hướng dẫn (render-guide-shots.ps1) → WebP. Dùng: guide_shots_webp.py <src> <dst> [quality]"""
import pathlib
import sys

from PIL import Image

src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
q = int(sys.argv[3]) if len(sys.argv) > 3 else 82
dst.mkdir(parents=True, exist_ok=True)
n = 0
for p in sorted(src.glob("*.png")):
    Image.open(p).convert("RGB").save(dst / (p.stem + ".webp"), "WEBP", quality=q, method=6)
    n += 1
print(f"{n} images -> {dst}")
