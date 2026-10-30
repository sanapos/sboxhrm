"""Tạo font ký hiệu SboxSymbols (mũi tên, ①–⑩, ⋮, ✓, hình khối) từ DejaVu Sans.

BeVietnamPro không có các ký tự này → trên web chữ «Cài đặt → Thiết lập ca» mất mũi tên.
SboxSymbols chỉ chứa ký hiệu nên làm font dự phòng an toàn (không kéo font CJK hệ thống
như Arial trên Android 6). DejaVu cho phép sửa + phân phối nếu đổi tên font (xem
assets/fonts/SboxSymbols-LICENSE.txt).

Dùng: python tool/build_symbol_font.py [thư mục chứa DejaVuSans.ttf, mặc định C:/Windows/Fonts]
"""
import pathlib
import sys

from fontTools import subset
from fontTools.ttLib import TTFont

SRC = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "C:/Windows/Fonts")
OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "fonts"

UNICODES = (
    list(range(0x2190, 0x2200))  # mũi tên
    + [0x00D7, 0x2212, 0x2248, 0x2260, 0x2264, 0x2265, 0x22EE, 0x22EF]  # × − ≈ ≠ ≤ ≥ ⋮ ⋯
    + list(range(0x2460, 0x246A))  # ①–⑩
    + list(range(0x25A0, 0x2600))  # hình khối ▲ ▶ ● ○
    + [0x2605, 0x2606, 0x26A0, 0x2713, 0x2714, 0x2715, 0x2716, 0x2717, 0x2718]  # ★ ☆ ⚠ ✓ ✔ ✕ ✖ ✗ ✘
)

for src_name, weight in [("DejaVuSans.ttf", "Regular"), ("DejaVuSans-Bold.ttf", "Bold")]:
    font = TTFont(SRC / src_name)
    opts = subset.Options()
    opts.name_IDs = []  # bỏ tên gốc, đặt tên mới bên dưới
    opts.notdef_outline = True
    sub = subset.Subsetter(opts)
    sub.populate(unicodes=UNICODES)
    sub.subset(font)
    name = font["name"]
    for nid, val in [(1, "SboxSymbols"), (2, weight), (4, f"SboxSymbols {weight}"), (6, f"SboxSymbols-{weight}")]:
        name.setName(val, nid, 3, 1, 0x409)
        name.setName(val, nid, 1, 0, 0)
    out = OUT / f"SboxSymbols-{weight}.ttf"
    font.save(out)
    print(f"{out.name}: {out.stat().st_size // 1024} KB")
