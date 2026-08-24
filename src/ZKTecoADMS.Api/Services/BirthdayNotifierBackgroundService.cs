using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.SystemAdmin;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Phát thông báo chúc mừng sinh nhật mỗi ngày: với mỗi nhân viên có
/// DateOfBirth.Month/Day == hôm nay (theo giờ VN) và còn đang làm việc, gửi 1
/// announcement (InApp + Banner + Push) tới toàn bộ user trong cùng store —
/// để đồng nghiệp nhận được lời chúc và bản thân nhân viên đó cũng thấy.
///
/// Chống gửi trùng: tra SystemAnnouncements có CreatedAt >= 00:00 hôm nay
/// (giờ VN) và Title chứa mã nhân viên — coi như đã gửi.
///
/// Chu kỳ: chạy mỗi 30 phút, chỉ gửi sau 08:00 giờ VN để không "spam" lúc 0h.
/// </summary>
public class BirthdayNotifierBackgroundService : BackgroundService
{
    private readonly IServiceProvider _sp;
    private readonly ILogger<BirthdayNotifierBackgroundService> _logger;
    private readonly TimeSpan _interval = TimeSpan.FromMinutes(30);
    // Local time-zone for "today" calculation (Vietnam: UTC+7). Using a fixed
    // offset avoids dependency on Windows/Linux IANA tz name differences.
    private static readonly TimeSpan _vnOffset = TimeSpan.FromHours(7);
    private const int _earliestHourLocal = 8; // chỉ gửi sau 08:00

    public BirthdayNotifierBackgroundService(IServiceProvider sp,
        ILogger<BirthdayNotifierBackgroundService> logger)
    {
        _sp = sp;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("🎂 BirthdayNotifier service started");
        await Task.Delay(TimeSpan.FromSeconds(60), stoppingToken);
        while (!stoppingToken.IsCancellationRequested)
        {
            try { await RunOnceAsync(stoppingToken); }
            catch (Exception ex) { _logger.LogError(ex, "BirthdayNotifier run failed"); }
            await Task.Delay(_interval, stoppingToken);
        }
    }

    private async Task RunOnceAsync(CancellationToken ct)
    {
        var nowLocal = DateTime.UtcNow + _vnOffset;
        if (nowLocal.Hour < _earliestHourLocal)
        {
            return;
        }

        using var scope = _sp.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();
        var svc = scope.ServiceProvider.GetRequiredService<IAnnouncementService>();

        var month = nowLocal.Month;
        var day = nowLocal.Day;

        // Chỉ NV còn làm việc và đã gắn cửa hàng — thiếu StoreId sẽ broadcast nhầm toàn hệ thống.
        var birthdays = await db.Employees
            .AsNoTracking()
            .Where(e => e.DateOfBirth != null
                && e.DateOfBirth!.Value.Month == month
                && e.DateOfBirth!.Value.Day == day
                && e.StoreId != null
                && e.ResignationDate == null
                && e.WorkStatus != EmployeeWorkStatus.Resigned)
            .Select(e => new
            {
                e.Id,
                e.EmployeeCode,
                e.FirstName,
                e.LastName,
                e.StoreId,
                e.DateOfBirth
            })
            .ToListAsync(ct);

        if (birthdays.Count == 0)
        {
            return;
        }

        // Tìm các announcement đã phát hôm nay để chống lặp.
        var dayStartUtc = (nowLocal.Date - _vnOffset);
        var todaysAnnouncements = await db.SystemAnnouncements
            .AsNoTracking()
            .Where(a => a.CreatedAt >= dayStartUtc && a.Kind == AnnouncementKind.News)
            .Select(a => new { a.Title, a.ActionUrl, a.AudienceJson })
            .ToListAsync(ct);

        foreach (var emp in birthdays)
        {
            if (!emp.StoreId.HasValue) continue;

            var bdayKey = $"sbox://birthday/{emp.Id:N}";
            var storeIdStr = emp.StoreId.Value.ToString();
            var alreadySent = todaysAnnouncements.Any(a =>
                a.ActionUrl == bdayKey
                || (a.Title != null && a.Title.Contains($"[BDAY:{emp.Id:N}]", StringComparison.Ordinal))
                || (a.Title != null
                    && a.Title.Contains($"[BDAY:{emp.EmployeeCode}]", StringComparison.Ordinal)
                    && a.AudienceJson != null
                    && a.AudienceJson.Contains(storeIdStr, StringComparison.OrdinalIgnoreCase)));
            if (alreadySent)
            {
                continue;
            }

            var fullName = string.Join(" ",
                new[] { emp.LastName, emp.FirstName }
                    .Where(s => !string.IsNullOrWhiteSpace(s)));
            var age = emp.DateOfBirth.HasValue
                ? nowLocal.Year - emp.DateOfBirth.Value.Year
                : 0;

            var title = $"🎂 Chúc mừng sinh nhật {fullName}!";
            var content = age > 0
                ? $"Hôm nay là sinh nhật lần thứ {age} của {fullName}. " +
                  "Cùng gửi lời chúc mừng và những điều tốt đẹp nhất tới đồng nghiệp nhé! 🎉🎁"
                : $"Hôm nay là sinh nhật của {fullName}. " +
                  "Cùng gửi lời chúc mừng và những điều tốt đẹp nhất tới đồng nghiệp nhé! 🎉🎁";

            // Audience: chỉ user của đúng cửa hàng đó. Không AllUsers.
            var audience = new AudienceSpec
            {
                AllUsers = false,
                StoreIds = new List<Guid> { emp.StoreId.Value }
            };

            try
            {
                await svc.CreateAsync(new CreateSystemAnnouncementDto
                {
                    Title = title,
                    Content = content,
                    Kind = AnnouncementKind.News,
                    Severity = AnnouncementSeverity.Info,
                    // InApp đã FCM; không gắn thêm kênh Push (tránh 2 thông báo cùng nội dung).
                    Channels = NotificationChannel.InApp | NotificationChannel.Banner,
                    RequireAck = false,
                    AllowDismiss = true,
                    Audience = audience,
                    ActionUrl = bdayKey,
                    SendNow = true,
                    ExpiresAt = nowLocal.Date.AddDays(1) - _vnOffset
                }, Guid.Empty, ct);
                _logger.LogInformation("🎂 Sent birthday announcement for {Code} ({Name})",
                    emp.EmployeeCode, fullName);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed sending birthday announcement for {Code}",
                    emp.EmployeeCode);
            }
        }
    }
}
