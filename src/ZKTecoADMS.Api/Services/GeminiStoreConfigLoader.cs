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

    public static async Task<GeminiConfig?> LoadFromDbAsync(
        ZKTecoDbContext db,
        Guid storeId,
        CancellationToken cancellationToken = default)
    {
        var rows = await db.AppSettings
            .AsNoTracking()
            .Where(s => s.StoreId == storeId && GeminiKeys.Contains(s.Key))
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
