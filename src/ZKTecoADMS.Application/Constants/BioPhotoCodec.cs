namespace ZKTecoADMS.Application.Constants;

/// <summary>JPEG helpers for VL face (BIOPHOTO / USERPIC).</summary>
public static class BioPhotoCodec
{
    public static bool LooksLikeJpeg(byte[]? data) =>
        data is { Length: >= 3 } && data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF;

    public static byte[]? TryGetJpeg(string? template, byte[]? photoData)
    {
        if (LooksLikeJpeg(photoData))
            return photoData;

        if (string.IsNullOrWhiteSpace(template))
            return null;

        var t = template.Trim();
        try
        {
            var bytes = Convert.FromBase64String(t);
            return LooksLikeJpeg(bytes) ? bytes : null;
        }
        catch (FormatException)
        {
            return null;
        }
    }

    public static bool HasFacePayload(string? template, byte[]? photoData, int minTemplateLen = 80)
    {
        if (photoData is { Length: >= 80 })
            return true;
        if (string.IsNullOrWhiteSpace(template))
            return false;
        var t = template.Trim();
        if (string.Equals(t, "enrolled-via-adms", StringComparison.OrdinalIgnoreCase))
            return false;
        return t.Length >= minTemplateLen;
    }
}
