from PIL import Image
from pathlib import Path

logo_src = Path(r"C:\Users\TH DECOR\.cursor\projects\e-SBOX-CURSOR-ZKTecoADMS-master\assets\c__Users_TH_DECOR_AppData_Roaming_Cursor_User_workspaceStorage_empty-window_images_z7810296848764_bea322b242209588999e55ecf55e6a2e-Photoroom-7bf9c7d0-e384-41c3-8b1b-ceabf4718fb8.png")
out_dir = Path("flutter_client/web/images/landing")
out_dir.mkdir(parents=True, exist_ok=True)

im = Image.open(logo_src).convert("RGBA")
# crop to opaque bbox
bbox = im.getbbox()
if bbox:
    pad = 6
    x0 = max(0, bbox[0] - pad)
    y0 = max(0, bbox[1] - pad)
    x1 = min(im.width, bbox[2] + pad)
    y1 = min(im.height, bbox[3] + pad)
    im = im.crop((x0, y0, x1, y1))

# Clean icon with alpha
im.save(out_dir / "sbox-logo.png", "PNG")
print("sbox-logo", im.size)

# White mark: keep near-white pixels only
px = im.load()
w, h = im.size
white = Image.new("RGBA", (w, h), (0, 0, 0, 0))
wpx = white.load()
for y in range(h):
    for x in range(w):
        r, g, b, a = px[x, y]
        if a < 20:
            continue
        # white / light glyph
        if r > 185 and g > 185 and b > 185:
            wpx[x, y] = (255, 255, 255, 255)
white.save(out_dir / "sbox-logo-white.png", "PNG")
print("sbox-logo-white", white.getbbox())

# Also copy into flutter assets if logo.png exists
assets = Path("flutter_client/assets")
if assets.exists():
    im.save(assets / "sbox-logo.png", "PNG")
    print("copied to assets")
print("done")
