using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Mỗi 6 giờ: xóa ảnh bằng chứng chấm công mobile (ảnh hiện trường / ảnh mặt) của các bản đã duyệt/từ chối
/// quá hạn lưu của cửa hàng (mặc định 30 ngày).
/// </summary>
public class AttendanceEvidencePurgeBackgroundService(IServiceProvider sp, ILogger<AttendanceEvidencePurgeBackgroundService> logger) : BackgroundService
{
    public const int DefaultRetentionDays = 30;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await Task.Delay(TimeSpan.FromMinutes(3), stoppingToken);
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                using var scope = sp.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();
                var storage = scope.ServiceProvider.GetRequiredService<IFileStorageService>();
                var n = await PurgeAsync(db, path => storage.DeleteAsync(path), DateTime.UtcNow, stoppingToken);
                if (n > 0) logger.LogInformation("Purged evidence photos of {Count} mobile attendance records", n);
            }
            catch (Exception ex) { logger.LogError(ex, "Attendance evidence purge failed"); }
            await Task.Delay(TimeSpan.FromHours(6), stoppingToken);
        }
    }

    public static async Task<int> PurgeAsync(ZKTecoDbContext db, Func<string, Task> deleteFile, DateTime nowUtc, CancellationToken ct)
    {
        var retention = await db.MobileAttendanceSettings.IgnoreQueryFilters().AsNoTracking()
            .Where(s => s.Deleted == null)
            .Select(s => new { s.StoreId, s.EvidenceRetentionDays })
            .ToListAsync(ct);
        var byStore = retention.GroupBy(r => r.StoreId).ToDictionary(g => g.Key, g => Math.Max(1, g.First().EvidenceRetentionDays));
        var minCutoff = nowUtc.AddDays(-1);
        var total = 0;
        for (var round = 0; round < 20; round++)
        {
            var batch = await db.MobileAttendanceRecords.IgnoreQueryFilters().AsTracking()
                .Where(r => r.EvidencePurgedAt == null && r.Status != "pending"
                    && (r.SitePhotoUrl != null || r.FaceImageUrl != null)
                    && (r.ApprovedAt ?? r.CreatedAt) < minCutoff)
                .OrderBy(r => r.ApprovedAt ?? r.CreatedAt)
                .Take(200)
                .ToListAsync(ct);
            var due = batch.Where(r => (r.ApprovedAt ?? r.CreatedAt) < nowUtc.AddDays(-byStore.GetValueOrDefault(r.StoreId, DefaultRetentionDays))).ToList();
            if (due.Count == 0) break;
            foreach (var r in due)
            {
                foreach (var path in new[] { r.SitePhotoUrl, r.FaceImageUrl })
                {
                    if (string.IsNullOrWhiteSpace(path)) continue;
                    try { await deleteFile(path); } catch { /* tệp đã mất vẫn đánh dấu đã xóa */ }
                }
                r.SitePhotoUrl = null;
                r.FaceImageUrl = null;
                r.EvidencePurgedAt = nowUtc;
            }
            await db.SaveChangesAsync(ct);
            total += due.Count;
            if (batch.Count < 200) break;
        }
        return total;
    }
}
