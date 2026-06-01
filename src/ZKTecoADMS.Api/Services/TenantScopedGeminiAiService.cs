using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Gemini AI scoped per HTTP request — config loaded from AppSettings for current store.
/// </summary>
public sealed class TenantScopedGeminiAiService : IGeminiAiService
{
    private readonly GeminiAiService _inner;
    private readonly ZKTecoDbContext _db;
    private readonly ITenantProvider _tenant;
    private bool _initialized;

    public TenantScopedGeminiAiService(
        IConfiguration configuration,
        ILogger<GeminiAiService> logger,
        ZKTecoDbContext db,
        ITenantProvider tenant)
    {
        _inner = new GeminiAiService(configuration, logger);
        _db = db;
        _tenant = tenant;
    }

    private void EnsureInitialized()
    {
        if (_initialized) return;
        _initialized = true;
        if (_tenant.StoreId is not Guid storeId) return;

        var cfg = GeminiStoreConfigLoader.LoadFromDbAsync(_db, storeId)
            .GetAwaiter()
            .GetResult();
        if (cfg != null)
            GeminiStoreConfigLoader.Apply(_inner, cfg);
    }

    public bool IsConfigured
    {
        get { EnsureInitialized(); return _inner.IsConfigured; }
    }

    public bool IsEnabled
    {
        get { EnsureInitialized(); return _inner.IsEnabled; }
    }

    public void UpdateConfig(
        string? apiKey,
        string? model = null,
        int? maxTokens = null,
        double? temperature = null,
        bool? enabled = null)
    {
        EnsureInitialized();
        _inner.UpdateConfig(apiKey, model, maxTokens, temperature, enabled);
    }

    public GeminiConfig GetCurrentConfig()
    {
        EnsureInitialized();
        return _inner.GetCurrentConfig();
    }

    public Task<AiGeneratedContent> GenerateCommunicationContentAsync(
        string prompt,
        string typeLabel,
        string tone,
        string? context,
        int maxLength)
    {
        EnsureInitialized();
        return _inner.GenerateCommunicationContentAsync(prompt, typeLabel, tone, context, maxLength);
    }

    public IAsyncEnumerable<string> StreamGenerateCommunicationContentAsync(
        string prompt,
        string typeLabel,
        string tone,
        string? context,
        int maxLength,
        CancellationToken cancellationToken = default)
    {
        EnsureInitialized();
        return _inner.StreamGenerateCommunicationContentAsync(
            prompt, typeLabel, tone, context, maxLength, cancellationToken);
    }

    public Task<string> GeneratePlainTextAsync(
        string systemPrompt,
        string userPrompt,
        int maxTokens = 1024)
    {
        EnsureInitialized();
        return _inner.GeneratePlainTextAsync(systemPrompt, userPrompt, maxTokens);
    }

    public Task<string> GenerateAssistantChatAsync(
        string systemPrompt,
        IReadOnlyList<(string Role, string Content)> messages,
        int maxTokens = 2048,
        CancellationToken cancellationToken = default)
    {
        EnsureInitialized();
        return _inner.GenerateAssistantChatAsync(systemPrompt, messages, maxTokens, cancellationToken);
    }
}
