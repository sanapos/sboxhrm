using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Nạp API key Gemini / DeepSeek từ bảng AppSettings (DB) vào singleton service khi app khởi động.
/// Trước đây config chỉ đọc từ appsettings.json → sau khi restart container, key user lưu qua UI bị mất runtime.
/// </summary>
public class AiConfigLoaderHostedService(
    IServiceProvider sp,
    IGeminiAiService gemini,
    IDeepSeekAiService deepSeek,
    ILogger<AiConfigLoaderHostedService> logger) : IHostedService
{
    public async Task StartAsync(CancellationToken cancellationToken)
    {
        try
        {
            using var scope = sp.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();

            var keys = new[]
            {
                "gemini_api_key", "gemini_model", "gemini_max_tokens", "gemini_temperature", "gemini_enabled",
                "deepseek_api_key", "deepseek_model", "deepseek_max_tokens", "deepseek_temperature", "deepseek_enabled"
            };

            var settings = await db.AppSettings
                .AsNoTracking()
                .Where(s => keys.Contains(s.Key))
                .ToListAsync(cancellationToken);

            string? Get(string k) => settings
                .Where(s => s.Key == k)
                .OrderByDescending(s => s.LastModified ?? s.CreatedAt)
                .Select(s => s.Value)
                .FirstOrDefault();

            var gKey = Get("gemini_api_key");
            if (!string.IsNullOrWhiteSpace(gKey))
            {
                int? gMax = int.TryParse(Get("gemini_max_tokens"), out var gm) ? gm : null;
                double? gTemp = double.TryParse(Get("gemini_temperature"), out var gt) ? gt : null;
                bool? gEnabled = bool.TryParse(Get("gemini_enabled"), out var ge) ? ge : null;
                gemini.UpdateConfig(gKey, Get("gemini_model"), gMax, gTemp, gEnabled);
                logger.LogInformation("Loaded Gemini config from DB. IsEnabled={IsEnabled}", gemini.IsEnabled);
            }
            else
            {
                logger.LogInformation("No Gemini API key found in DB (AppSettings).");
            }

            var dKey = Get("deepseek_api_key");
            if (!string.IsNullOrWhiteSpace(dKey))
            {
                int? dMax = int.TryParse(Get("deepseek_max_tokens"), out var dm) ? dm : null;
                double? dTemp = double.TryParse(Get("deepseek_temperature"), out var dt) ? dt : null;
                bool? dEnabled = bool.TryParse(Get("deepseek_enabled"), out var de) ? de : null;
                deepSeek.UpdateConfig(dKey, Get("deepseek_model"), dMax, dTemp, dEnabled);
                logger.LogInformation("Loaded DeepSeek config from DB. IsEnabled={IsEnabled}", deepSeek.IsEnabled);
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Failed to load AI config from DB (non-fatal)");
        }
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
