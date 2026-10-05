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
    private readonly IHttpContextAccessor _http;
    private readonly ILogger<GeminiAiService> _logger;
    private bool _initialized;
    /// <summary>Khóa + cấu hình theo thứ ưu tiên: khóa của cửa hàng rồi khóa dùng chung (Super Admin).</summary>
    private readonly List<(string Key, GeminiConfig Config)> _chain = [];
    private bool _manualOverride;

    public TenantScopedGeminiAiService(
        IConfiguration configuration,
        ILogger<GeminiAiService> logger,
        ZKTecoDbContext db,
        ITenantProvider tenant,
        IHttpContextAccessor http)
    {
        _inner = new GeminiAiService(configuration, logger);
        _db = db;
        _tenant = tenant;
        _http = http;
        _logger = logger;
    }

    private void EnsureInitialized()
    {
        if (_initialized) return;
        _initialized = true;
        // Khóa riêng của cửa hàng trước. Khóa AI chung của SBOX chỉ khi gói có «Dùng AI chung SBOX»
        // (Super Admin / đại lý không thuộc cửa hàng luôn dùng khóa chung).
        var storeId = CurrentStoreId();
        var store = storeId is Guid sid
            ? GeminiStoreConfigLoader.LoadFromDbAsync(_db, sid).GetAwaiter().GetResult()
            : null;
        var platform = GeminiStoreConfigLoader.LoadPlatformAsync(_db).GetAwaiter().GetResult();
        if (storeId is Guid s2 && platform != null && !_alwaysShared && !SharedAllowed(s2))
        {
            platform = null;
            SharedBlocked = true;
        }
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

    /// <summary>
    /// Cửa hàng của người gọi. ITenantProvider có thể được tạo trong lúc xác thực JWT (OnTokenValidated dùng DbContext)
    /// khi request chưa có User → StoreId null; đọc thẳng claim để khóa AI riêng của cửa hàng vẫn được dùng.
    /// </summary>
    private Guid? CurrentStoreId()
    {
        if (_tenant.StoreId is Guid sid) return sid;
        var user = _http.HttpContext?.User;
        if (user?.Identity?.IsAuthenticated != true) return null;
        return Guid.TryParse(user.FindFirst(Application.Constants.ClaimTypeNames.StoreId)?.Value, out var id) ? id : null;
    }

    /// <summary>Gói (hoặc chức năng cấp riêng) của cửa hàng cho dùng khóa AI chung của SBOX.</summary>
    private bool SharedAllowed(Guid storeId) =>
        Infrastructure.Helpers.StorePackageHelper.ResolveAllowedModulesAsync(_db, storeId).GetAwaiter().GetResult()
            .Contains(Application.Authorization.FeatureModuleCatalog.SharedAiModule, StringComparer.OrdinalIgnoreCase);

    private bool _alwaysShared;

    /// <summary>
    /// Tính năng mọi cửa hàng được dùng khóa AI chung (mẫu hợp đồng / báo giá, AI thêm menu) — vẫn ưu tiên khóa riêng.
    /// </summary>
    public void AllowSharedKeyForThisFeature()
    {
        if (_alwaysShared) return;
        _alwaysShared = true;
        if (!_initialized) return;
        _initialized = false;
        _chain.Clear();
        SharedBlocked = false;
    }

    /// <summary>Có khóa AI chung nhưng gói của cửa hàng không cho dùng.</summary>
    public bool SharedBlocked { get; private set; }

    /// <summary>Cửa hàng đang chạy bằng khóa AI chung (không có khóa riêng dùng được).</summary>
    public bool UsingSharedKey
    {
        get
        {
            EnsureInitialized();
            var current = _inner.GetCurrentConfig().ApiKey;
            return !string.IsNullOrEmpty(current) && _chain.Any(c => c.Key == current && c.Config.IsPlatform);
        }
    }

    /// <summary>Câu báo khi chưa gọi được AI (chưa có khóa riêng và gói không cho dùng khóa chung, hoặc chưa cấu hình).</summary>
    public static string NotReadyMessage(IGeminiAiService service) =>
        service is TenantScopedGeminiAiService { SharedBlocked: true } t && !t.IsConfigured
            ? NoOwnKeyMessage
            : "Gemini AI chưa được bật hoặc chưa cấu hình API key";

    /// <summary>Lý do không gọi được AI — hiện cho người dùng.</summary>
    public const string NoOwnKeyMessage =
        "Cửa hàng chưa có khóa AI riêng. Vào Thiết lập SBOX › Trợ lý AI để nhập khóa Gemini của cửa hàng, "
        + "hoặc liên hệ SBOX nâng cấp gói có «Dùng AI chung SBOX».";

    private void UseKey((string Key, GeminiConfig Config) entry, string? model = null) =>
        _inner.UpdateConfig(entry.Key, model ?? entry.Config.Model, entry.Config.MaxOutputTokens,
            entry.Config.Temperature, entry.Config.Enabled);

    /// <summary>
    /// Model dự phòng khi Google báo model đã chọn không còn cho khóa này (404 — tài khoản mới không
    /// được dùng model cũ) hoặc đang quá tải (503). Thử trên cùng khóa trước khi chuyển khóa.
    /// </summary>
    internal static readonly string[] FallbackModels = [GeminiModels.Flash, GeminiModels.FlashLite];

    internal static bool IsModelUnavailable(AiApiException ex) => ex.StatusCode is 404 or 503;

    /// <summary>Gọi trên 1 khóa: model đã chọn, lỗi model / quá tải thì thử các model dự phòng.</summary>
    private async Task<T> CallOnKeyAsync<T>((string Key, GeminiConfig Config) entry, Func<Task<T>> call)
    {
        UseKey(entry);
        try
        {
            return await call();
        }
        catch (AiApiException ex) when (IsModelUnavailable(ex))
        {
            AiApiException last = ex;
            foreach (var model in FallbackModels.Where(m => !string.Equals(m, entry.Config.Model, StringComparison.OrdinalIgnoreCase)))
            {
                UseKey(entry, model);
                try
                {
                    var r = await call();
                    _logger.LogInformation("Gemini key {Mask}: model {Model} không dùng được ({Status}) — đã chạy bằng {Fallback}",
                        GeminiKeyPool.Mask(entry.Key), entry.Config.Model, ex.StatusCode, model);
                    return r;
                }
                catch (AiApiException e2) when (IsModelUnavailable(e2))
                {
                    last = e2;
                }
            }
            throw last;
        }
    }

    /// <summary>
    /// Gọi AI lần lượt qua các khóa: khóa hết lượt (429) nghỉ 15 phút, khóa sai / hết hạn nghỉ 6 giờ,
    /// rồi thử khóa kế tiếp. Lỗi khác (nội dung, mạng, model) trả ngay.
    /// </summary>
    /// <summary>Hết lượt: nghỉ khóa với model đang gọi. Khóa sai / hết hạn: nghỉ cho mọi model.</summary>
    private static void MarkCooling(string key, bool auth, Func<string, string> pk, TimeSpan duration)
    {
        GeminiKeyPool.MarkExhausted(pk(key), duration);
        if (auth) GeminiKeyPool.MarkExhausted(key, duration);
    }

    private async Task<T> WithFailoverAsync<T>(Func<Task<T>> call, string? poolTag = null)
    {
        string Pk(string key) => poolTag == null ? key : key + "#" + poolTag;
        EnsureInitialized();
        if (!_manualOverride && _chain.Count == 0 && SharedBlocked)
            throw new InvalidOperationException(NoOwnKeyMessage);
        if (_manualOverride || _chain.Count == 0)
            return await call();
        if (_chain.Count == 1)
        {
            try { return await CallOnKeyAsync(_chain[0], call); }
            catch (AiApiException ex) when (ex.IsQuotaError || ex.IsAuthError)
            {
                MarkCooling(_chain[0].Key, ex.IsAuthError, Pk,
                    ex.IsQuotaError ? TimeSpan.FromMinutes(15) : TimeSpan.FromHours(6));
                throw;
            }
        }
        AiApiException? last = null;
        foreach (var i in GeminiKeyPool.OrderForUse(_chain.Select(c => Pk(c.Key)).ToList()))
        {
            try
            {
                return await CallOnKeyAsync(_chain[i], call);
            }
            catch (AiApiException ex) when (ex.IsQuotaError || ex.IsAuthError || IsModelUnavailable(ex))
            {
                // Hết lượt / sai khóa: cho nghỉ. Model không dùng được (đã thử dự phòng) / quá tải: chuyển khóa, không phạt.
                if (ex.IsQuotaError || ex.IsAuthError)
                    MarkCooling(_chain[i].Key, ex.IsAuthError, Pk,
                        ex.IsQuotaError ? TimeSpan.FromMinutes(15) : TimeSpan.FromHours(6));
                _logger.LogWarning("Gemini key #{Index} ({Mask}) {Reason} — chuyển khóa kế tiếp",
                    i + 1, GeminiKeyPool.Mask(_chain[i].Key),
                    ex.IsQuotaError ? "hết lượt" : ex.IsAuthError ? "không hợp lệ" : $"model không dùng được ({ex.StatusCode})");
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

    public Task<System.Text.Json.JsonElement> GenerateContentRawAsync(object requestBody, CancellationToken cancellationToken = default, string? model = null)
    {
        // Model chỉ định (TTS, Flash Lite dự phòng): hạn mức Google tính riêng từng model → hết lượt chỉ cho nghỉ khóa với model đó.
        return WithFailoverAsync(() => _inner.GenerateContentRawAsync(requestBody, cancellationToken, model), model);
    }
}

public static class GeminiSharedKeyExtensions
{
    /// <summary>Cho tính năng này dùng khóa AI chung dù gói không có «Dùng AI chung SBOX» (vẫn ưu tiên khóa riêng).</summary>
    public static IGeminiAiService AllowSharedKey(this IGeminiAiService service)
    {
        (service as TenantScopedGeminiAiService)?.AllowSharedKeyForThisFeature();
        return service;
    }
}
