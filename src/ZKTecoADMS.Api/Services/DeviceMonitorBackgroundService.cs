using System.Collections.Concurrent;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Background service that monitors device connectivity and sends notifications when devices go offline.
/// A device is considered offline if it hasn't sent a heartbeat in the last 2 minutes.
/// </summary>
public class DeviceMonitorBackgroundService : BackgroundService
{
    private readonly IServiceProvider _serviceProvider;
    private readonly ILogger<DeviceMonitorBackgroundService> _logger;
    
    // Check interval: 60 seconds (reduced from 30s to lower DB pressure at scale)
    private readonly TimeSpan _checkInterval = TimeSpan.FromSeconds(60);
    
    // Device is considered offline after 2 minutes of no heartbeat
    private readonly TimeSpan _offlineThreshold = TimeSpan.FromMinutes(2);
    
    // Thread-safe cache for device status tracking
    private readonly ConcurrentDictionary<string, bool> _deviceStatusCache = new();
    private bool _isInitialized = false;

    public DeviceMonitorBackgroundService(
        IServiceProvider serviceProvider,
        ILogger<DeviceMonitorBackgroundService> logger)
    {
        _serviceProvider = serviceProvider;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("🔍 Device Monitor Background Service started");

        // Wait a bit before starting to let the application fully initialize
        await Task.Delay(TimeSpan.FromSeconds(10), stoppingToken);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await CheckDeviceStatusAsync(stoppingToken);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred while checking device status");
            }

            await Task.Delay(_checkInterval, stoppingToken);
        }

        _logger.LogInformation("🔍 Device Monitor Background Service stopped");
    }

    private async Task CheckDeviceStatusAsync(CancellationToken stoppingToken)
    {
        using var scope = _serviceProvider.CreateScope();
        var dbContext = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();
        var notificationService = scope.ServiceProvider.GetService<IDeviceStatusNotificationService>();

        if (notificationService == null)
        {
            _logger.LogWarning("DeviceStatusNotificationService not available");
            return;
        }

        var cutoffTime = DateTime.UtcNow.Subtract(_offlineThreshold);
        
        // Load all devices that are either active OR currently showing as Online
        // This ensures pending devices that received heartbeats are also monitored
        var devices = await dbContext.Devices
            .IgnoreQueryFilters()
            .AsNoTracking()
            .Where(d => d.Deleted == null && (d.IsActive || d.DeviceStatus == "Online"))
            .Select(d => new { d.Id, d.SerialNumber, d.DeviceName, d.LastOnline, d.DeviceStatus, d.StoreId })
            .ToListAsync(stoppingToken);

        _logger.LogDebug("🔍 Checking {Count} active devices, cutoff time: {CutoffTime}", devices.Count, cutoffTime);

        // Collect devices that changed status for batch DB update
        var devicesToSetOffline = new List<Guid>();

        foreach (var device in devices)
        {
            var isOnlineNow = device.LastOnline != null && device.LastOnline > cutoffTime;
            var serialNumber = device.SerialNumber;

            // First time seeing this device - initialize cache
            if (!_deviceStatusCache.TryGetValue(serialNumber, out var wasOnline))
            {
                _deviceStatusCache[serialNumber] = isOnlineNow;
                
                if (!_isInitialized)
                {
                    continue;
                }
            }

            // Status changed from online to offline
            if (wasOnline && !isOnlineNow)
            {
                _logger.LogWarning("📡 Device went OFFLINE: {DeviceName} (SN: {SN}), LastOnline: {LastOnline}", 
                    device.DeviceName, serialNumber, device.LastOnline);
                devicesToSetOffline.Add(device.Id);
                _deviceStatusCache[serialNumber] = false;
            }
            // Status changed from offline to online (update cache only, notification is sent immediately via heartbeat)
            else if (!wasOnline && isOnlineNow)
            {
                _logger.LogInformation("📡 Device came ONLINE (cache update): {DeviceName} (SN: {SN})", 
                    device.DeviceName, serialNumber);
                _deviceStatusCache[serialNumber] = true;
            }
            else
            {
                _deviceStatusCache[serialNumber] = isOnlineNow;
            }
        }

        // Batch update offline devices in one query
        // Guard: only set offline if LastOnline is still stale (prevents race with fresh heartbeat)
        if (devicesToSetOffline.Count > 0)
        {
            await dbContext.Devices
                .Where(d => devicesToSetOffline.Contains(d.Id)
                    && (d.LastOnline == null || d.LastOnline < cutoffTime))
                .ExecuteUpdateAsync(setters => setters
                    .SetProperty(d => d.DeviceStatus, "Offline"), stoppingToken);

            // Batch load devices for notifications instead of N+1
            var offlineDevices = await dbContext.Devices
                .Where(d => devicesToSetOffline.Contains(d.Id))
                .ToListAsync(stoppingToken);
            foreach (var fullDevice in offlineDevices)
            {
                await notificationService.NotifyDeviceOfflineAsync(fullDevice);
            }
        }

        // Batch load devices for online notifications is no longer needed
        // Online notifications are sent immediately via DeviceActiveCheckBehaviour

        // Clean up stale entries: remove devices from cache that no longer exist in DB
        var activeSerials = new HashSet<string>(devices.Select(d => d.SerialNumber));
        var staleKeys = _deviceStatusCache.Keys.Where(k => !activeSerials.Contains(k)).ToList();
        foreach (var staleKey in staleKeys)
        {
            _deviceStatusCache.TryRemove(staleKey, out _);
        }

        // Mark as initialized after first run
        if (!_isInitialized)
        {
            _isInitialized = true;
            _logger.LogInformation("🔍 Device Monitor initialized with {Count} devices in cache", _deviceStatusCache.Count);
        }
    }
}
