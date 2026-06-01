namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Gemini config is loaded per store on each API request (TenantScopedGeminiAiService).
/// Startup hook kept for future global providers; no longer overwrites singleton with one store's key.
/// </summary>
public class AiConfigLoaderHostedService(ILogger<AiConfigLoaderHostedService> logger) : IHostedService
{
    public Task StartAsync(CancellationToken cancellationToken)
    {
        logger.LogInformation(
            "AI: Gemini config is loaded per store (AppSettings.StoreId) on each authenticated request.");
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
