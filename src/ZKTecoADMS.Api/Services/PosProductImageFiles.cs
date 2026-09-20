namespace ZKTecoADMS.Api.Services;

/// <summary>Đọc ảnh sản phẩm POS từ wwwroot để nhúng base64 vào HTML in.</summary>
public static class PosProductImageFiles
{
    public static string? ResolvePath(string contentRootPath, string? imageUrl)
    {
        if (string.IsNullOrWhiteSpace(imageUrl)) return null;

        var normalized = imageUrl.Trim().Replace('\\', '/');
        if (normalized.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
            || normalized.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                normalized = new Uri(normalized).AbsolutePath.TrimStart('/');
            }
            catch
            {
                return null;
            }
        }
        else
        {
            normalized = normalized.TrimStart('/');
        }

        if (normalized.StartsWith("wwwroot/", StringComparison.OrdinalIgnoreCase))
            normalized = normalized["wwwroot/".Length..];

        var wwwroot = Path.GetFullPath(Path.Combine(contentRootPath, "wwwroot"));
        var candidates = new List<string> { normalized };

        if (normalized.StartsWith("stores/", StringComparison.OrdinalIgnoreCase)
            && normalized.Contains("uploads/pos-products", StringComparison.OrdinalIgnoreCase))
        {
            var parts = normalized.Split('/', StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length >= 4)
                candidates.Add(string.Join('/', parts.Skip(1)));
        }
        else if (normalized.Contains("uploads/pos-products", StringComparison.OrdinalIgnoreCase)
                 && !normalized.StartsWith("stores/", StringComparison.OrdinalIgnoreCase))
        {
            candidates.Add($"stores/{normalized}");
        }

        foreach (var rel in candidates.Distinct(StringComparer.OrdinalIgnoreCase))
        {
            var full = Path.GetFullPath(
                Path.Combine(wwwroot, rel.Replace('/', Path.DirectorySeparatorChar)));
            if (full.StartsWith(wwwroot, StringComparison.OrdinalIgnoreCase)
                && File.Exists(full))
                return full;
        }

        return null;
    }

    public static string EmbedImgTag(string contentRootPath, string? imageUrl)
    {
        var fullPath = ResolvePath(contentRootPath, imageUrl);
        if (fullPath == null) return "";

        try
        {
            var bytes = File.ReadAllBytes(fullPath);
            if (bytes.Length == 0) return "";
            var ext = Path.GetExtension(fullPath).ToLowerInvariant();
            var mime = ext switch
            {
                ".jpg" or ".jpeg" or ".jfif" => "image/jpeg",
                ".png" => "image/png",
                ".webp" => "image/webp",
                ".gif" => "image/gif",
                _ => "image/jpeg",
            };
            var b64 = Convert.ToBase64String(bytes);
            return $"""<img src="data:{mime};base64,{b64}" alt="" style="width:3cm;height:3cm;object-fit:contain;display:block;margin:auto"/>""";
        }
        catch
        {
            return "";
        }
    }
}
