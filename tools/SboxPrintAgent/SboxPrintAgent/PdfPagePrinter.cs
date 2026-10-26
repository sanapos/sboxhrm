using System.Drawing;
using System.Drawing.Printing;
using Windows.Data.Pdf;
using Windows.Storage.Streams;

namespace SboxPrintAgent;

/// <summary>
/// In chứng từ khổ trang (A4/A5, payload PdfBase64) ra máy in văn phòng đã cài driver Windows:
/// dựng từng trang PDF thành ảnh (Windows.Data.Pdf) rồi in qua GDI — khác máy nhiệt (RAW ESC/POS).
/// </summary>
public static class PdfPagePrinter
{
    const int RenderDpi = 200;

    public static async Task PrintAsync(
        string printerName, byte[] pdf, int copies, string docName,
        string? printToFile = null, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(printerName))
            throw new InvalidOperationException("Máy in A4/A5 phải là máy in đã cài trên Windows.");
        if (pdf.Length < 5 || pdf[0] != 0x25 || pdf[1] != 0x50 || pdf[2] != 0x44 || pdf[3] != 0x46)
            throw new InvalidOperationException("Dữ liệu in không phải PDF.");

        var (pages, sizesInch) = await RenderPagesAsync(pdf, ct);
        try
        {
            if (pages.Count == 0) throw new InvalidOperationException("PDF không có trang nào.");
            PrintBitmaps(printerName, pages, sizesInch[0], Math.Clamp(copies, 1, 10), docName, printToFile);
        }
        finally
        {
            foreach (var b in pages) b.Dispose();
        }
    }

    static async Task<(List<Bitmap> Pages, List<SizeF> SizesInch)> RenderPagesAsync(
        byte[] pdf, CancellationToken ct)
    {
        using var mem = new InMemoryRandomAccessStream();
        using (var writer = new DataWriter(mem.GetOutputStreamAt(0)))
        {
            writer.WriteBytes(pdf);
            await writer.StoreAsync();
            await writer.FlushAsync();
            writer.DetachStream();
        }
        var doc = await PdfDocument.LoadFromStreamAsync(mem);
        var pages = new List<Bitmap>();
        var sizes = new List<SizeF>();
        for (uint i = 0; i < doc.PageCount; i++)
        {
            ct.ThrowIfCancellationRequested();
            using var page = doc.GetPage(i);
            // Size: DIP (1/96 inch).
            var wIn = (float)(page.Size.Width / 96.0);
            var hIn = (float)(page.Size.Height / 96.0);
            var opts = new PdfPageRenderOptions
            {
                DestinationWidth = (uint)Math.Round(wIn * RenderDpi),
                DestinationHeight = (uint)Math.Round(hIn * RenderDpi),
                BackgroundColor = Windows.UI.Color.FromArgb(255, 255, 255, 255),
            };
            using var png = new InMemoryRandomAccessStream();
            await page.RenderToStreamAsync(png, opts);
            using var net = png.AsStreamForRead();
            using var buf = new MemoryStream();
            await net.CopyToAsync(buf, ct);
            buf.Position = 0;
            using var img = Image.FromStream(buf);
            pages.Add(new Bitmap(img));
            sizes.Add(new SizeF(wIn, hIn));
        }
        return (pages, sizes);
    }

    static void PrintBitmaps(
        string printerName, List<Bitmap> pages, SizeF pageInch, int copies, string docName,
        string? printToFile)
    {
        using var pd = new PrintDocument();
        pd.PrinterSettings.PrinterName = WindowsSpooler.ResolvePrinterName(printerName);
        if (!pd.PrinterSettings.IsValid)
            throw new InvalidOperationException(
                $"Không thấy máy in Windows «{printerName}». Kiểm tra máy đã cài driver.");
        if (!string.IsNullOrWhiteSpace(printToFile))
        {
            pd.PrinterSettings.PrintToFile = true;
            pd.PrinterSettings.PrintFileName = printToFile;
        }
        pd.DocumentName = docName;
        pd.PrintController = new StandardPrintController(); // không hiện hộp «Đang in…»
        pd.OriginAtMargins = false;
        var paper = PickPaper(pd.PrinterSettings, pageInch);
        if (paper != null) pd.DefaultPageSettings.PaperSize = paper;
        pd.DefaultPageSettings.Landscape = false;

        var total = pages.Count * copies;
        var index = 0;
        pd.PrintPage += (_, e) =>
        {
            var bmp = pages[index % pages.Count];
            var g = e.Graphics!;
            // Đơn vị 1/100 inch; gốc tọa độ ở mép vùng in được → lùi lại lề cứng để khớp mép giấy.
            var pageW = e.PageBounds.Width;
            var pageH = e.PageBounds.Height;
            var scale = Math.Min(pageW / (float)bmp.Width, pageH / (float)bmp.Height);
            var w = bmp.Width * scale;
            var h = bmp.Height * scale;
            var x = (pageW - w) / 2 - e.PageSettings.HardMarginX;
            var y = -e.PageSettings.HardMarginY;
            g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
            g.DrawImage(bmp, new RectangleF(x, y, w, h));
            index++;
            e.HasMorePages = index < total;
        };
        pd.Print();
    }

    /// <summary>Chọn khổ giấy của driver gần nhất với trang PDF (A4 / A5…).</summary>
    static PaperSize? PickPaper(PrinterSettings ps, SizeF pageInch)
    {
        var wantW = pageInch.Width * 100;
        var wantH = pageInch.Height * 100;
        PaperSize? best = null;
        var bestDiff = float.MaxValue;
        foreach (PaperSize p in ps.PaperSizes)
        {
            var diff = Math.Abs(p.Width - wantW) + Math.Abs(p.Height - wantH);
            if (diff < bestDiff)
            {
                bestDiff = diff;
                best = p;
            }
        }
        // Lệch > ~1 cm → để khổ mặc định của driver.
        return bestDiff <= 40 ? best : null;
    }
}
