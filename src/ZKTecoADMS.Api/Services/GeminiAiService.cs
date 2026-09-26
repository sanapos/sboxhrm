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
    Task<string> GeneratePlainTextAsync(string systemPrompt, string userPrompt, int maxTokens = 1024);
    /// <summary>Multi-turn chat for AI assistant (lower temperature, system instruction).</summary>
    Task<string> GenerateAssistantChatAsync(
        string systemPrompt,
        IReadOnlyList<(string Role, string Content)> messages,
        int maxTokens = 2048,
        CancellationToken cancellationToken = default);
    /// <summary>
    /// Gửi prompt kèm ảnh / tài liệu (inline) và nhận JSON (responseMimeType=application/json).
    /// Trả chuỗi JSON đã bỏ code fence. Lỗi quota → <see cref="AiApiException"/> (IsQuotaError).
    /// </summary>
    Task<string> GenerateJsonAsync(
        string systemPrompt,
        string userPrompt,
        IReadOnlyList<AiFilePart>? files = null,
        int maxTokens = 16384,
        CancellationToken cancellationToken = default);
    bool IsConfigured { get; }
    bool IsEnabled { get; }
    void UpdateConfig(string? apiKey, string? model = null, int? maxTokens = null, double? temperature = null, bool? enabled = null);
    GeminiConfig GetCurrentConfig();
}

/// <summary>Ảnh / tài liệu gửi kèm Gemini (inlineData, tối đa ~20 MB mỗi request).</summary>
public sealed record AiFilePart(string MimeType, byte[] Data);

public class GeminiConfig
{
    public string ApiKey { get; set; } = string.Empty;
    /// <summary>Mọi khóa đã cấu hình (khóa đầu = <see cref="ApiKey"/>); hết lượt thì chuyển khóa kế.</summary>
    public List<string> ApiKeys { get; set; } = [];
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
        // Đọc ảnh menu / file Word nhiều trang có thể > 60 s.
        _httpClient = new HttpClient { Timeout = TimeSpan.FromSeconds(180) };
        
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

    public async Task<string> GenerateJsonAsync(
        string systemPrompt,
        string userPrompt,
        IReadOnlyList<AiFilePart>? files = null,
        int maxTokens = 16384,
        CancellationToken cancellationToken = default)
    {
        if (!IsConfigured)
            throw new InvalidOperationException("Chưa cấu hình AI (Gemini). Super Admin cấu hình tại Quản trị hệ thống → AI.");
        if (!IsEnabled)
            throw new InvalidOperationException("AI (Gemini) đang tắt. Super Admin bật lại tại Quản trị hệ thống → AI.");

        var parts = new List<object> { new Dictionary<string, object> { ["text"] = userPrompt } };
        foreach (var f in files ?? [])
        {
            parts.Add(new Dictionary<string, object>
            {
                ["inlineData"] = new Dictionary<string, object>
                {
                    ["mimeType"] = f.MimeType,
                    ["data"] = Convert.ToBase64String(f.Data),
                },
            });
        }

        var requestBody = new Dictionary<string, object>
        {
            ["systemInstruction"] = new { parts = new[] { new { text = systemPrompt } } },
            ["contents"] = new[] { new Dictionary<string, object> { ["role"] = "user", ["parts"] = parts } },
            ["generationConfig"] = new Dictionary<string, object>
            {
                ["temperature"] = 0.1,
                ["maxOutputTokens"] = Math.Max(maxTokens, 1024),
                ["responseMimeType"] = "application/json",
            },
        };

        var url = $"https://generativelanguage.googleapis.com/v1beta/models/{_model}:generateContent?key={_apiKey}";
        using var request = new HttpRequestMessage(HttpMethod.Post, url)
        {
            Content = new StringContent(JsonSerializer.Serialize(requestBody), Encoding.UTF8, "application/json"),
        };
        using var response = await _httpClient.SendAsync(request, cancellationToken);
        var responseBody = await response.Content.ReadAsStringAsync(cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            _logger.LogError("Gemini JSON API error {StatusCode}: {Body}", response.StatusCode,
                responseBody.Length > 500 ? responseBody[..500] : responseBody);
            throw new AiApiException(ParseGeminiError(response.StatusCode, responseBody), (int)response.StatusCode);
        }

        using var doc = JsonDocument.Parse(responseBody);
        if (!doc.RootElement.TryGetProperty("candidates", out var candidates) || candidates.GetArrayLength() == 0)
            throw new AiApiException("AI không trả kết quả (nội dung có thể bị chặn). Thử ảnh / file khác.", 422);
        var candidate = candidates[0];
        var finish = candidate.TryGetProperty("finishReason", out var fr) ? fr.GetString() : null;
        var text = "";
        if (candidate.TryGetProperty("content", out var content) && content.TryGetProperty("parts", out var outParts))
        {
            for (var i = outParts.GetArrayLength() - 1; i >= 0; i--)
            {
                var part = outParts[i];
                if (part.TryGetProperty("thought", out var thought) && thought.ValueKind == JsonValueKind.True)
                    continue;
                if (part.TryGetProperty("text", out var t)) { text = t.GetString() ?? ""; break; }
            }
        }
        if (string.IsNullOrWhiteSpace(text))
        {
            throw new AiApiException(finish == "MAX_TOKENS"
                ? "Nội dung quá dài cho một lần đọc — chia nhỏ ảnh / file rồi thử lại."
                : "AI không trả kết quả. Vui lòng thử lại sau.", 422);
        }

        text = text.Trim();
        if (text.StartsWith("```json")) text = text[7..];
        if (text.StartsWith("```")) text = text[3..];
        if (text.EndsWith("```")) text = text[..^3];
        return text.Trim();
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

    public async Task<string> GeneratePlainTextAsync(string systemPrompt, string userPrompt, int maxTokens = 1024)
    {
        if (!IsConfigured)
            throw new InvalidOperationException("Gemini API key chưa được cấu hình. Vui lòng cấu hình tại Cài đặt → Thiết lập AI (Gemini).");
        if (!IsEnabled)
            throw new InvalidOperationException("Gemini AI chưa được bật. Vui lòng bật trong Cài đặt → Thiết lập AI (Gemini).");

        var requestBody = new
        {
            contents = new[]
            {
                new
                {
                    parts = new[]
                    {
                        new { text = systemPrompt },
                        new { text = userPrompt }
                    }
                }
            },
            generationConfig = new
            {
                temperature = _temperature,
                maxOutputTokens = Math.Max(maxTokens, 256)
            }
        };

        var url = $"https://generativelanguage.googleapis.com/v1beta/models/{_model}:generateContent?key={_apiKey}";
        var jsonContent = JsonSerializer.Serialize(requestBody, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase });
        var request = new HttpRequestMessage(HttpMethod.Post, url)
        {
            Content = new StringContent(jsonContent, Encoding.UTF8, "application/json")
        };

        var response = await _httpClient.SendAsync(request);
        var responseBody = await response.Content.ReadAsStringAsync();
        if (!response.IsSuccessStatusCode)
        {
            _logger.LogError("Gemini API error {StatusCode}: {Body}", response.StatusCode, responseBody);
            throw new AiApiException(ParseGeminiError(response.StatusCode, responseBody), (int)response.StatusCode);
        }

        using var doc = JsonDocument.Parse(responseBody);
        var parts = doc.RootElement.GetProperty("candidates")[0].GetProperty("content").GetProperty("parts");
        var text = "";
        for (int i = parts.GetArrayLength() - 1; i >= 0; i--)
        {
            var part = parts[i];
            if (part.TryGetProperty("thought", out var thought) && thought.GetBoolean()) continue;
            text = part.GetProperty("text").GetString() ?? "";
            break;
        }
        return text.Trim();
    }

    public async Task<string> GenerateAssistantChatAsync(
        string systemPrompt,
        IReadOnlyList<(string Role, string Content)> messages,
        int maxTokens = 2048,
        CancellationToken cancellationToken = default)
    {
        if (!IsConfigured)
            throw new InvalidOperationException("Gemini API key chưa được cấu hình.");
        if (!IsEnabled)
            throw new InvalidOperationException("Gemini AI chưa được bật.");

        var contents = new List<object>();
        foreach (var (role, content) in messages)
        {
            if (string.IsNullOrWhiteSpace(content)) continue;
            var geminiRole = string.Equals(role, "assistant", StringComparison.OrdinalIgnoreCase)
                || string.Equals(role, "model", StringComparison.OrdinalIgnoreCase)
                ? "model"
                : "user";
            contents.Add(new
            {
                role = geminiRole,
                parts = new[] { new { text = content.Trim() } }
            });
        }

        if (contents.Count == 0)
            throw new InvalidOperationException("Không có nội dung hội thoại.");

        var assistantTemp = Math.Min(_temperature, 0.35);
        var requestBody = new
        {
            systemInstruction = new { parts = new[] { new { text = systemPrompt } } },
            contents,
            generationConfig = new
            {
                temperature = assistantTemp,
                maxOutputTokens = Math.Max(maxTokens, 512)
            }
        };

        var url = $"https://generativelanguage.googleapis.com/v1beta/models/{_model}:generateContent?key={_apiKey}";
        var jsonContent = JsonSerializer.Serialize(requestBody, new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        });

        var request = new HttpRequestMessage(HttpMethod.Post, url)
        {
            Content = new StringContent(jsonContent, Encoding.UTF8, "application/json")
        };

        var response = await _httpClient.SendAsync(request, cancellationToken);
        var responseBody = await response.Content.ReadAsStringAsync(cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            _logger.LogError("Gemini assistant chat error {StatusCode}: {Body}", response.StatusCode, responseBody);
            throw new AiApiException(ParseGeminiError(response.StatusCode, responseBody), (int)response.StatusCode);
        }

        using var doc = JsonDocument.Parse(responseBody);
        var parts = doc.RootElement.GetProperty("candidates")[0].GetProperty("content").GetProperty("parts");
        for (int i = parts.GetArrayLength() - 1; i >= 0; i--)
        {
            var part = parts[i];
            if (part.TryGetProperty("thought", out var thought) && thought.GetBoolean()) continue;
            return (part.GetProperty("text").GetString() ?? "").Trim();
        }

        return string.Empty;
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

    public const string QuotaMessage = "AI đang quá tải hoặc đã hết lượt sử dụng. Vui lòng thử lại sau ít phút.";
    public const string InvalidKeyMessage = "API Key không hợp lệ hoặc không có quyền truy cập. Vui lòng kiểm tra lại API Key.";

    private static string ParseGeminiError(System.Net.HttpStatusCode statusCode, string responseBody)
    {
        try
        {
            using var doc = JsonDocument.Parse(responseBody);
            var root = doc.RootElement;
            
            if (root.TryGetProperty("error", out var error))
            {
                // Khóa sai Google trả 400 INVALID_ARGUMENT / API_KEY_INVALID — không phải lỗi model.
                if (responseBody.Contains("API_KEY_INVALID", StringComparison.Ordinal)
                    || responseBody.Contains("API key not valid", StringComparison.OrdinalIgnoreCase)
                    || responseBody.Contains("API key expired", StringComparison.OrdinalIgnoreCase))
                    return InvalidKeyMessage;
                var code = error.TryGetProperty("code", out var c) ? c.GetInt32() : (int)statusCode;
                var status = error.TryGetProperty("status", out var s) ? s.GetString() : "";
                
                return code switch
                {
                    429 => QuotaMessage,
                    _ when status == "RESOURCE_EXHAUSTED" => QuotaMessage,
                    400 => "Yêu cầu không hợp lệ. Vui lòng kiểm tra lại cấu hình model.",
                    401 or 403 => InvalidKeyMessage,
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
    public bool IsQuotaError => StatusCode == 429 || Message == GeminiAiService.QuotaMessage;
    public bool IsAuthError => StatusCode == 401 || StatusCode == 403 || Message == GeminiAiService.InvalidKeyMessage;
    
    public AiApiException(string message, int statusCode) : base(message)
    {
        StatusCode = statusCode;
    }
}
