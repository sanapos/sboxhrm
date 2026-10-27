using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.DTOs.Permissions;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>Trợ lý trả lời dần (stream) và biểu đồ trong câu trả lời.</summary>
public class AiAssistantStreamTests
{
    /// <summary>Gemini giả trả theo từng vòng: mỗi vòng là danh sách đoạn (content JSON).</summary>
    sealed class StreamGemini(params string[][] rounds) : IGeminiAiService
    {
        int _round;
        public int Calls => _round;

        public async IAsyncEnumerable<JsonElement> StreamGenerateContentRawAsync(object requestBody,
            [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken cancellationToken = default, string? model = null)
        {
            var chunks = rounds[Math.Min(_round++, rounds.Length - 1)];
            foreach (var c in chunks)
            {
                await Task.Yield();
                using var doc = JsonDocument.Parse(c);
                yield return doc.RootElement.Clone();
            }
        }

        public Task<JsonElement> GenerateContentRawAsync(object requestBody, CancellationToken cancellationToken = default, string? model = null)
        {
            // Không stream: ghép các đoạn của vòng thành một nội dung.
            var chunks = rounds[Math.Min(_round++, rounds.Length - 1)];
            var parts = chunks.SelectMany(c => JsonDocument.Parse(c).RootElement.GetProperty("parts").EnumerateArray()
                .Select(p => p.GetRawText()));
            using var doc = JsonDocument.Parse("{\"role\":\"model\",\"parts\":[" + string.Join(",", parts) + "]}");
            return Task.FromResult(doc.RootElement.Clone());
        }

        public bool IsConfigured => true;
        public bool IsEnabled => true;
        public Task<string> GenerateJsonAsync(string systemPrompt, string userPrompt, IReadOnlyList<AiFilePart>? files = null, int maxTokens = 16384, CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public Task<AiGeneratedContent> GenerateCommunicationContentAsync(string prompt, string typeLabel, string tone, string? context, int maxLength) => throw new NotSupportedException();
        public IAsyncEnumerable<string> StreamGenerateCommunicationContentAsync(string prompt, string typeLabel, string tone, string? context, int maxLength, CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public Task<string> GeneratePlainTextAsync(string systemPrompt, string userPrompt, int maxTokens = 1024) => throw new NotSupportedException();
        public Task<string> GenerateAssistantChatAsync(string systemPrompt, IReadOnlyList<(string Role, string Content)> messages, int maxTokens = 2048, CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public void UpdateConfig(string? apiKey, string? model = null, int? maxTokens = null, double? temperature = null, bool? enabled = null) { }
        public GeminiConfig GetCurrentConfig() => new();
    }

    static string Text(string t) => JsonSerializer.Serialize(new { role = "model", parts = new[] { new { text = t } } });

    static AiAssistantAgent Agent(IGeminiAiService gemini)
    {
        var db = new ZKTecoDbContext(new DbContextOptionsBuilder<ZKTecoDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking).Options);
        var actions = new AiAssistantActions(db, null!, null!, NullLogger<AiAssistantActions>.Instance);
        return new AiAssistantAgent(db, gemini, new HttpContextAccessor(), actions, NullLogger<AiAssistantAgent>.Instance);
    }

    static readonly Dictionary<string, ModulePermissionDto> NoPerms = [];

    [Fact]
    public async Task Tra_loi_dan_tung_doan_va_ket_qua_cuoi_giong_ban_thuong()
    {
        var gemini = new StreamGemini([Text("Doanh thu "), Text("hôm nay **1.200.000đ**.")]);
        var events = new List<AiAssistantAgent.AgentEvent>();
        var result = await Agent(gemini).RunAsync("Hệ thống", [("user", "doanh thu hôm nay?")], Guid.NewGuid(), NoPerms, true,
            CancellationToken.None, options: new AiAssistantAgent.Options(AiAssistantScope.Whole(), "q", false, null,
                e => { events.Add(e); return Task.CompletedTask; }));
        Assert.Equal(["Doanh thu ", "hôm nay **1.200.000đ**."], events.Where(e => e.Type == "delta").Select(e => e.Text));
        // Kết quả cuối đã ghép đoạn + bỏ Markdown như bản không stream.
        Assert.Equal("Doanh thu hôm nay 1.200.000đ.", result.Reply);
    }

    [Fact]
    public async Task Goi_cong_cu_bao_trang_thai_va_bo_chu_tam()
    {
        var call = JsonSerializer.Serialize(new
        {
            role = "model",
            parts = new object[] { new { text = "Để tôi xem…" }, new { functionCall = new { name = "store_overview", args = new { } } } },
        });
        var gemini = new StreamGemini([call], [Text("Cửa hàng có 0 mặt hàng.")]);
        var events = new List<AiAssistantAgent.AgentEvent>();
        var result = await Agent(gemini).RunAsync("Hệ thống", [("user", "cửa hàng có gì?")], Guid.NewGuid(), NoPerms, true,
            CancellationToken.None, options: new AiAssistantAgent.Options(AiAssistantScope.Whole(), "q", false, null,
                e => { events.Add(e); return Task.CompletedTask; }));
        var types = events.Select(e => e.Type).ToList();
        // Chữ tạm của vòng gọi công cụ bị bỏ (reset), rồi báo đang làm gì, rồi mới tới câu trả lời thật.
        Assert.Equal(["delta", "reset", "status", "delta"], types);
        Assert.Equal("Đang xem thông tin cửa hàng…", events[2].Text);
        Assert.Equal("Cửa hàng có 0 mặt hàng.", result.Reply);
        Assert.Equal(2, gemini.Calls);
    }

    [Fact]
    public async Task Khong_nghe_su_kien_thi_goi_thuong()
    {
        var gemini = new StreamGemini([Text("Xin chào "), Text("bạn.")]);
        var result = await Agent(gemini).RunAsync("Hệ thống", [("user", "chào")], Guid.NewGuid(), NoPerms, true, CancellationToken.None);
        // Bản thường ghép các part bằng xuống dòng (như trước), không gọi stream.
        Assert.Equal(["Xin chào", "bạn."], result.Reply.Split('\n').Select(s => s.Trim()));
    }

    [Fact]
    public void Doc_the_bieu_do()
    {
        var c = AiAssistantReplyParser.ParseChart("line|Doanh thu 7 ngày|T2=1200000;T3=950000;T4=1.300.000|", NoPerms, true)!;
        Assert.Equal("line", c.Type);
        Assert.Equal(["T2", "T3", "T4"], c.Labels);
        Assert.Equal([1200000m, 950000m, 1300000m], c.Values);
        Assert.Null(c.OpenModule);
        // Dưới 2 điểm / sai cú pháp → bỏ, không làm hỏng câu trả lời.
        Assert.Null(AiAssistantReplyParser.ParseChart("bar|X|A=1", NoPerms, true));
        Assert.Null(AiAssistantReplyParser.ParseChart("rác", NoPerms, true));
        var parsed = AiAssistantReplyParser.Parse("Tổng 3 ngày.\n[[CHART:bar|Món bán chạy|Cà phê=120;Trà=80;Bánh=45]]", NoPerms, true, [], "");
        Assert.Equal("Tổng 3 ngày.", parsed.Text);
        Assert.Single(parsed.Charts!);
        Assert.Equal("bar", parsed.Charts![0].Type);
    }
}
