using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Helpers;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Xóa chấm công / hóa đơn cũ theo cấu hình từng gói dịch vụ.
/// Chỉ cửa hàng đang gán gói đó. Chạy vào giờ đã cài (múi giờ Việt Nam).
/// </summary>
public class PackageDataRetentionBackgroundService : BackgroundService
{
    private readonly IServiceProvider _serviceProvider;
    private readonly ILogger<PackageDataRetentionBackgroundService> _logger;
    private readonly Dictionary<Guid, DateOnly> _ranOn = new();

    public PackageDataRetentionBackgroundService(
        IServiceProvider serviceProvider,
        ILogger<PackageDataRetentionBackgroundService> logger)
    {
        _serviceProvider = serviceProvider;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("Package data retention service started");
        await Task.Delay(TimeSpan.FromMinutes(3), stoppingToken);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await RunDuePackagesAsync(stoppingToken);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Package data retention run failed");
            }

            await Task.Delay(TimeSpan.FromMinutes(10), stoppingToken);
        }
    }

    private async Task RunDuePackagesAsync(CancellationToken stoppingToken)
    {
        var now = VietnamNow();
        using var scope = _serviceProvider.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();

        var packages = await db.ServicePackages.AsNoTracking()
            .Where(p => p.IsActive)
            .Select(p => new { p.Id, p.Name, p.DataRetentionJson })
            .ToListAsync(stoppingToken);

        foreach (var package in packages)
        {
            var rule = StorePackageHelper.ParseRetention(package.DataRetentionJson);
            if (rule.AttendanceMonths <= 0 && rule.SaleOrderMonths <= 0) continue;
            if (now.Hour != rule.RunHour) continue;
            if (_ranOn.TryGetValue(package.Id, out var day) && day == DateOnly.FromDateTime(now))
                continue;

            var storeIds = await db.Stores.AsNoTracking()
                .Where(s => s.ServicePackageId == package.Id)
                .Select(s => s.Id)
                .ToListAsync(stoppingToken);

            foreach (var storeId in storeIds)
            {
                if (rule.AttendanceMonths > 0)
                {
                    var cutoff = now.AddMonths(-rule.AttendanceMonths);
                    var punches = await DeleteAttendanceAsync(db, storeId, cutoff, stoppingToken);
                    if (punches > 0)
                    {
                        _logger.LogInformation(
                            "Package {Package} store {StoreId}: deleted {Count} attendance rows older than {Months} months",
                            package.Name, storeId, punches, rule.AttendanceMonths);
                    }
                }

                if (rule.SaleOrderMonths > 0)
                {
                    var cutoff = now.AddMonths(-rule.SaleOrderMonths);
                    var orders = await DeleteSaleOrdersAsync(db, storeId, cutoff, stoppingToken);
                    if (orders > 0)
                    {
                        _logger.LogInformation(
                            "Package {Package} store {StoreId}: deleted {Count} sale orders older than {Months} months",
                            package.Name, storeId, orders, rule.SaleOrderMonths);
                    }
                }
            }

            _ranOn[package.Id] = DateOnly.FromDateTime(now);
        }
    }

    private static DateTime VietnamNow() => DateTime.SpecifyKind(DateTime.UtcNow.AddHours(7), DateTimeKind.Unspecified);

    private static async Task<int> DeleteAttendanceAsync(
        ZKTecoDbContext db, Guid storeId, DateTime cutoff, CancellationToken stoppingToken)
    {
        var deviceIds = await db.Devices.AsNoTracking()
            .Where(d => d.StoreId == storeId)
            .Select(d => d.Id)
            .ToListAsync(stoppingToken);

        var logIds = deviceIds.Count == 0
            ? new List<Guid>()
            : await db.AttendanceLogs.IgnoreQueryFilters()
                .Where(a => deviceIds.Contains(a.DeviceId) && a.AttendanceTime < cutoff)
                .Select(a => a.Id)
                .ToListAsync(stoppingToken);

        if (logIds.Count > 0)
        {
            await db.AttendanceCorrectionRequests.IgnoreQueryFilters()
                .Where(x => x.AttendanceId != null && logIds.Contains(x.AttendanceId.Value))
                .ExecuteUpdateAsync(s => s.SetProperty(x => x.AttendanceId, (Guid?)null), stoppingToken);
            await db.MealRecords.IgnoreQueryFilters()
                .Where(x => x.AttendanceId != null && logIds.Contains(x.AttendanceId.Value))
                .ExecuteUpdateAsync(s => s.SetProperty(x => x.AttendanceId, (Guid?)null), stoppingToken);
            await db.PenaltyTickets.IgnoreQueryFilters()
                .Where(x => x.AttendanceId != null && logIds.Contains(x.AttendanceId.Value))
                .ExecuteUpdateAsync(s => s.SetProperty(x => x.AttendanceId, (Guid?)null), stoppingToken);
            await db.Shifts.IgnoreQueryFilters()
                .Where(x => x.CheckInAttendanceId != null && logIds.Contains(x.CheckInAttendanceId.Value))
                .ExecuteUpdateAsync(s => s.SetProperty(x => x.CheckInAttendanceId, (Guid?)null), stoppingToken);
            await db.Shifts.IgnoreQueryFilters()
                .Where(x => x.CheckOutAttendanceId != null && logIds.Contains(x.CheckOutAttendanceId.Value))
                .ExecuteUpdateAsync(s => s.SetProperty(x => x.CheckOutAttendanceId, (Guid?)null), stoppingToken);
            await db.AttendanceLogs.IgnoreQueryFilters()
                .Where(a => logIds.Contains(a.Id))
                .ExecuteDeleteAsync(stoppingToken);
        }

        var mobile = await db.MobileAttendanceRecords.IgnoreQueryFilters()
            .Where(m => m.StoreId == storeId && m.PunchTime < cutoff)
            .ExecuteDeleteAsync(stoppingToken);

        return logIds.Count + mobile;
    }

    private static async Task<int> DeleteSaleOrdersAsync(
        ZKTecoDbContext db, Guid storeId, DateTime cutoff, CancellationToken stoppingToken)
    {
        var orderIds = await db.PosSaleOrders.IgnoreQueryFilters()
            .Where(o => o.StoreId == storeId
                && o.Status != PosSaleOrderStatus.Draft
                && (o.SaleDate ?? o.CreatedAt) < cutoff)
            .Select(o => o.Id)
            .ToListAsync(stoppingToken);
        if (orderIds.Count == 0) return 0;

        await db.PosSaleOrderLines.IgnoreQueryFilters()
            .Where(l => orderIds.Contains(l.SaleOrderId))
            .ExecuteDeleteAsync(stoppingToken);
        await db.PosSaleCommissionLines.IgnoreQueryFilters()
            .Where(l => orderIds.Contains(l.SaleOrderId))
            .ExecuteDeleteAsync(stoppingToken);
        await db.PosProductWarrantyRegistrations.IgnoreQueryFilters()
            .Where(l => orderIds.Contains(l.SaleOrderId))
            .ExecuteDeleteAsync(stoppingToken);
        await db.PosStockTransactions.IgnoreQueryFilters()
            .Where(l => l.SaleOrderId != null && orderIds.Contains(l.SaleOrderId.Value))
            .ExecuteUpdateAsync(s => s.SetProperty(x => x.SaleOrderId, (Guid?)null), stoppingToken);
        await db.PosCustomerPayments.IgnoreQueryFilters()
            .Where(l => l.SaleOrderId != null && orderIds.Contains(l.SaleOrderId.Value))
            .ExecuteUpdateAsync(s => s.SetProperty(x => x.SaleOrderId, (Guid?)null), stoppingToken);
        await db.PosCustomerPointTransactions.IgnoreQueryFilters()
            .Where(l => l.SaleOrderId != null && orderIds.Contains(l.SaleOrderId.Value))
            .ExecuteUpdateAsync(s => s.SetProperty(x => x.SaleOrderId, (Guid?)null), stoppingToken);
        await db.PosKitchenVoidSlips.IgnoreQueryFilters()
            .Where(l => l.SaleOrderId != null && orderIds.Contains(l.SaleOrderId.Value))
            .ExecuteUpdateAsync(s => s.SetProperty(x => x.SaleOrderId, (Guid?)null), stoppingToken);
        await db.PosCancelReturnAudits.IgnoreQueryFilters()
            .Where(l => l.SaleOrderId != null && orderIds.Contains(l.SaleOrderId.Value))
            .ExecuteUpdateAsync(s => s.SetProperty(x => x.SaleOrderId, (Guid?)null), stoppingToken);
        await db.PosCustomerSessionTransactions.IgnoreQueryFilters()
            .Where(l => l.SaleOrderId != null && orderIds.Contains(l.SaleOrderId.Value))
            .ExecuteUpdateAsync(s => s.SetProperty(x => x.SaleOrderId, (Guid?)null), stoppingToken);
        await db.PosTransferPaymentIntents.IgnoreQueryFilters()
            .Where(l => l.SaleOrderId != null && orderIds.Contains(l.SaleOrderId.Value))
            .ExecuteUpdateAsync(s => s.SetProperty(x => x.SaleOrderId, (Guid?)null), stoppingToken);
        await db.PosResourceSessions.IgnoreQueryFilters()
            .Where(l => l.SaleOrderId != null && orderIds.Contains(l.SaleOrderId.Value))
            .ExecuteUpdateAsync(s => s.SetProperty(x => x.SaleOrderId, (Guid?)null), stoppingToken);

        return await db.PosSaleOrders.IgnoreQueryFilters()
            .Where(o => orderIds.Contains(o.Id))
            .ExecuteDeleteAsync(stoppingToken);
    }
}
