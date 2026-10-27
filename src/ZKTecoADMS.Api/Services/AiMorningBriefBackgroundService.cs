namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Chạy nền «Bản tin sáng»: 5 phút thức dậy một lần, tìm cửa hàng đã bật và đã tới giờ gửi hôm nay (giờ VN) mà chưa gửi,
/// gửi tối đa 3 cửa hàng song song (mỗi cửa hàng một scope / DbContext riêng). Chống gửi trùng bằng nhật ký
/// AiMorningBriefLogs (mỗi cửa hàng mỗi ngày một dòng, khóa duy nhất + chuyển trạng thái nguyên tử) nên khởi động lại
/// hay nhiều máy chủ cùng chạy cũng không gửi lần hai. Lỗi của một cửa hàng không ảnh hưởng cửa hàng khác / host.
/// </summary>
public sealed class AiMorningBriefBackgroundService(IServiceScopeFactory scopes, ILogger<AiMorningBriefBackgroundService> logger)
    : BackgroundService
{
    static readonly TimeSpan Interval = TimeSpan.FromMinutes(5);
    const int MaxParallelStores = 3;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        try
        {
            await Task.Delay(TimeSpan.FromSeconds(90), stoppingToken);
            while (!stoppingToken.IsCancellationRequested)
            {
                try
                {
                    await RunOnceAsync(DateTime.UtcNow, stoppingToken);
                }
                catch (Exception ex) when (ex is not OperationCanceledException)
                {
                    logger.LogError(ex, "AiMorningBrief run failed");
                }
                await Task.Delay(Interval, stoppingToken);
            }
        }
        catch (OperationCanceledException)
        {
            // dừng host
        }
    }

    internal async Task RunOnceAsync(DateTime utcNow, CancellationToken ct)
    {
        List<Guid> due;
        using (var scope = scopes.CreateScope())
        {
            due = await scope.ServiceProvider.GetRequiredService<AiMorningBriefService>().DueStoreIdsAsync(utcNow, ct);
        }
        if (due.Count == 0) return;

        await Parallel.ForEachAsync(due, new ParallelOptions { MaxDegreeOfParallelism = MaxParallelStores, CancellationToken = ct },
            async (storeId, token) =>
            {
                try
                {
                    using var scope = scopes.CreateScope();
                    var svc = scope.ServiceProvider.GetRequiredService<AiMorningBriefService>();
                    var r = await svc.SendStoreAsync(storeId, utcNow, token);
                    if (r.Skipped != null)
                        logger.LogInformation("Morning brief store {StoreId} skipped: {Reason}", storeId, r.Skipped);
                }
                catch (Exception ex) when (ex is not OperationCanceledException)
                {
                    logger.LogError(ex, "Morning brief store {StoreId} failed", storeId);
                }
            });
    }
}
