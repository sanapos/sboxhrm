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
    private readonly ILogger<GeminiAiService> _logger;
    private bool _initialized;
    /// <summary>Khóa + cấu hình theo thứ ưu tiên: khóa của cửa hàng rồi khóa dùng chung (Super Admin).</summary>
    private readonly List<(string Key, GeminiConfig Config)> _chain = [];
    private bool _manualOverride;

    public TenantScopedGeminiAiService(
        IConfiguration configuration,
        ILogger<GeminiAiService> logger,
        ZKTecoDbContext db,
        ITenantProvider tenant)
    {
        _inner = new GeminiAiService(configuration, logger);
        _db = db;
        _tenant = tenant;
        _logger = logger;
    }

    private void EnsureInitialized()
    {
        if (_initialized) return;
        _initialized = true;
        // Khóa riêng của cửa hàng trước, sau đó khóa AI chung của Super Admin (dự phòng khi hết lượt).
        var store = _tenant.StoreId is Guid sid
            ? GeminiStoreConfigLoader.LoadFromDbAsync(_db, sid).GetAwaiter().GetResult()
            : null;
        var platform = GeminiStoreConfigLoader.LoadPlatformAsync(_db).GetAwaiter().GetResult();
        foreach (var cfg in new[] { store, platform })
        {
            if (cfg == null || !cfg.Enabled) continue;
            foreach (var k in cfg.ApiKeys.Count > 0 ? cfg.ApiKeys : [cfg.ApiKey])
                if (!string.IsNullOrWhiteSpace(k) && !_chain.Any(c => c.Key == k))
                    _chain.Add((k, cfg));
        }
        var first = _chain.Count > 0 ? _chain[GeminiKeyPool.OrderForUse(_chain.Select(c => c.Key).ToList())[0]] : default;
        if (first.Config != null)
            UseKey(first);
        else if ((store ?? platform) is GeminiConfig off)
            GeminiStoreConfigLoader.Apply(_inner, off); // đang tắt — giữ cấu hình để báo "đang tắt"
    }

    private void UseKey((string Key, GeminiConfig Config) entry) =>
        _inner.UpdateConfig(entry.Key, entry.Config.Model, entry.Config.MaxOutputTokens,
            entry.Config.Temperature, entry.Config.Enabled);

    /// <summary>
    /// Gọi AI lần lượt qua các khóa: khóa hết lượt (429) nghỉ 15 phút, khóa sai / hết hạn nghỉ 6 giờ,
    /// rồi thử khóa kế tiếp. Lỗi khác (nội dung, mạng, model) trả ngay.
    /// </summary>
    private async Task<T> WithFailoverAsync<T>(Func<Task<T>> call)
    {
        EnsureInitialized();
        if (_manualOverride || _chain.Count <= 1)
        {
            try { return await call(); }
            catch (AiApiException ex) when (_chain.Count == 1 && (ex.IsQuotaError || ex.IsAuthError))
            {
                GeminiKeyPool.MarkExhausted(_chain[0].Key,
                    ex.IsQuotaError ? TimeSpan.FromMinutes(15) : TimeSpan.FromHours(6));
                throw;
            }
        }
        AiApiException? last = null;
        foreach (var i in GeminiKeyPool.OrderForUse(_chain.Select(c => c.Key).ToList()))
        {
            UseKey(_chain[i]);
            try
            {
                return await call();
            }
            catch (AiApiException ex) when (ex.IsQuotaError || ex.IsAuthError)
            {
                GeminiKeyPool.MarkExhausted(_chain[i].Key,
                    ex.IsQuotaError ? TimeSpan.FromMinutes(15) : TimeSpan.FromHours(6));
                _logger.LogWarning("Gemini key #{Index} ({Mask}) {Reason} — chuyển khóa kế tiếp",
                    i + 1, GeminiKeyPool.Mask(_chain[i].Key), ex.IsQuotaError ? "hết lượt" : "không hợp lệ");
                last = ex;
            }
        }
        throw last!;
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
        // Gọi cấu hình tay (vd. nút «Kiểm tra») → chỉ dùng đúng cấu hình đó, không chuyển khóa.
        if (!string.IsNullOrWhiteSpace(apiKey)) _manualOverride = true;
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
        return WithFailoverAsync(() => _inner.GenerateCommunicationContentAsync(prompt, typeLabel, tone, context, maxLength));
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
        return WithFailoverAsync(() => _inner.GeneratePlainTextAsync(systemPrompt, userPrompt, maxTokens));
    }

    public Task<string> GenerateJsonAsync(
        string systemPrompt,
        string userPrompt,
        IReadOnlyList<AiFilePart>? files = null,
        int maxTokens = 16384,
        CancellationToken cancellationToken = default)
    {
        return WithFailoverAsync(() => _inner.GenerateJsonAsync(systemPrompt, userPrompt, files, maxTokens, cancellationToken));
    }

    public Task<string> GenerateAssistantChatAsync(
        string systemPrompt,
        IReadOnlyList<(string Role, string Content)> messages,
        int maxTokens = 2048,
        CancellationToken cancellationToken = default)
    {
        return WithFailoverAsync(() => _inner.GenerateAssistantChatAsync(systemPrompt, messages, maxTokens, cancellationToken));
    }
}
