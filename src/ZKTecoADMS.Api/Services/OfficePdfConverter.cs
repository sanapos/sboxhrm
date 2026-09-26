using System.Diagnostics;
using System.Text.RegularExpressions;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Chuyển sang PDF: mẫu Word (.docx) bằng LibreOffice headless; mẫu HTML bằng Chromium headless
/// (cùng bộ máy với bản in trên trình duyệt — LibreOffice đọc CSS kém, vỡ căn lề / khối ký).
/// Mỗi lần chạy dùng thư mục tạm + profile riêng để chạy song song không khóa nhau.
/// </summary>
public sealed class OfficePdfConverter(ILogger<OfficePdfConverter> logger)
{
    static readonly SemaphoreSlim Gate = new(2, 2); // soffice ~200 MB RAM mỗi tiến trình
    static readonly string[] Candidates =
    [
        "/usr/bin/soffice",
        "/usr/lib/libreoffice/program/soffice",
        @"C:\Program Files\LibreOffice\program\soffice.exe",
    ];

    static readonly string[] ChromiumCandidates =
    [
        "/usr/bin/chromium",
        "/usr/bin/chromium-browser",
        @"C:\Program Files\Google\Chrome\Application\chrome.exe",
    ];

    public bool IsAvailable => Executable != null;

    static string? Executable => Candidates.FirstOrDefault(File.Exists);
    static string? Chromium => ChromiumCandidates.FirstOrDefault(File.Exists);

    /// <summary>HTML (mẫu in A4) → PDF bằng Chromium; không có Chromium thì dùng LibreOffice.</summary>
    public async Task<byte[]> HtmlToPdfAsync(string html, CancellationToken ct)
    {
        var chromium = Chromium;
        var page = EnsureA4(SanitizeHtml(html));
        if (chromium == null)
            return await ToPdfAsync([.. System.Text.Encoding.UTF8.GetPreamble(), .. System.Text.Encoding.UTF8.GetBytes(page)], ".html", ct);

        // Thư mục cha cố định /tmp/sbox-pdf/ = thư mục duy nhất policy Chromium cho mở file://.
        var work = Path.Combine(Path.GetTempPath(), "sbox-pdf", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        var src = Path.Combine(work, "doc.html");
        var pdf = Path.Combine(work, "doc.pdf");
        // BOM: đã bỏ <meta> khi làm sạch → trình duyệt vẫn nhận đúng UTF-8 (tiếng Việt).
        await File.WriteAllTextAsync(src, page, new System.Text.UTF8Encoding(true), ct);

        await Gate.WaitAsync(ct);
        try
        {
            var psi = new ProcessStartInfo(chromium)
            {
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                WorkingDirectory = work,
            };
            // Mẫu HTML do cửa hàng tự soạn → coi là không tin cậy: đã bỏ script / on*= (không tắt JS bằng
            // cờ được — Chromium in PDF cần JS nội bộ), chặn mạng (không gọi ra dịch vụ nội bộ). Ảnh đều nhúng data:. Khung / tài liệu file:// ngoài thư mục job bằng
            // policy Chromium trong image Docker (/etc/chromium/policies/managed/sbox-pdf.json).
            foreach (var a in new[]
            {
                "--headless", "--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage",
                "--no-pdf-header-footer", "--hide-scrollbars",
                "--host-resolver-rules=MAP * ~NOTFOUND",
                "--proxy-server=127.0.0.1:9", "--proxy-bypass-list=<-loopback>",
                "--disable-extensions", "--disable-background-networking", "--no-first-run",
                "--run-all-compositor-stages-before-draw", "--virtual-time-budget=8000",
                "--user-data-dir=" + Path.Combine(work, "profile"),
                "--print-to-pdf=" + pdf,
                new Uri(src).AbsoluteUri,
            })
                psi.ArgumentList.Add(a);

            using var proc = Process.Start(psi) ?? throw new InvalidOperationException("Không chạy được Chromium.");
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeout.CancelAfter(TimeSpan.FromSeconds(60));
            try
            {
                await proc.WaitForExitAsync(timeout.Token);
            }
            catch (OperationCanceledException)
            {
                try { proc.Kill(entireProcessTree: true); } catch { /* đã thoát */ }
                throw new InvalidOperationException("Tạo PDF quá lâu — thử lại.");
            }
            if (!File.Exists(pdf))
            {
                var err = await proc.StandardError.ReadToEndAsync(ct);
                logger.LogWarning("Chromium print-to-pdf failed ({Code}): {Err}", proc.ExitCode, err.Length > 800 ? err[..800] : err);
                throw new InvalidOperationException("Không tạo được PDF — thử lại.");
            }
            return await File.ReadAllBytesAsync(pdf, ct);
        }
        finally
        {
            Gate.Release();
            try { Directory.Delete(work, recursive: true); } catch { /* dọn sau */ }
        }
    }

    static readonly Regex DangerousBlock = new(
        @"<(script|iframe|frame|frameset|object|embed|applet|portal|noscript|template)\b[\s\S]*?</\1\s*>",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);
    static readonly Regex DangerousTag = new(
        @"</?(script|iframe|frame|frameset|object|embed|applet|portal|base|link|meta|noscript|template)\b[^>]*>",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);
    static readonly Regex UrlAttr = new(
        @"\s(src|href|srcset|poster|data|xlink:href|background|action|formaction|lowsrc|dynsrc|longdesc|manifest|ping|cite)\s*=\s*(""[^""]*""|'[^']*'|[^\s>]+)",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);
    static readonly Regex CssUrl = new(@"url\s*\(\s*(['""]?)([^'"")]*)\1\s*\)", RegexOptions.IgnoreCase | RegexOptions.Compiled);
    static readonly Regex EventAttr = new(
        @"\son[a-z]+\s*=\s*(""[^""]*""|'[^']*'|[^\s>]+)",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);
    static readonly Regex CssImport = new(@"@import[^;]*;?", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    /// <summary>
    /// Bỏ phần có thể đọc file / gọi mạng khi dựng PDF trên máy chủ: script, on*=, khung (iframe/object/embed),
    /// base / link / meta refresh, @import, mọi URL không phải ảnh data: hoặc neo #.
    /// Chữ + bảng + CSS nội tuyến + ảnh nhúng (con dấu, ảnh sản phẩm) giữ nguyên.
    /// </summary>
    public static string SanitizeHtml(string html)
    {
        var s = DangerousBlock.Replace(html ?? "", "");
        s = DangerousTag.Replace(s, "");
        s = CssImport.Replace(s, "");
        s = EventAttr.Replace(s, "");
        s = UrlAttr.Replace(s, m => SafeUrl(m.Groups[2].Value.Trim('"', '\'')) ? m.Value : "");
        s = CssUrl.Replace(s, m => SafeUrl(m.Groups[2].Value) ? m.Value : "url()");
        return s;
    }

    static bool SafeUrl(string raw)
    {
        var v = new string(System.Net.WebUtility.HtmlDecode(raw).Where(c => !char.IsWhiteSpace(c) && !char.IsControl(c)).ToArray());
        return v.StartsWith('#') || v.StartsWith("data:image/", StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>Khổ A4 + lề in (mẫu HTML không khai báo @page thì Chromium mặc định khổ Letter).</summary>
    static string EnsureA4(string html)
    {
        const string css = "<style>@page{size:A4;margin:10mm 8mm}html,body{-webkit-print-color-adjust:exact;print-color-adjust:exact}</style>";
        // Bảng không tràn khổ giấy (mẫu có tổng độ rộng cột px lớn hơn trang) — khớp khung soạn / xem trước.
        const string tableCss = "<style>table{max-width:100% !important;table-layout:auto !important}img{max-width:100%;height:auto}</style>";
        var headEnd = html.IndexOf("</head>", StringComparison.OrdinalIgnoreCase);
        if (headEnd >= 0) html = html.Insert(headEnd, tableCss);
        if (html.Contains("@page", StringComparison.OrdinalIgnoreCase)) return html;
        var head = html.IndexOf("</head>", StringComparison.OrdinalIgnoreCase);
        if (head >= 0) return html.Insert(head, css);
        return "<!DOCTYPE html><html><head><meta charset=\"utf-8\">" + css + "</head><body>" + html + "</body></html>";
    }

    /// <param name="extension">".docx" hoặc ".html"</param>
    public async Task<byte[]> ToPdfAsync(byte[] input, string extension, CancellationToken ct)
    {
        var exe = Executable
            ?? throw new InvalidOperationException("Máy chủ chưa cài LibreOffice — chưa xuất được PDF, hãy tải bản Word.");

        var work = Path.Combine(Path.GetTempPath(), "sbox-pdf-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        var src = Path.Combine(work, "doc" + extension);
        await File.WriteAllBytesAsync(src, input, ct);

        await Gate.WaitAsync(ct);
        try
        {
            var psi = new ProcessStartInfo(exe)
            {
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                WorkingDirectory = work,
            };
            psi.ArgumentList.Add("-env:UserInstallation=file://" + Path.Combine(work, "profile").Replace('\\', '/'));
            psi.ArgumentList.Add("--headless");
            psi.ArgumentList.Add("--norestore");
            psi.ArgumentList.Add("--convert-to");
            psi.ArgumentList.Add("pdf");
            psi.ArgumentList.Add("--outdir");
            psi.ArgumentList.Add(work);
            psi.ArgumentList.Add(src);

            using var proc = Process.Start(psi) ?? throw new InvalidOperationException("Không chạy được LibreOffice.");
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeout.CancelAfter(TimeSpan.FromSeconds(90));
            try
            {
                await proc.WaitForExitAsync(timeout.Token);
            }
            catch (OperationCanceledException)
            {
                try { proc.Kill(entireProcessTree: true); } catch { /* đã thoát */ }
                throw new InvalidOperationException("Tạo PDF quá lâu — thử lại hoặc tải bản Word.");
            }

            var pdf = Path.Combine(work, "doc.pdf");
            if (proc.ExitCode != 0 || !File.Exists(pdf))
            {
                var err = await proc.StandardError.ReadToEndAsync(ct);
                logger.LogWarning("LibreOffice convert failed ({Code}): {Err}", proc.ExitCode, err);
                throw new InvalidOperationException("Không tạo được PDF — thử lại hoặc tải bản Word.");
            }
            return await File.ReadAllBytesAsync(pdf, ct);
        }
        finally
        {
            Gate.Release();
            try { Directory.Delete(work, recursive: true); } catch { /* dọn sau */ }
        }
    }
}
