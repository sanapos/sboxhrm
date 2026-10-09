using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Mỗi phút dọn lệnh in treo / quá hạn của các cửa hàng còn lệnh đang chạy. Trước đây chỉ dọn
/// khi có Agent gọi claim → cửa hàng tắt hết Agent thì lệnh treo + máy in «Bận» mãi.
/// </summary>
public class PosPrintJobSweepBackgroundService(IServiceProvider services, ILogger<PosPrintJobSweepBackgroundService> logger)
    : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await Task.Delay(TimeSpan.FromSeconds(75), stoppingToken);
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                using var scope = services.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();
                var dispatch = scope.ServiceProvider.GetRequiredService<IPosPrintDispatchService>();
                var storeIds = await db.PosPrintJobs.IgnoreQueryFilters().AsNoTracking()
                    .Where(j => j.Deleted == null && (j.Status == PosPrintJobStatus.Queued
                        || j.Status == PosPrintJobStatus.Claimed || j.Status == PosPrintJobStatus.Printing))
                    .Select(j => j.StoreId).Distinct().Take(500).ToListAsync(stoppingToken);
                foreach (var sid in storeIds)
                {
                    try { await dispatch.SweepStuckJobsAsync(sid, stoppingToken); }
                    catch (Exception ex) when (ex is not OperationCanceledException)
                    {
                        logger.LogWarning(ex, "Print sweep store {StoreId} failed", sid);
                    }
                }
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                logger.LogWarning(ex, "Print job sweep failed");
            }
            await Task.Delay(TimeSpan.FromMinutes(1), stoppingToken);
        }
    }
}

/// <summary>
/// Dọn bảng lệnh in cloud (mỗi 6 giờ). Payload ESC/POS là ảnh hóa đơn base64 nên rất nặng:
/// lệnh đã xong quá <see cref="PayloadKeepDays"/> ngày → xóa nội dung (giữ dòng để xem lịch sử);
/// quá <see cref="RetentionDays"/> ngày → xóa hẳn. Xóa theo lô để không khóa bảng lâu.
/// </summary>
public class PosPrintJobCleanupBackgroundService(IServiceProvider services, ILogger<PosPrintJobCleanupBackgroundService> logger)
    : BackgroundService
{
    public const int PayloadKeepDays = 3;
    public const int RetentionDays = 30;
    const int BatchSize = 2000;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await Task.Delay(TimeSpan.FromMinutes(7), stoppingToken);
        while (!stoppingToken.IsCancellationRequested)
        {
            try { await RunOnceAsync(stoppingToken); }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                logger.LogWarning(ex, "Print job cleanup failed");
            }
            await Task.Delay(TimeSpan.FromHours(6), stoppingToken);
        }
    }

    internal async Task RunOnceAsync(CancellationToken ct)
    {
        using var scope = services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();
        var now = DateTime.UtcNow;
        var payloadCut = now.AddDays(-PayloadKeepDays);
        var deleteCut = now.AddDays(-RetentionDays);
        var finished = new[] { PosPrintJobStatus.Completed, PosPrintJobStatus.Failed, PosPrintJobStatus.Cancelled };

        int cleared = 0, removed = 0, n;
        do
        {
            var ids = await db.PosPrintJobs.IgnoreQueryFilters()
                .Where(j => j.CreatedAt < payloadCut && finished.Contains(j.Status) && j.Payload != "")
                .OrderBy(j => j.CreatedAt).Select(j => j.Id).Take(BatchSize).ToListAsync(ct);
            n = ids.Count == 0 ? 0 : await db.PosPrintJobs.IgnoreQueryFilters()
                .Where(j => ids.Contains(j.Id))
                .ExecuteUpdateAsync(s => s.SetProperty(j => j.Payload, ""), ct);
            cleared += n;
        } while (n == BatchSize && !ct.IsCancellationRequested);

        do
        {
            var ids = await db.PosPrintJobs.IgnoreQueryFilters()
                .Where(j => j.CreatedAt < deleteCut && j.Status != PosPrintJobStatus.Queued
                            && j.Status != PosPrintJobStatus.Claimed && j.Status != PosPrintJobStatus.Printing)
                .OrderBy(j => j.CreatedAt).Select(j => j.Id).Take(BatchSize).ToListAsync(ct);
            n = ids.Count == 0 ? 0 : await db.PosPrintJobs.IgnoreQueryFilters()
                .Where(j => ids.Contains(j.Id)).ExecuteDeleteAsync(ct);
            removed += n;
        } while (n == BatchSize && !ct.IsCancellationRequested);

        if (cleared + removed > 0)
            logger.LogInformation("Print job cleanup: cleared payload {Cleared}, deleted {Removed}", cleared, removed);
    }
}
