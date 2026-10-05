namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Model Gemini cho phép chọn. Chỉ giữ bản «mới nhất» (Google tự lên đời, khóa mới đều dùng được);
/// model cũ / cố định phiên bản đã lưu trước đây tự chuyển sang Flash.
/// </summary>
public static class GeminiModels
{
    public const string Flash = "gemini-flash-latest";
    public const string FlashLite = "gemini-flash-lite-latest";

    public static readonly IReadOnlyList<string> Supported = [Flash, FlashLite];

    public static string Normalize(string? model) =>
        Supported.FirstOrDefault(m => string.Equals(m, model?.Trim(), StringComparison.OrdinalIgnoreCase)) ?? Flash;
}
