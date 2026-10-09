using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>
/// Lượt tập hội viên: quét lần đầu trong ngày = vào (trừ 1 buổi, tối đa 1 lần / ngày), quét lần sau = ra.
/// Máy ở cửa bật «máy chủ mở cửa»: thẻ hợp lệ → gửi lệnh mở cửa; hết hạn / hết buổi → không mở,
/// thông báo trên màn hình máy + báo quầy.
/// Máy push không có người dùng đăng nhập → luôn lọc StoreId / Deleted tường minh (bỏ bộ lọc tenant).
/// </summary>
public class GymCheckInService(ZKTecoDbContext db, ILogger<GymCheckInService> logger, IServiceProvider sp) : IGymCheckInService
{
    /// <summary>DeviceSettings: «server» = máy chủ quyết định mở cửa cho hội viên.</summary>
    public const string DoorModeKey = "GymDoorMode";
    public const string DoorModeServer = "server";

    /// <summary>Thông báo trên màn hình máy (không dấu — nhiều máy không hiện tiếng Việt có dấu).</summary>
    public const string ExpiredMessage = "THE TAP HET HAN / HET BUOI - MOI GAP LE TAN";

    readonly IGymRealtimeNotifier? _realtime = sp.GetService<IGymRealtimeNotifier>();

    public async Task<HashSet<string>> GetMemberPinsAsync(Device device)
    {
        if (!device.StoreId.HasValue) return [];
        // Gồm cả liên kết đã gỡ: lệnh xóa người dùng chưa tới máy (máy offline) thì khách vẫn quét được —
        // những lần quét đó không được tính là chấm công nhân viên.
        var pins = await db.PosGymMemberDevices.IgnoreQueryFilters().AsNoTracking()
            .Where(m => m.DeviceId == device.Id && m.StoreId == device.StoreId)
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
        var serverDoor = await IsServerDoorAsync(device.Id);
        var now = DateTime.UtcNow;

        foreach (var p in punches.OrderBy(p => p.AttendanceTime))
        {
            if (!byPin.TryGetValue(p.PIN, out var customerId))
            {
                logger.LogWarning("Gym punch from removed / unknown member PIN {Pin} on device {DeviceId} — ignored", p.PIN, device.Id);
                continue;
            }
            try
            {
                // Máy gửi giờ Việt Nam (không múi giờ) → UTC.
                var utc = DateTime.SpecifyKind(p.AttendanceTime, DateTimeKind.Unspecified).AddHours(-7);
                var visit = await RecordPunchAsync(storeId, customerId, utc, device.Id, p.PIN, "Device", "device:" + device.SerialNumber);
                // Log cũ máy gửi bù (mất mạng lâu) → chỉ ghi lượt, KHÔNG mở cửa / báo quầy.
                if (!GymVisitRules.IsRealtime(utc, now)) continue;

                var last = visit ?? await LastVisitAsync(storeId, customerId, utc);
                var open = serverDoor && GymVisitRules.ShouldOpenDoor(visit, utc, last);
                if (open) QueueOpenDoor(device.Id);
                if (serverDoor) await SyncDeviceAccessCoreAsync(storeId, customerId, onlyDeviceId: device.Id);
                await db.SaveChangesAsync();

                if (last != null) NotifyScan(storeId, last, utc, device.DeviceName, open);
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
        // Lấy cả lượt tối hôm trước còn mở (tập qua nửa đêm: vào 22:00, ra 00:30 là RA, không phải lượt mới trừ thêm buổi).
        var recent = await db.PosGymVisits.IgnoreQueryFilters().AsTracking()
            .Where(v => v.StoreId == storeId && v.CustomerId == customerId && v.Deleted == null
                && v.CheckInAt >= dayFrom - GymVisitRules.MaxOpenVisit && v.CheckInAt < dayTo)
            .OrderBy(v => v.CheckInAt)
            .ToListAsync();
        var today = recent.Where(v => v.CheckInAt >= dayFrom).ToList();

        var open = recent.LastOrDefault(v => v.CheckOutAt == null && v.CheckInAt <= utc
            && utc - v.CheckInAt <= GymVisitRules.MaxOpenVisit);
        var lastEvent = recent
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

    public async Task<int> SyncDeviceAccessAsync(Guid storeId, Guid? customerId = null)
    {
        var changed = await SyncDeviceAccessCoreAsync(storeId, customerId, onlyDeviceId: null);
        if (changed > 0) await db.SaveChangesAsync();
        return changed;
    }

    /// <summary>
    /// Thẻ hết hạn / hết buổi → đẩy thông báo riêng lên máy (hiện khi khách quét); gia hạn → gỡ. Chỉ máy bật
    /// «máy chủ mở cửa» (máy chấm công thường không cần, tránh gửi lệnh máy không hỗ trợ). Chưa SaveChanges.
    /// </summary>
    async Task<int> SyncDeviceAccessCoreAsync(Guid storeId, Guid? customerId, Guid? onlyDeviceId)
    {
        var doorDevices = await db.DeviceSettings.IgnoreQueryFilters().AsNoTracking()
            .Where(s => s.SettingKey == DoorModeKey && s.SettingValue == DoorModeServer)
            .Select(s => s.DeviceId)
            .ToListAsync();
        if (onlyDeviceId.HasValue) doorDevices = doorDevices.Where(d => d == onlyDeviceId.Value).ToList();
        if (doorDevices.Count == 0) return 0;

        var q = db.PosGymMemberDevices.IgnoreQueryFilters().AsTracking()
            .Where(m => m.StoreId == storeId && m.Deleted == null && doorDevices.Contains(m.DeviceId));
        if (customerId.HasValue) q = q.Where(m => m.CustomerId == customerId.Value);
        var links = await q.ToListAsync();
        if (links.Count == 0) return 0;

        var ids = links.Select(l => l.CustomerId).Distinct().ToList();
        var now = DateTime.UtcNow;
        var valid = (await db.PosCustomerSessionBalances.IgnoreQueryFilters().AsNoTracking()
                .Where(b => b.StoreId == storeId && ids.Contains(b.CustomerId) && b.Deleted == null
                    && b.RemainingSessions > 0 && (b.ExpiresAt == null || b.ExpiresAt > now))
                .Select(b => b.CustomerId).Distinct().ToListAsync())
            .ToHashSet();
        // Vào lại trong ngày sau khi dùng buổi cuối vẫn hợp lệ (không trừ thêm) → không báo hết hạn hôm nay.
        var (dayFrom, _) = GymVisitRules.VnDayUtc(now);
        var usedToday = (await db.PosGymVisits.IgnoreQueryFilters().AsNoTracking()
                .Where(v => v.StoreId == storeId && ids.Contains(v.CustomerId) && v.Deleted == null
                    && v.SessionDeducted && v.CheckInAt >= dayFrom)
                .Select(v => v.CustomerId).Distinct().ToListAsync())
            .ToHashSet();

        var changed = 0;
        foreach (var l in links)
        {
            var ok = valid.Contains(l.CustomerId) || usedToday.Contains(l.CustomerId);
            if (ok == !l.AccessBlocked) continue;
            var uid = GymVisitRules.MessageUid(l.Pin);
            if (ok)
                QueueCommand(l.DeviceId, ClockCommandBuilder.BuildDeleteUserMessageCommand(uid), DeviceCommandTypes.UpdateDeviceUser);
            else
                foreach (var cmd in ClockCommandBuilder.BuildUserMessageCommands(l.Pin, uid, ExpiredMessage))
                    QueueCommand(l.DeviceId, cmd, DeviceCommandTypes.UpdateDeviceUser);
            l.AccessBlocked = !ok;
            l.AccessSyncedAt = now;
            changed++;
        }
        return changed;
    }

    async Task<bool> IsServerDoorAsync(Guid deviceId) =>
        await db.DeviceSettings.IgnoreQueryFilters().AsNoTracking()
            .AnyAsync(s => s.DeviceId == deviceId && s.SettingKey == DoorModeKey && s.SettingValue == DoorModeServer);

    Task<PosGymVisit?> LastVisitAsync(Guid storeId, Guid customerId, DateTime utc) =>
        db.PosGymVisits.IgnoreQueryFilters().AsNoTracking()
            .Where(v => v.StoreId == storeId && v.CustomerId == customerId && v.Deleted == null
                && v.CheckInAt <= utc && v.CheckInAt >= utc - GymVisitRules.MaxOpenVisit)
            .OrderByDescending(v => v.CheckInAt)
            .FirstOrDefaultAsync();

    /// <summary>Mở cửa: cùng lệnh nút «Mở cửa» (SenseFace 2A: C:OPENDOORn:AC_UNLOCK, giao qua getrequest).</summary>
    void QueueOpenDoor(Guid deviceId) =>
        db.DeviceCommands.Add(new DeviceCommand
        {
            DeviceId = deviceId,
            Command = ClockCommandBuilder.BuildOpenDoorCommand(useAccessControlProtocol: false),
            CommandType = DeviceCommandTypes.OpenDoor,
            CommandId = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() % 10_000,
            Priority = 100,
            Status = CommandStatus.Created,
        });

    void QueueCommand(Guid deviceId, string command, DeviceCommandTypes type) =>
        db.DeviceCommands.Add(new DeviceCommand
        {
            DeviceId = deviceId,
            Command = command,
            CommandType = type,
            Priority = 20,
            Status = CommandStatus.Created,
        });

    void NotifyScan(Guid storeId, PosGymVisit v, DateTime punchUtc, string? deviceName, bool doorOpened)
    {
        if (_realtime == null) return;
        try
        {
            var name = db.PosCustomers.IgnoreQueryFilters().AsNoTracking()
                .Where(c => c.Id == v.CustomerId).Select(c => c.Name).FirstOrDefault() ?? "";
            var action = v.CheckOutAt == punchUtc ? "out" : v.CheckInAt == punchUtc ? "in" : "repeat";
            _realtime.GymScan(storeId, new GymScanEvent(v.Id, v.CustomerId, name, deviceName, action, v.Status, v.Note, doorOpened));
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Gym realtime notify failed");
        }
    }
}
