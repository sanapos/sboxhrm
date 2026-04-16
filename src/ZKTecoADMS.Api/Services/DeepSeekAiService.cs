using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Runtime.CompilerServices;

namespace ZKTecoADMS.Api.Services;

public interface IDeepSeekAiService
{
    Task<AiGeneratedContent> GenerateCommunicationContentAsync(
        string prompt, string typeLabel, string tone, string? context, int maxLength);
    IAsyncEnumerable<string> StreamGenerateCommunicationContentAsync(
        string prompt, string typeLabel, string tone, string? context, int maxLength,
        CancellationToken cancellationToken = default);
    bool IsConfigured { get; }
    bool IsEnabled { get; }
    void UpdateConfig(string? apiKey, string? model = null, int? maxTokens = null, double? temperature = null, bool? enabled = null);
    DeepSeekConfig GetCurrentConfig();
}

public class DeepSeekConfig
{
    public string ApiKey { get; set; } = string.Empty;
    public string Model { get; set; } = "deepseek-chat";
    public int MaxOutputTokens { get; set; } = 2048;
    public double Temperature { get; set; } = 0.7;
    public bool Enabled { get; set; } = false;
    public bool IsConfigured => !string.IsNullOrWhiteSpace(ApiKey);
}

public class DeepSeekAiService : IDeepSeekAiService
{
    private readonly HttpClient _httpClient;
    private string _apiKey;
    private string _model;
    private int _maxOutputTokens;
    private double _temperature;
    private bool _enabled;
    private readonly ILogger<DeepSeekAiService> _logger;

    private const string BaseUrl = "https://api.deepseek.com/v1";

    public bool IsConfigured => !string.IsNullOrWhiteSpace(_apiKey);
    public bool IsEnabled => _enabled && IsConfigured;

    public DeepSeekAiService(IConfiguration configuration, ILogger<DeepSeekAiService> logger)
    {
        _logger = logger;
        _httpClient = new HttpClient { Timeout = TimeSpan.FromSeconds(60) };

        var section = configuration.GetSection("DeepSeekAi");
        _apiKey = section["ApiKey"] ?? "";
        _model = section["Model"] ?? "deepseek-chat";
        _maxOutputTokens = int.TryParse(section["MaxOutputTokens"], out var t) ? t : 2048;
        _temperature = double.TryParse(section["Temperature"], out var temp) ? temp : 0.7;
        _enabled = !bool.TryParse(section["Enabled"], out var e) || e;
    }

    public void UpdateConfig(string? apiKey, string? model = null, int? maxTokens = null, double? temperature = null, bool? enabled = null)
    {
        if (apiKey != null) _apiKey = apiKey;
        if (model != null) _model = model;
        if (maxTokens.HasValue) _maxOutputTokens = maxTokens.Value;
        if (temperature.HasValue) _temperature = temperature.Value;
        if (enabled.HasValue) _enabled = enabled.Value;
        _logger.LogInformation("DeepSeek AI config updated. IsEnabled: {IsEnabled}, Model: {Model}", IsEnabled, _model);
    }

    public DeepSeekConfig GetCurrentConfig() => new()
    {
        ApiKey = _apiKey,
        Model = _model,
        MaxOutputTokens = _maxOutputTokens,
        Temperature = _temperature,
        Enabled = _enabled
    };

    public async Task<AiGeneratedContent> GenerateCommunicationContentAsync(
        string prompt, string typeLabel, string tone, string? context, int maxLength)
    {
        if (!IsEnabled)
            throw new InvalidOperationException("DeepSeek AI chưa được bật hoặc chưa cấu hình API key");

        var systemPrompt = BuildSystemPrompt(typeLabel, tone, context, maxLength, json: true);

        var requestBody = new
        {
            model = _model,
            messages = new object[]
            {
                new { role = "system", content = systemPrompt },
                new { role = "user", content = $"Viết bài về: {prompt}" }
            },
            max_tokens = Math.Max(_maxOutputTokens, 8192),
            temperature = _temperature,
            response_format = new { type = "json_object" }
        };

        var url = $"{BaseUrl}/chat/completions";
        var jsonContent = JsonSerializer.Serialize(requestBody, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase });

        _logger.LogInformation("Calling DeepSeek API for prompt: {Prompt}", prompt);

        var request = new HttpRequestMessage(HttpMethod.Post, url)
        {
            Content = new StringContent(jsonContent, Encoding.UTF8, "application/json")
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _apiKey);

        var response = await _httpClient.SendAsync(request);
        var responseBody = await response.Content.ReadAsStringAsync();

        if (!response.IsSuccessStatusCode)
        {
            _logger.LogError("DeepSeek API error {StatusCode}: {Body}", response.StatusCode, responseBody);
            var errorMessage = ParseDeepSeekError(response.StatusCode, responseBody);
            throw new AiApiException(errorMessage, (int)response.StatusCode);
        }

        using var doc = JsonDocument.Parse(responseBody);
        var text = doc.RootElement
            .GetProperty("choices")[0]
            .GetProperty("message")
            .GetProperty("content")
            .GetString() ?? "{}";

        text = text.Trim();
        if (text.StartsWith("```json")) text = text[7..];
        if (text.StartsWith("```")) text = text[3..];
        if (text.EndsWith("```")) text = text[..^3];
        text = text.Trim();

        try
        {
            var result = JsonSerializer.Deserialize<AiGeneratedContent>(text, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            return result ?? new AiGeneratedContent { Title = "Không thể parse kết quả AI", Content = text, Summary = prompt, Tags = ["ai-generated"] };
        }
        catch (JsonException ex)
        {
            _logger.LogWarning(ex, "Failed to parse DeepSeek JSON, returning raw text");
            return new AiGeneratedContent { Title = $"📰 {prompt}", Content = text, Summary = prompt, Tags = ["ai-generated"] };
        }
    }

    private string BuildSystemPrompt(string typeLabel, string tone, string? context, int maxLength, bool json = false)
    {
        var format = json
            ? @"

QUAN TRỌNG: Trả lời ĐÚNG theo format JSON sau (không markdown, không code block):
{
  ""title"": ""Tiêu đề bài viết"",
  ""content"": ""<h2>...</h2><p>...</p> (nội dung HTML)"",
  ""summary"": ""Tóm tắt ngắn gọn 1-2 câu"",
  ""tags"": [""tag1"", ""tag2"", ""tag3""]
}"
            : "";

        return $@"Bạn là chuyên gia truyền thông nội bộ doanh nghiệp Việt Nam. 
Hãy viết một bài {typeLabel} bằng tiếng Việt với giọng văn {tone}.

YÊU CẦU:
- Viết nội dung HTML chuyên nghiệp, có cấu trúc rõ ràng với <h2>, <h3>, <p>, <ul>, <li>, <strong>
- Độ dài tối đa khoảng {maxLength} ký tự
- Nội dung phải chuyên nghiệp, phù hợp môi trường doanh nghiệp
- Kết thúc bằng lời chào trân trọng từ Ban Truyền thông

{(context != null ? $"BỐI CẢNH THÊM: {context}" : "")}{format}";
    }

    public async IAsyncEnumerable<string> StreamGenerateCommunicationContentAsync(
        string prompt, string typeLabel, string tone, string? context, int maxLength,
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        if (!IsEnabled)
            throw new InvalidOperationException("DeepSeek AI chưa được bật");

        var systemPrompt = BuildSystemPrompt(typeLabel, tone, context, maxLength);

        var requestBody = new
        {
            model = _model,
            messages = new object[]
            {
                new { role = "system", content = systemPrompt },
                new { role = "user", content = $"Viết bài về: {prompt}" }
            },
            max_tokens = Math.Max(_maxOutputTokens, 8192),
            temperature = _temperature,
            stream = true
        };

        var url = $"{BaseUrl}/chat/completions";
        var jsonContent = JsonSerializer.Serialize(requestBody, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase });

        var request = new HttpRequestMessage(HttpMethod.Post, url)
        {
            Content = new StringContent(jsonContent, Encoding.UTF8, "application/json")
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _apiKey);

        HttpResponseMessage response;
        try
        {
            response = await _httpClient.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        }
        catch (OperationCanceledException) { yield break; }

        if (!response.IsSuccessStatusCode)
        {
            var errorBody = await response.Content.ReadAsStringAsync(cancellationToken);
            throw new AiApiException(ParseDeepSeekError(response.StatusCode, errorBody), (int)response.StatusCode);
        }

        using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var reader = new System.IO.StreamReader(stream);

        while (!reader.EndOfStream && !cancellationToken.IsCancellationRequested)
        {
            var line = await reader.ReadLineAsync(cancellationToken);
            if (line == null) break;
            if (!line.StartsWith("data: ")) continue;

            var json = line["data: ".Length..];
            if (json == "[DONE]") break;
            if (string.IsNullOrWhiteSpace(json)) continue;

            string? textChunk = null;
            try
            {
                using var chunkDoc = JsonDocument.Parse(json);
                var delta = chunkDoc.RootElement
                    .GetProperty("choices")[0]
                    .GetProperty("delta");
                if (delta.TryGetProperty("content", out var contentEl))
                    textChunk = contentEl.GetString();
            }
            catch (JsonException ex)
            {
                _logger.LogWarning(ex, "Failed to parse DeepSeek streaming chunk");
                continue;
            }

            if (!string.IsNullOrEmpty(textChunk))
                yield return textChunk;
        }
    }

    private static string ParseDeepSeekError(System.Net.HttpStatusCode statusCode, string responseBody)
    {
        try
        {
            using var doc = JsonDocument.Parse(responseBody);
            if (doc.RootElement.TryGetProperty("error", out var error))
            {
                var message = error.TryGetProperty("message", out var m) ? m.GetString() : "Không rõ";
                var code = (int)statusCode;
                return code switch
                {
                    429 => "Đã vượt quá giới hạn sử dụng DeepSeek API. Vui lòng đợi rồi thử lại.",
                    400 => $"Yêu cầu không hợp lệ: {message}",
                    401 or 403 => "API Key không hợp lệ hoặc không có quyền truy cập.",
                    404 => "Model không tồn tại. Vui lòng chọn model khác.",
                    500 or 503 => "Máy chủ DeepSeek đang gặp sự cố. Vui lòng thử lại sau.",
                    _ => $"Lỗi DeepSeek API (mã {code}): {message}"
                };
            }
        }
        catch { }
        return $"Lỗi DeepSeek API ({statusCode})";
    }
}
