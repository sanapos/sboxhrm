using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Background service tự động dọn dẹp dữ liệu field:
/// - EmployeeLiveLocations: xóa bản ghi cũ hơn 1 ngày
/// - RoutePointsJson trong JourneyTrackings: xóa route points cũ hơn 7 ngày
/// - Ảnh chấm công (PhotoUrlsJson): chỉ giữ ảnh ngoài công ty, xóa sau 45 ngày
/// Chạy mỗi 24 giờ.
/// </summary>
public class FieldDataCleanupBackgroundService : BackgroundService
{
    private readonly IServiceProvider _serviceProvider;
    private readonly ILogger<FieldDataCleanupBackgroundService> _logger;
    private readonly TimeSpan _checkInterval = TimeSpan.FromHours(24);
    private const int LiveLocationRetentionDays = 1;
    private const int RoutePointsRetentionDays = 7;
    private const int PhotoRetentionDays = 45;

    public FieldDataCleanupBackgroundService(
        IServiceProvider serviceProvider,
        ILogger<FieldDataCleanupBackgroundService> logger)
    {
        _serviceProvider = serviceProvider;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("🧹 Field Data Cleanup Background Service started (live: {LiveDays}d, routes: {RouteDays}d, photos: {PhotoDays}d)",
            LiveLocationRetentionDays, RoutePointsRetentionDays, PhotoRetentionDays);

        await Task.Delay(TimeSpan.FromMinutes(5), stoppingToken);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await CleanupAsync(stoppingToken);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in field data cleanup service");
            }

            await Task.Delay(_checkInterval, stoppingToken);
        }
    }

    private async Task CleanupAsync(CancellationToken stoppingToken)
    {
        using var scope = _serviceProvider.CreateScope();
        var dbContext = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();
        var fileStorage = scope.ServiceProvider.GetRequiredService<IFileStorageService>();

        // 1. Delete old EmployeeLiveLocations (> 1 day)
        var liveCutoff = DateTime.UtcNow.AddDays(-LiveLocationRetentionDays);
        var deletedLive = await dbContext.EmployeeLiveLocations
            .Where(l => l.UpdatedAt < liveCutoff)
            .ExecuteDeleteAsync(stoppingToken);
        if (deletedLive > 0)
            _logger.LogInformation("Deleted {Count} old live locations (> {Days}d)", deletedLive, LiveLocationRetentionDays);

        // 2. Clear RoutePointsJson from old journeys (> 7 days) to save DB space
        var routeCutoff = DateTime.UtcNow.AddDays(-RoutePointsRetentionDays);
        var clearedRoutes = await dbContext.JourneyTrackings
            .Where(j => j.JourneyDate < routeCutoff && j.RoutePointsJson != null)
            .ExecuteUpdateAsync(s => s.SetProperty(j => j.RoutePointsJson, (string?)null), stoppingToken);
        if (clearedRoutes > 0)
            _logger.LogInformation("Cleared route points from {Count} old journeys (> {Days}d)", clearedRoutes, RoutePointsRetentionDays);

        // 3. Delete photos from old visit reports (> 45 days)
        // Only keep photos where outsideRadius = true (ngoài công ty)
        var photoCutoff = DateTime.UtcNow.AddDays(-PhotoRetentionDays);

        // 3a. Delete ALL photos from visits that are INSIDE radius (not outside company)
        var insideVisitsWithPhotos = await dbContext.VisitReports
            .Where(v => v.OutsideRadius == false && v.PhotoUrlsJson != null && v.PhotoUrlsJson != "[]")
            .Select(v => new { v.Id, v.PhotoUrlsJson })
            .ToListAsync(stoppingToken);

        var deletedInsidePhotos = 0;
        foreach (var visit in insideVisitsWithPhotos)
        {
            try
            {
                var urls = System.Text.Json.JsonSerializer.Deserialize<List<string>>(visit.PhotoUrlsJson!);
                if (urls != null)
                {
                    foreach (var url in urls)
                    {
                        await fileStorage.DeleteAsync(url);
                        deletedInsidePhotos++;
                    }
                }
            }
            catch { }
        }
        if (insideVisitsWithPhotos.Count > 0)
        {
            await dbContext.VisitReports
                .Where(v => v.OutsideRadius == false && v.PhotoUrlsJson != null && v.PhotoUrlsJson != "[]")
                .ExecuteUpdateAsync(s => s.SetProperty(v => v.PhotoUrlsJson, "[]"), stoppingToken);
            _logger.LogInformation("Deleted {PhotoCount} photos from {VisitCount} inside-radius visits",
                deletedInsidePhotos, insideVisitsWithPhotos.Count);
        }

        // 3b. Delete photos from outside-radius visits older than 45 days
        var oldOutsideVisits = await dbContext.VisitReports
            .Where(v => v.OutsideRadius == true && v.VisitDate < photoCutoff && v.PhotoUrlsJson != null && v.PhotoUrlsJson != "[]")
            .Select(v => new { v.Id, v.PhotoUrlsJson })
            .ToListAsync(stoppingToken);

        var deletedOldPhotos = 0;
        foreach (var visit in oldOutsideVisits)
        {
            try
            {
                var urls = System.Text.Json.JsonSerializer.Deserialize<List<string>>(visit.PhotoUrlsJson!);
                if (urls != null)
                {
                    foreach (var url in urls)
                    {
                        await fileStorage.DeleteAsync(url);
                        deletedOldPhotos++;
                    }
                }
            }
            catch { }
        }
        if (oldOutsideVisits.Count > 0)
        {
            await dbContext.VisitReports
                .Where(v => v.OutsideRadius == true && v.VisitDate < photoCutoff && v.PhotoUrlsJson != null && v.PhotoUrlsJson != "[]")
                .ExecuteUpdateAsync(s => s.SetProperty(v => v.PhotoUrlsJson, "[]"), stoppingToken);
            _logger.LogInformation("Deleted {PhotoCount} photos from {VisitCount} old outside-radius visits (> {Days}d)",
                deletedOldPhotos, oldOutsideVisits.Count, PhotoRetentionDays);
        }
    }
}
