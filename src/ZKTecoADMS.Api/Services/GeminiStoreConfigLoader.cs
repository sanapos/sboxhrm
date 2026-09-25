using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Load Gemini settings from AppSettings per store (StoreId).
/// </summary>
public static class GeminiStoreConfigLoader
{
    private static readonly string[] GeminiKeys =
    [
        AppSettingKeys.GeminiApiKey,
        "gemini_model",
        "gemini_max_tokens",
        "gemini_temperature",
        "gemini_enabled",
    ];

    public static Task<GeminiConfig?> LoadFromDbAsync(
        ZKTecoDbContext db,
        Guid storeId,
        CancellationToken cancellationToken = default)
        => LoadAsync(db, storeId, cancellationToken);

    /// <summary>Cấu hình AI dùng chung toàn hệ thống (Super Admin) — AppSettings StoreId = null.</summary>
    public static Task<GeminiConfig?> LoadPlatformAsync(
        ZKTecoDbContext db,
        CancellationToken cancellationToken = default)
        => LoadAsync(db, null, cancellationToken);

    /// <summary>Key riêng của cửa hàng nếu có, không thì cấu hình chung.</summary>
    public static async Task<GeminiConfig?> LoadEffectiveAsync(
        ZKTecoDbContext db,
        Guid? storeId,
        CancellationToken cancellationToken = default)
    {
        if (storeId is Guid sid)
        {
            var store = await LoadAsync(db, sid, cancellationToken);
            if (store != null) return store;
        }
        return await LoadAsync(db, null, cancellationToken);
    }

    private static async Task<GeminiConfig?> LoadAsync(
        ZKTecoDbContext db,
        Guid? storeId,
        CancellationToken cancellationToken)
    {
        // IgnoreQueryFilters: dòng StoreId = null bị bộ lọc cửa hàng ẩn với người dùng thường.
        var rows = await db.AppSettings
            .IgnoreQueryFilters()
            .AsNoTracking()
            .Where(s => s.StoreId == storeId && s.Deleted == null && GeminiKeys.Contains(s.Key))
            .ToListAsync(cancellationToken);

        if (rows.Count == 0)
            return null;

        var map = rows
            .GroupBy(s => s.Key)
            .ToDictionary(g => g.Key, g => g.OrderByDescending(s => s.LastModified ?? s.CreatedAt).First().Value);

        var apiKey = map.GetValueOrDefault(AppSettingKeys.GeminiApiKey);
        if (string.IsNullOrWhiteSpace(apiKey))
            return null;

        var enabled = true;
        if (map.TryGetValue("gemini_enabled", out var enabledRaw)
            && bool.TryParse(enabledRaw, out var e))
            enabled = e;

        return new GeminiConfig
        {
            ApiKey = apiKey.Trim(),
            Model = map.GetValueOrDefault("gemini_model") ?? "gemini-2.5-flash",
            MaxOutputTokens = int.TryParse(map.GetValueOrDefault("gemini_max_tokens"), out var t) ? t : 2048,
            Temperature = double.TryParse(
                map.GetValueOrDefault("gemini_temperature"),
                System.Globalization.NumberStyles.Any,
                System.Globalization.CultureInfo.InvariantCulture,
                out var temp)
                ? temp
                : 0.7,
            Enabled = enabled,
        };
    }

    public static void Apply(IGeminiAiService service, GeminiConfig config)
    {
        service.UpdateConfig(
            config.ApiKey,
            config.Model,
            config.MaxOutputTokens,
            config.Temperature,
            config.Enabled);
    }
}
