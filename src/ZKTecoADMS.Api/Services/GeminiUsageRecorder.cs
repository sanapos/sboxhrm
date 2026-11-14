using System.Threading.Channels;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>Ghi lại số token mỗi lời gọi Gemini. Lớp giả trong kiểm thử chỉ cần giữ danh sách.</summary>
public interface IGeminiUsageRecorder
{
    void Record(Guid? storeId, string feature, string? apiKeyMask, bool sharedKey, GeminiUsage usage);
}

/// <summary>
/// Xếp hàng rồi ghi nền theo lô. Ghi nhật ký không được làm chậm lời gọi AI và hỏng nhật ký không được
/// làm hỏng tính năng — nên <see cref="Record"/> chỉ bỏ vào hàng đợi, đầy thì bỏ qua dòng mới.
/// </summary>
public sealed class GeminiUsageRecorder(IServiceProvider services, ILogger<GeminiUsageRecorder> logger)
    : BackgroundService, IGeminiUsageRecorder
{
    /// <summary>Tối đa bấy nhiêu dòng chờ ghi; quá thì bỏ dòng mới (thà mất số liệu còn hơn ngốn bộ nhớ).</summary>
    public const int QueueCapacity = 5000;

    /// <summary>Mỗi lần ghi tối đa bấy nhiêu dòng.</summary>
    public const int BatchSize = 200;

    readonly Channel<GeminiUsageLog> _queue = Channel.CreateBounded<GeminiUsageLog>(
        new BoundedChannelOptions(QueueCapacity) { FullMode = BoundedChannelFullMode.DropWrite });

    int _dropped;

    public void Record(Guid? storeId, string feature, string? apiKeyMask, bool sharedKey, GeminiUsage usage)
    {
        if (usage.Total <= 0) return;
        var row = new GeminiUsageLog
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            Feature = Cut(feature, 120) ?? "",
            Model = Cut(usage.Model, 60) ?? "",
            ApiKeyMask = Cut(apiKeyMask, 80),
            SharedKey = sharedKey,
            PromptTokens = usage.PromptTokens,
            AnswerTokens = usage.AnswerTokens,
            ThoughtTokens = usage.ThoughtTokens,
            TotalTokens = usage.Total,
            CreatedAt = DateTime.UtcNow,
        };
        if (!_queue.Writer.TryWrite(row) && Interlocked.Increment(ref _dropped) % 100 == 1)
            logger.LogWarning("Hàng đợi token Gemini đầy — đã bỏ {Count} dòng", _dropped);
    }

    static string? Cut(string? s, int max) =>
        string.IsNullOrEmpty(s) ? s : s.Length <= max ? s : s[..max];

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (await _queue.Reader.WaitToReadAsync(stoppingToken))
        {
            var batch = new List<GeminiUsageLog>();
            while (batch.Count < BatchSize && _queue.Reader.TryRead(out var row))
                batch.Add(row);
            if (batch.Count == 0) continue;
            try
            {
                using var scope = services.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();
                db.GeminiUsageLogs.AddRange(batch);
                await db.SaveChangesAsync(stoppingToken);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                // Mất vài dòng thống kê không đáng để làm hỏng tính năng AI.
                logger.LogWarning(ex, "Không ghi được {Count} dòng token Gemini", batch.Count);
            }
        }
    }
}
