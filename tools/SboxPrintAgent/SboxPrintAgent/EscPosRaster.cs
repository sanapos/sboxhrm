using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Runtime.InteropServices;

namespace SboxPrintAgent;

/// <summary>
/// Vẽ chữ tiếng Việt (font Windows) → bitmap → ESC/POS GS v 0.
/// XP-80C / Zywell không đọc UTF-8 firmware; in ảnh mới giữ dấu đúng.
/// </summary>
public static class EscPosRaster
{
    public static int PaperDots(string? paperSize)
    {
        var p = (paperSize ?? "").Trim().ToUpperInvariant();
        if (p.Contains("58") || p.Contains("K58")) return 384;
        return 576;
    }

    public static bool NeedsRaster(string? textMode, string? printerBrand)
    {
        // Windows Agent luôn ưu tiên raster cho job JSON; giữ API nếu sau này cần.
        var mode = (textMode ?? "").Trim().ToLowerInvariant();
        if (mode is "ascii" or "tcvn3" or "cp1258") return false;
        return true;
    }

    public static byte[] FromText(string text, int paperDots = 576, bool cut = true)
    {
        paperDots = Math.Clamp(paperDots, 192, 576);
        var lines = (text ?? "")
            .Replace("\r\n", "\n")
            .Replace('\r', '\n')
            .Split('\n');

        const int pad = 4;
        const float fontPx = 22f;
        const float lineGap = 2f;
        var contentW = paperDots - pad * 2;

        using var font = CreateVnFont(fontPx, FontStyle.Regular);
        using var bold = CreateVnFont(fontPx, FontStyle.Bold);

        var heights = new float[lines.Length];
        var totalH = pad * 2f;
        using (var measureBmp = new Bitmap(8, 8))
        using (var mg = Graphics.FromImage(measureBmp))
        {
            mg.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            for (var i = 0; i < lines.Length; i++)
            {
                var line = lines[i];
                if (string.IsNullOrEmpty(line))
                {
                    heights[i] = fontPx * 0.55f;
                    totalH += heights[i] + lineGap;
                    continue;
                }
                var useBold = LooksLikeTitle(line);
                var sz = mg.MeasureString(line, useBold ? bold : font, contentW);
                heights[i] = Math.Max(fontPx, sz.Height);
                totalH += heights[i] + lineGap;
            }
        }

        totalH += 6; // feed trước cắt (gọn)
        var bmpH = Math.Max(32, (int)Math.Ceiling(totalH));

        using var bmp = new Bitmap(paperDots, bmpH, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(bmp))
        {
            g.Clear(Color.White);
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.HighQuality;
            var y = (float)pad;
            using var brush = new SolidBrush(Color.Black);
            for (var i = 0; i < lines.Length; i++)
            {
                var line = lines[i];
                if (!string.IsNullOrEmpty(line))
                {
                    var useBold = LooksLikeTitle(line);
                    var rect = new RectangleF(pad, y, contentW, heights[i] + 4);
                    g.DrawString(line, useBold ? bold : font, brush, rect);
                }
                y += heights[i] + lineGap;
            }
        }

        using var ms = new MemoryStream();
        ms.WriteByte(0x1B); ms.WriteByte(0x40); // init
        WriteGsV0(ms, bmp);
        if (cut)
        {
            ms.WriteByte(0x1B); ms.WriteByte(0x64); ms.WriteByte(0x02);
            ms.WriteByte(0x1D); ms.WriteByte(0x56); ms.WriteByte(0x00);
        }
        return ms.ToArray();
    }

    static bool LooksLikeTitle(string line)
    {
        var t = line.Trim();
        return t.StartsWith("***", StringComparison.Ordinal)
               || t.StartsWith("===", StringComparison.Ordinal);
    }

    static Font CreateVnFont(float px, FontStyle style)
    {
        foreach (var name in new[] { "Segoe UI", "Arial", "Tahoma", "Microsoft Sans Serif" })
        {
            try { return new Font(name, px, style, GraphicsUnit.Pixel); }
            catch { /* try next */ }
        }
        return new Font(FontFamily.GenericSansSerif, px, style, GraphicsUnit.Pixel);
    }

    static void WriteGsV0(Stream ms, Bitmap bmp)
    {
        var w = bmp.Width;
        var h = bmp.Height;
        var bytesPerRow = (w + 7) / 8;
        var raster = new byte[bytesPerRow * h];

        var data = bmp.LockBits(
            new Rectangle(0, 0, w, h),
            ImageLockMode.ReadOnly,
            PixelFormat.Format32bppArgb);
        try
        {
            var stride = Math.Abs(data.Stride);
            var buf = new byte[stride * h];
            Marshal.Copy(data.Scan0, buf, 0, buf.Length);
            for (var y = 0; y < h; y++)
            {
                for (var xByte = 0; xByte < bytesPerRow; xByte++)
                {
                    byte b = 0;
                    for (var bit = 0; bit < 8; bit++)
                    {
                        var x = xByte * 8 + bit;
                        if (x >= w) continue;
                        var idx = y * stride + x * 4;
                        // BGRA
                        var blue = buf[idx];
                        var green = buf[idx + 1];
                        var red = buf[idx + 2];
                        var lum = 0.299 * red + 0.587 * green + 0.114 * blue;
                        if (lum < 160)
                            b |= (byte)(0x80 >> bit);
                    }
                    raster[y * bytesPerRow + xByte] = b;
                }
            }
        }
        finally
        {
            bmp.UnlockBits(data);
        }

        ms.WriteByte(0x1D);
        ms.WriteByte(0x76);
        ms.WriteByte(0x30);
        ms.WriteByte(0x00);
        ms.WriteByte((byte)(bytesPerRow & 0xFF));
        ms.WriteByte((byte)((bytesPerRow >> 8) & 0xFF));
        ms.WriteByte((byte)(h & 0xFF));
        ms.WriteByte((byte)((h >> 8) & 0xFF));
        ms.Write(raster, 0, raster.Length);
    }
}
