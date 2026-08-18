using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Formats.Jpeg;
using SixLabors.ImageSharp.Processing;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Nén ảnh upload: resize cạnh dài + JPEG để giảm dung lượng server và tải nhanh.
/// Không đụng PDF/video/SVG/GIF động — trả lại stream gốc nếu không phải ảnh raster.
/// </summary>
public static class ImageOptimizeHelper
{
    public const int ProductMaxEdge = 1200;
    public const int ProductJpegQuality = 75;

    /// <summary>Ảnh catalog mẫu Super Admin — đủ nét khi hiển thị lưới POS / thẻ món.</summary>
    public const int SampleCatalogMaxEdge = 1920;
    public const int SampleCatalogJpegQuality = 88;

    public const int PhotoMaxEdge = 1280;
    public const int PhotoJpegQuality = 72;

    public const int FieldMaxEdge = 1024;
    public const int FieldJpegQuality = 65;

    /// <summary>
    /// Đọc toàn bộ input, tối ưu nếu là ảnh raster. Trả MemoryStream ở vị trí 0 và tên file gợi ý (.jpg).
    /// </summary>
    public static async Task<(MemoryStream Stream, string FileName, bool Optimized)> OptimizeAsync(
        Stream input,
        string? originalFileName,
        int maxEdge = ProductMaxEdge,
        int jpegQuality = ProductJpegQuality,
        CancellationToken ct = default)
    {
        await using var buffer = new MemoryStream();
        await input.CopyToAsync(buffer, ct);
        var bytes = buffer.ToArray();
        return Optimize(bytes, originalFileName, maxEdge, jpegQuality);
    }

    public static (MemoryStream Stream, string FileName, bool Optimized) Optimize(
        byte[] bytes,
        string? originalFileName,
        int maxEdge = ProductMaxEdge,
        int jpegQuality = ProductJpegQuality)
    {
        var safeName = string.IsNullOrWhiteSpace(originalFileName) ? "image.jpg" : originalFileName.Trim();
        var ext = Path.GetExtension(safeName).ToLowerInvariant();

        // Không nén các định dạng không phải ảnh raster / giữ animation.
        if (ext is ".svg" or ".pdf" or ".mp4" or ".webm" or ".mov" or ".gif")
        {
            var passthrough = new MemoryStream(bytes);
            passthrough.Position = 0;
            return (passthrough, safeName, false);
        }

        try
        {
            using var image = Image.Load(bytes);
            var w = image.Width;
            var h = image.Height;
            if (w <= 0 || h <= 0)
            {
                var passthrough = new MemoryStream(bytes);
                passthrough.Position = 0;
                return (passthrough, safeName, false);
            }

            if (w > maxEdge || h > maxEdge)
            {
                var ratio = Math.Min((double)maxEdge / w, (double)maxEdge / h);
                var nw = Math.Max(1, (int)Math.Round(w * ratio));
                var nh = Math.Max(1, (int)Math.Round(h * ratio));
                image.Mutate(x => x.Resize(nw, nh));
            }

            var output = new MemoryStream();
            image.Save(output, new JpegEncoder { Quality = Math.Clamp(jpegQuality, 40, 95) });
            output.Position = 0;

            // Nếu JPEG sau nén lớn hơn gốc (hiếm, PNG nhỏ) → giữ gốc.
            if (output.Length >= bytes.Length && bytes.Length > 0)
            {
                output.Dispose();
                var passthrough = new MemoryStream(bytes);
                passthrough.Position = 0;
                return (passthrough, safeName, false);
            }

            var jpgName = Path.ChangeExtension(safeName, ".jpg") ?? "image.jpg";
            if (string.IsNullOrWhiteSpace(Path.GetFileNameWithoutExtension(jpgName)))
                jpgName = "image.jpg";
            return (output, jpgName, true);
        }
        catch
        {
            var passthrough = new MemoryStream(bytes);
            passthrough.Position = 0;
            return (passthrough, safeName, false);
        }
    }

    public static bool IsRasterImageExtension(string? extension)
    {
        var ext = (extension ?? "").ToLowerInvariant();
        return ext is ".jpg" or ".jpeg" or ".jfif" or ".png" or ".webp" or ".bmp"
            or ".tif" or ".tiff" or ".heic" or ".heif" or ".avif";
    }
}
