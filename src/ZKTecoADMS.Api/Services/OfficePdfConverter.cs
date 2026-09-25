using System.Diagnostics;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Chuyển .docx / .html → PDF bằng LibreOffice headless (cài trong image API).
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

    public bool IsAvailable => Executable != null;

    static string? Executable => Candidates.FirstOrDefault(File.Exists);

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
