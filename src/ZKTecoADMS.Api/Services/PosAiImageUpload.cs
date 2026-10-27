namespace ZKTecoADMS.Api.Services;

/// <summary>Nhận dạng ảnh upload cho các tính năng AI đọc ảnh (hóa đơn NCC…) — cùng quy tắc với «AI thêm menu».</summary>
public static class PosAiImageUpload
{
    static readonly HashSet<string> ImageTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        "image/jpeg", "image/png", "image/webp", "image/heic", "image/heif",
    };

    /// <summary>
    /// MIME ảnh theo nội dung file trước (tên / Content-Type từ trình duyệt có thể thiếu hoặc sai), rồi theo
    /// Content-Type, cuối cùng theo đuôi file. Không phải ảnh nhận được → null.
    /// </summary>
    public static string? ResolveMime(byte[] bytes, string? contentType, string? fileName)
    {
        var mime = Sniff(bytes)
                   ?? (string.IsNullOrWhiteSpace(contentType) || contentType == "application/octet-stream"
                       ? GuessMime(fileName)
                       : contentType);
        return ImageTypes.Contains(mime) ? mime : null;
    }

    public static string? Sniff(byte[] b)
    {
        if (b.Length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return "image/jpeg";
        if (b.Length >= 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return "image/png";
        if (b.Length >= 12 && b[0] == (byte)'R' && b[1] == (byte)'I' && b[2] == (byte)'F' && b[3] == (byte)'F'
            && b[8] == (byte)'W' && b[9] == (byte)'E' && b[10] == (byte)'B' && b[11] == (byte)'P') return "image/webp";
        if (b.Length >= 12 && b[4] == (byte)'f' && b[5] == (byte)'t' && b[6] == (byte)'y' && b[7] == (byte)'p')
        {
            var brand = System.Text.Encoding.ASCII.GetString(b, 8, 4);
            if (brand is "heic" or "heix" or "hevc" or "mif1" or "msf1") return "image/heic";
        }
        return null;
    }

    static string GuessMime(string? fileName) => Path.GetExtension(fileName ?? "").ToLowerInvariant() switch
    {
        ".png" => "image/png",
        ".webp" => "image/webp",
        ".heic" => "image/heic",
        ".heif" => "image/heif",
        _ => "image/jpeg",
    };
}
