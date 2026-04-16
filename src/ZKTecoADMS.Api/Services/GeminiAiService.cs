using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

using System.Runtime.CompilerServices;

namespace ZKTecoADMS.Api.Services;

public interface IGeminiAiService
{
    Task<AiGeneratedContent> GenerateCommunicationContentAsync(
        string prompt, string typeLabel, string tone, string? context, int maxLength);
    IAsyncEnumerable<string> StreamGenerateCommunicationContentAsync(
        string prompt, string typeLabel, string tone, string? context, int maxLength,
        CancellationToken cancellationToken = default);
    bool IsConfigured { get; }
    bool IsEnabled { get; }
    void UpdateConfig(string? apiKey, string? model = null, int? maxTokens = null, double? temperature = null, bool? enabled = null);
    GeminiConfig GetCurrentConfig();
}

public class GeminiConfig
{
    public string ApiKey { get; set; } = string.Empty;
    public string Model { get; set; } = "gemini-2.5-flash";
    public int MaxOutputTokens { get; set; } = 2048;
    public double Temperature { get; set; } = 0.7;
    public bool Enabled { get; set; } = true;
    public bool IsConfigured => !string.IsNullOrWhiteSpace(ApiKey);
}

public class AiGeneratedContent
{
    public string Title { get; set; } = string.Empty;
    public string Content { get; set; } = string.Empty;
    public string Summary { get; set; } = string.Empty;
    public List<string> Tags { get; set; } = new();
}

public class GeminiAiService : IGeminiAiService
{
    private readonly HttpClient _httpClient;
    private string _apiKey;
    private string _model;
    private int _maxOutputTokens;
    private double _temperature;
    private bool _enabled;
    private readonly ILogger<GeminiAiService> _logger;

    public bool IsConfigured => !string.IsNullOrWhiteSpace(_apiKey);
    public bool IsEnabled => _enabled && IsConfigured;

    public GeminiAiService(IConfiguration configuration, ILogger<GeminiAiService> logger)
    {
        _logger = logger;
        _httpClient = new HttpClient { Timeout = TimeSpan.FromSeconds(60) };
        
        var section = configuration.GetSection("GeminiAi");
        _apiKey = section["ApiKey"] ?? "";
        _model = section["Model"] ?? "gemini-2.5-flash";
        _maxOutputTokens = int.TryParse(section["MaxOutputTokens"], out var t) ? t : 2048;
        _temperature = double.TryParse(section["Temperature"], out var temp) ? temp : 0.7;
        _enabled = !bool.TryParse(section["Enabled"], out var e) || e; // default true for backwards compat
    }

    public void UpdateConfig(string? apiKey, string? model = null, int? maxTokens = null, double? temperature = null, bool? enabled = null)
    {
        if (apiKey != null) _apiKey = apiKey;
        if (model != null) _model = model;
        if (maxTokens.HasValue) _maxOutputTokens = maxTokens.Value;
        if (temperature.HasValue) _temperature = temperature.Value;
        if (enabled.HasValue) _enabled = enabled.Value;
        _logger.LogInformation("Gemini AI config updated. IsEnabled: {IsEnabled}, Model: {Model}", IsEnabled, _model);
    }

    public GeminiConfig GetCurrentConfig() => new()
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
        if (!IsConfigured)
            throw new InvalidOperationException("Gemini API key chưa được cấu hình. Vui lòng thêm API key vào appsettings.json > GeminiAi > ApiKey");

        var systemPrompt = $@"Bạn là chuyên gia truyền thông nội bộ doanh nghiệp Việt Nam. 
Hãy viết một bài {typeLabel} bằng tiếng Việt với giọng văn {tone}.

YÊU CẦU:
- Viết nội dung HTML chuyên nghiệp, có cấu trúc rõ ràng với <h2>, <h3>, <p>, <ul>, <li>, <strong>
- Độ dài tối đa khoảng {maxLength} ký tự
- Nội dung phải chuyên nghiệp, phù hợp môi trường doanh nghiệp
- Kết thúc bằng lời chào trân trọng từ Ban Truyền thông

{(context != null ? $"BỐI CẢNH THÊM: {context}" : "")}

QUAN TRỌNG: Trả lời ĐÚNG theo format JSON sau (không markdown, không code block):
{{
  ""title"": ""Tiêu đề bài viết"",
  ""content"": ""<h2>...</h2><p>...</p> (nội dung HTML)"",
  ""summary"": ""Tóm tắt ngắn gọn 1-2 câu"",
  ""tags"": [""tag1"", ""tag2"", ""tag3""]
}}";

        var requestBody = new
        {
            contents = new[]
            {
                new
                {
                    parts = new[]
                    {
                        new { text = systemPrompt },
                        new { text = $"Viết bài về: {prompt}" }
                    }
                }
            },
            generationConfig = new
            {
                temperature = _temperature,
                maxOutputTokens = Math.Max(_maxOutputTokens, 8192),
                responseMimeType = "application/json"
            }
        };

        var url = $"https://generativelanguage.googleapis.com/v1beta/models/{_model}:generateContent?key={_apiKey}";

        var jsonContent = JsonSerializer.Serialize(requestBody, new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        });

        _logger.LogInformation("Calling Gemini API for prompt: {Prompt}", prompt);

        var request = new HttpRequestMessage(HttpMethod.Post, url)
        {
            Content = new StringContent(jsonContent, Encoding.UTF8, "application/json")
        };

        var response = await _httpClient.SendAsync(request);
        var responseBody = await response.Content.ReadAsStringAsync();

        if (!response.IsSuccessStatusCode)
        {
            _logger.LogError("Gemini API error {StatusCode}: {Body}", response.StatusCode, responseBody);
            
            // Parse error response for user-friendly message
            var errorMessage = ParseGeminiError(response.StatusCode, responseBody);
            throw new AiApiException(errorMessage, (int)response.StatusCode);
        }

        // Parse Gemini response
        using var doc = JsonDocument.Parse(responseBody);
        var root = doc.RootElement;

        // For thinking models (gemini-2.5-*), get the last non-thought part
        var parts = root
            .GetProperty("candidates")[0]
            .GetProperty("content")
            .GetProperty("parts");

        var text = "{}";
        for (int i = parts.GetArrayLength() - 1; i >= 0; i--)
        {
            var part = parts[i];
            // Skip "thought" parts (used by thinking models like gemini-2.5-flash)
            if (part.TryGetProperty("thought", out var thought) && thought.GetBoolean())
                continue;
            text = part.GetProperty("text").GetString() ?? "{}";
            break;
        }

        _logger.LogInformation("Gemini raw response text: {Text}", text.Length > 200 ? text[..200] + "..." : text);

        // Clean up response (remove markdown code blocks if present)
        text = text.Trim();
        if (text.StartsWith("```json")) text = text[7..];
        if (text.StartsWith("```")) text = text[3..];
        if (text.EndsWith("```")) text = text[..^3];
        text = text.Trim();

        try
        {
            var result = JsonSerializer.Deserialize<AiGeneratedContent>(text, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });

            return result ?? new AiGeneratedContent
            {
                Title = "Không thể parse kết quả AI",
                Content = text,
                Summary = prompt,
                Tags = new List<string> { "ai-generated" }
            };
        }
        catch (JsonException ex)
        {
            _logger.LogWarning(ex, "Failed to parse Gemini JSON, returning raw text");
            return new AiGeneratedContent
            {
                Title = $"📰 {prompt}",
                Content = text,
                Summary = prompt,
                Tags = new List<string> { "ai-generated" }
            };
        }
    }

    private string BuildSystemPrompt(string typeLabel, string tone, string? context, int maxLength)
    {
        return $@"Bạn là chuyên gia truyền thông nội bộ doanh nghiệp Việt Nam. 
Hãy viết một bài {typeLabel} bằng tiếng Việt với giọng văn {tone}.

YÊU CẦU:
- Viết nội dung text thuần (plain text), có cấu trúc rõ ràng
- Sử dụng dấu gạch đầu dòng (-) cho danh sách
- Sử dụng dấu === hoặc --- để phân cách phần
- Độ dài tối đa khoảng {maxLength} ký tự
- Nội dung phải chuyên nghiệp, phù hợp môi trường doanh nghiệp
- Kết thúc bằng lời chào trân trọng từ Ban Truyền thông

{(context != null ? $"BỐI CẢNH THÊM: {context}" : "")}

Hãy viết trực tiếp nội dung, KHÔNG bọc trong JSON hay markdown code block.";
    }

    public async IAsyncEnumerable<string> StreamGenerateCommunicationContentAsync(
        string prompt, string typeLabel, string tone, string? context, int maxLength,
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        if (!IsConfigured)
            throw new InvalidOperationException("Gemini API key chưa được cấu hình");

        var systemPrompt = BuildSystemPrompt(typeLabel, tone, context, maxLength);

        var requestBody = new
        {
            contents = new[]
            {
                new
                {
                    parts = new[]
                    {
                        new { text = systemPrompt },
                        new { text = $"Viết bài về: {prompt}" }
                    }
                }
            },
            generationConfig = new
            {
                temperature = _temperature,
                maxOutputTokens = Math.Max(_maxOutputTokens, 8192)
            }
        };

        var url = $"https://generativelanguage.googleapis.com/v1beta/models/{_model}:streamGenerateContent?alt=sse&key={_apiKey}";

        var jsonContent = JsonSerializer.Serialize(requestBody, new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        });

        _logger.LogInformation("Calling Gemini streaming API for prompt: {Prompt}", prompt);

        var request = new HttpRequestMessage(HttpMethod.Post, url)
        {
            Content = new StringContent(jsonContent, Encoding.UTF8, "application/json")
        };

        HttpResponseMessage response;
        try
        {
            response = await _httpClient.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        }
        catch (OperationCanceledException)
        {
            yield break;
        }

        if (!response.IsSuccessStatusCode)
        {
            var errorBody = await response.Content.ReadAsStringAsync(cancellationToken);
            _logger.LogError("Gemini streaming API error {StatusCode}: {Body}", response.StatusCode, errorBody);
            var errorMessage = ParseGeminiError(response.StatusCode, errorBody);
            throw new AiApiException(errorMessage, (int)response.StatusCode);
        }

        using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var reader = new System.IO.StreamReader(stream);

        while (!reader.EndOfStream && !cancellationToken.IsCancellationRequested)
        {
            var line = await reader.ReadLineAsync(cancellationToken);
            if (line == null) break;
            if (!line.StartsWith("data: ")) continue;

            var json = line["data: ".Length..];
            if (string.IsNullOrWhiteSpace(json)) continue;

            string? textChunk = null;
            try
            {
                using var doc = JsonDocument.Parse(json);
                var candidates = doc.RootElement.GetProperty("candidates");
                if (candidates.GetArrayLength() == 0) continue;

                var parts = candidates[0]
                    .GetProperty("content")
                    .GetProperty("parts");

                for (int i = 0; i < parts.GetArrayLength(); i++)
                {
                    var part = parts[i];
                    // Skip thinking/thought parts
                    if (part.TryGetProperty("thought", out var thought) && thought.GetBoolean())
                        continue;
                    if (part.TryGetProperty("text", out var textEl))
                    {
                        textChunk = textEl.GetString();
                    }
                }
            }
            catch (JsonException ex)
            {
                _logger.LogWarning(ex, "Failed to parse streaming chunk");
                continue;
            }

            if (!string.IsNullOrEmpty(textChunk))
            {
                yield return textChunk;
            }
        }
    }

    private static string ParseGeminiError(System.Net.HttpStatusCode statusCode, string responseBody)
    {
        try
        {
            using var doc = JsonDocument.Parse(responseBody);
            var root = doc.RootElement;
            
            if (root.TryGetProperty("error", out var error))
            {
                var code = error.TryGetProperty("code", out var c) ? c.GetInt32() : (int)statusCode;
                var status = error.TryGetProperty("status", out var s) ? s.GetString() : "";
                
                return code switch
                {
                    429 or _ when status == "RESOURCE_EXHAUSTED" => 
                        "Đã vượt quá giới hạn sử dụng miễn phí của Gemini API. " +
                        "API Key hợp lệ nhưng quota đã hết. " +
                        "Vui lòng đợi vài phút rồi thử lại, hoặc nâng cấp gói tại console.cloud.google.com",
                    400 => "Yêu cầu không hợp lệ. Vui lòng kiểm tra lại cấu hình model.",
                    401 or 403 => "API Key không hợp lệ hoặc không có quyền truy cập. Vui lòng kiểm tra lại API Key.",
                    404 => $"Model không tồn tại. Vui lòng chọn model khác.",
                    500 or 503 => "Máy chủ Google đang gặp sự cố. Vui lòng thử lại sau.",
                    _ => $"Lỗi Gemini API (mã {code}): {(error.TryGetProperty("message", out var m) ? m.GetString() : "Không rõ")}"
                };
            }
        }
        catch { /* ignore parse errors */ }
        
        return $"Lỗi Gemini API ({statusCode})";
    }
}

public class AiApiException : Exception
{
    public int StatusCode { get; }
    public bool IsQuotaError => StatusCode == 429;
    public bool IsAuthError => StatusCode == 401 || StatusCode == 403;
    
    public AiApiException(string message, int statusCode) : base(message)
    {
        StatusCode = statusCode;
    }
}
