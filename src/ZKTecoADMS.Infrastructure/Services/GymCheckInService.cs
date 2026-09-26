using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>
/// Lượt tập hội viên: quét lần đầu trong ngày = vào (trừ 1 buổi, tối đa 1 lần / ngày), quét lần sau = ra.
/// Máy push không có người dùng đăng nhập → luôn lọc StoreId / Deleted tường minh (bỏ bộ lọc tenant).
/// </summary>
public class GymCheckInService(ZKTecoDbContext db, ILogger<GymCheckInService> logger) : IGymCheckInService
{
    public async Task<HashSet<string>> GetMemberPinsAsync(Device device)
    {
        if (!device.StoreId.HasValue) return [];
        var pins = await db.PosGymMemberDevices.IgnoreQueryFilters().AsNoTracking()
            .Where(m => m.DeviceId == device.Id && m.StoreId == device.StoreId && m.Deleted == null)
            .Select(m => m.Pin)
            .ToListAsync();
        return pins.ToHashSet(StringComparer.Ordinal);
    }

    public async Task ProcessPunchesAsync(Device device, IReadOnlyList<Attendance> punches)
    {
        if (!device.StoreId.HasValue || punches.Count == 0) return;
        var storeId = device.StoreId.Value;
        var pins = punches.Select(p => p.PIN).Distinct().ToList();
        var links = await db.PosGymMemberDevices.IgnoreQueryFilters().AsNoTracking()
            .Where(m => m.DeviceId == device.Id && m.StoreId == storeId && m.Deleted == null && pins.Contains(m.Pin))
            .ToListAsync();
        var byPin = links.GroupBy(l => l.Pin).ToDictionary(g => g.Key, g => g.First().CustomerId);

        foreach (var p in punches.OrderBy(p => p.AttendanceTime))
        {
            if (!byPin.TryGetValue(p.PIN, out var customerId)) continue;
            try
            {
                // Máy gửi giờ Việt Nam (không múi giờ) → UTC.
                var utc = DateTime.SpecifyKind(p.AttendanceTime, DateTimeKind.Unspecified).AddHours(-7);
                await RecordPunchAsync(storeId, customerId, utc, device.Id, p.PIN, "Device", "device:" + device.SerialNumber);
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Gym check-in failed for PIN {Pin} on device {DeviceId}", p.PIN, device.Id);
            }
        }
    }

    public async Task<PosGymVisit?> RecordPunchAsync(
        Guid storeId, Guid customerId, DateTime utc, Guid? deviceId, string? pin, string source, string? actor)
    {
        var (dayFrom, dayTo) = GymVisitRules.VnDayUtc(utc);
        var today = await db.PosGymVisits.IgnoreQueryFilters().AsTracking()
            .Where(v => v.StoreId == storeId && v.CustomerId == customerId && v.Deleted == null
                && v.CheckInAt >= dayFrom && v.CheckInAt < dayTo)
            .OrderBy(v => v.CheckInAt)
            .ToListAsync();

        var open = today.LastOrDefault(v => v.CheckOutAt == null && v.CheckInAt <= utc);
        var lastEvent = today
            .SelectMany(v => v.CheckOutAt.HasValue ? new[] { v.CheckInAt, v.CheckOutAt.Value } : new[] { v.CheckInAt })
            .OrderBy(t => (t - utc).Duration())
            .Select(t => (DateTime?)t)
            .FirstOrDefault();

        switch (GymVisitRules.Decide(utc, open?.CheckInAt, lastEvent))
        {
            case GymVisitRules.PunchAction.Ignore:
                return null;
            case GymVisitRules.PunchAction.CheckOut:
                open!.CheckOutAt = utc;
                open.DurationMinutes = (int)Math.Round((utc - open.CheckInAt).TotalMinutes);
                open.UpdatedAt = DateTime.UtcNow;
                open.UpdatedBy = actor;
                await db.SaveChangesAsync();
                return open;
        }

        var visit = new PosGymVisit
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            CustomerId = customerId,
            DeviceId = deviceId,
            Pin = pin,
            CheckInAt = utc,
            Source = source,
            IsActive = true,
            CreatedBy = actor,
        };

        var deductedToday = today.FirstOrDefault(v => v.SessionDeducted);
        if (deductedToday != null)
        {
            // Đã trừ buổi trong ngày: vào lại (sau khi ra) không trừ thêm.
            visit.BalanceId = deductedToday.BalanceId;
            visit.PackageName = deductedToday.PackageName;
            visit.Status = "Ok";
            visit.Note = "Vào lại trong ngày — không trừ thêm buổi";
        }
        else
        {
            var balances = await db.PosCustomerSessionBalances.IgnoreQueryFilters().AsTracking()
                .Where(b => b.StoreId == storeId && b.CustomerId == customerId && b.Deleted == null)
                .ToListAsync();
            var usable = balances
                .Where(b => b.RemainingSessions > 0 && (b.ExpiresAt == null || b.ExpiresAt > utc) && b.CreatedAt <= utc.AddMinutes(5))
                .OrderByDescending(b => PosCustomerSessionBalance.IsUnlimitedCount(b.TotalSessions))
                .ThenBy(b => b.ExpiresAt ?? DateTime.MaxValue)
                .ThenBy(b => b.CreatedAt)
                .FirstOrDefault();
            if (usable == null)
            {
                visit.Status = balances.Count == 0 ? "NoPackage"
                    : balances.Any(b => b.RemainingSessions > 0) ? "Expired"
                    : "OutOfSessions";
                visit.Note = visit.Status switch
                {
                    "Expired" => "Thẻ / gói đã hết hạn",
                    "OutOfSessions" => "Gói đã hết buổi",
                    _ => "Khách chưa có thẻ / gói tập",
                };
            }
            else
            {
                usable.RemainingSessions -= 1;
                usable.UpdatedAt = DateTime.UtcNow;
                usable.UpdatedBy = actor;
                visit.BalanceId = usable.Id;
                visit.PackageName = usable.PackageName;
                visit.SessionDeducted = true;
                visit.Status = "Ok";
                db.PosCustomerSessionTransactions.Add(new PosCustomerSessionTransaction
                {
                    Id = Guid.NewGuid(),
                    StoreId = storeId,
                    BalanceId = usable.Id,
                    CustomerId = customerId,
                    TransactionType = PosSessionTxnType.Redeem,
                    SessionDelta = -1,
                    RemainingAfter = usable.RemainingSessions,
                    UsedAt = utc,
                    Note = source == "Device" ? "Check-in máy chấm công" : "Check-in tại quầy",
                    IsActive = true,
                    CreatedBy = actor,
                });
            }
        }

        db.PosGymVisits.Add(visit);
        await db.SaveChangesAsync();
        return visit;
    }
}
