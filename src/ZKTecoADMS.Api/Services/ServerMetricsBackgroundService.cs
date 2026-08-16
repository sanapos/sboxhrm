using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Lấy mẫu CPU/RAM mỗi phút, lưu lịch sử 7 ngày, cảnh báo SuperAdmin khi ≥ 70%.
/// </summary>
public class ServerMetricsBackgroundService : BackgroundService
{
    public const double AlertThreshold = ServerMetricsSnapshot.AlertThresholdPercent;
    private static readonly TimeSpan SampleInterval = TimeSpan.FromMinutes(1);
    private static readonly TimeSpan AlertCooldown = TimeSpan.FromMinutes(30);
    private static readonly TimeSpan Retention = TimeSpan.FromDays(7);

    private readonly IServiceProvider _sp;
    private readonly ILogger<ServerMetricsBackgroundService> _logger;
    private readonly ServerMetricsState _state;
    private CpuTick _prevCpu;
    private DateTime _lastAlertUtc = DateTime.MinValue;
    private DateTime _lastCleanupUtc = DateTime.MinValue;

    public ServerMetricsBackgroundService(
        IServiceProvider sp,
        ILogger<ServerMetricsBackgroundService> logger,
        ServerMetricsState state)
    {
        _sp = sp;
        _logger = logger;
        _state = state;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("Server metrics collector started (alert ≥ {Threshold}%)", AlertThreshold);
        try
        {
            await Task.Delay(TimeSpan.FromSeconds(8), stoppingToken);
        }
        catch (OperationCanceledException)
        {
            return;
        }

        _prevCpu = ServerResourceReader.ReadCpuTick();

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await SampleOnceAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Server metrics sample failed");
            }

            try
            {
                await Task.Delay(SampleInterval, stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
        }
    }

    private async Task SampleOnceAsync(CancellationToken ct)
    {
        var snapshot = await ServerResourceReader.CaptureAsync(_prevCpu, ct);
        var tick = ServerResourceReader.ReadCpuTick();
        if (tick.Total > 0) _prevCpu = tick;
        _state.Set(snapshot);

        using var scope = _sp.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();
        db.ServerMetricSamples.Add(new ServerMetricSample
        {
            Id = Guid.NewGuid(),
            SampledAt = snapshot.SampledAt,
            CpuPercent = snapshot.CpuPercent,
            RamPercent = snapshot.RamPercent,
            RamUsedMb = snapshot.RamUsedMb,
            RamTotalMb = snapshot.RamTotalMb,
            ProcessWorkingSetMb = snapshot.ProcessWorkingSetMb,
            Source = snapshot.Source,
            CreatedBy = "system",
        });
        await db.SaveChangesAsync(ct);

        if (DateTime.UtcNow - _lastCleanupUtc > TimeSpan.FromHours(6))
        {
            var cutoff = DateTime.UtcNow.Subtract(Retention);
            await db.ServerMetricSamples.Where(x => x.SampledAt < cutoff).ExecuteDeleteAsync(ct);
            _lastCleanupUtc = DateTime.UtcNow;
        }

        if (!snapshot.AnyAlert || DateTime.UtcNow - _lastAlertUtc < AlertCooldown)
            return;

        var parts = new List<string>();
        if (snapshot.CpuAlert)
            parts.Add($"CPU {snapshot.CpuPercent:0.#}%");
        if (snapshot.RamAlert)
            parts.Add($"RAM {snapshot.RamPercent:0.#}% ({snapshot.RamUsedMb}/{snapshot.RamTotalMb} MB)");
        if (snapshot.DiskAlert)
            parts.Add($"ổ cứng {snapshot.DiskPercent:0.#}% (còn {snapshot.DiskFreeMb} MB / {snapshot.DiskTotalMb} MB)");

        var title = "Cảnh báo hiệu năng server";
        var message =
            $"{string.Join(" và ", parts)} vượt ngưỡng {AlertThreshold}%. Kiểm tra Super Admin → Tổng quan.";

        var notifications = scope.ServiceProvider.GetRequiredService<ISystemNotificationService>();
        var users = scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
        await SuperAdminNotificationHelper.NotifySuperAdminsAsync(
            notifications,
            users,
            NotificationType.Warning,
            title,
            message,
            relatedUrl: SuperAdminNotificationHelper.AdminDashboardUrl,
            relatedEntityType: "ServerMetrics",
            categoryCode: "system");
        _lastAlertUtc = DateTime.UtcNow;
        _logger.LogWarning("Server metrics alert: {Message}", message);
    }
}
