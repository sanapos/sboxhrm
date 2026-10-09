using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Hội viên quét ở máy cửa: còn hạn → lệnh mở cửa; hết hạn → không mở, thông báo trên máy + báo quầy.</summary>
[Collection("pos-pg")]
public class GymDoorTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    sealed class FakeNotifier : IGymRealtimeNotifier
    {
        public readonly List<GymScanEvent> Events = [];
        public void GymScan(Guid storeId, GymScanEvent e) => Events.Add(e);
    }

    static GymCheckInService Service(ZKTecoDbContext db, FakeNotifier n)
    {
        var sp = new ServiceCollection().AddSingleton<IGymRealtimeNotifier>(n).BuildServiceProvider();
        return new GymCheckInService(db, NullLogger<GymCheckInService>.Instance, sp);
    }

    async Task<(Guid Store, Device Device)> SeedDeviceAsync(bool serverDoor)
    {
        var store = await Fx.NewStoreAsync();
        await using var db = Fx.NewDb();
        var manager = await db.Users.Where(u => u.StoreId == store).Select(u => u.Id).FirstAsync();
        var device = new Device
        {
            Id = Guid.NewGuid(), StoreId = store, ManagerId = manager, SerialNumber = "SF2A" + store.ToString("N")[..8],
            DeviceName = "Cửa chính", LastOnline = DateTime.UtcNow, IsActive = true,
        };
        var info = new DeviceInfo { Id = Guid.NewGuid(), DeviceId = device.Id, SupportsDoorControl = true, DeviceModelName = "SenseFace 2A" };
        device.DeviceInfoId = info.Id;
        db.Devices.Add(device);
        db.Add(info);
        if (serverDoor)
            db.DeviceSettings.Add(new DeviceSetting
            {
                Id = Guid.NewGuid(), DeviceId = device.Id,
                SettingKey = GymCheckInService.DoorModeKey, SettingValue = GymCheckInService.DoorModeServer,
            });
        await db.SaveChangesAsync();
        return (store, device);
    }

    async Task<Guid> AddMemberAsync(Guid store, Guid deviceId, string name, string phone, int sessions, DateTime? expires)
    {
        await using var db = Fx.NewDb();
        var c = new PosCustomer { Id = Guid.NewGuid(), StoreId = store, CustomerCode = "HV" + phone[^6..], Name = name, Phone = phone, IsActive = true };
        db.PosCustomers.Add(c);
        if (sessions >= 0)
            db.PosCustomerSessionBalances.Add(new PosCustomerSessionBalance
            {
                Id = Guid.NewGuid(), StoreId = store, CustomerId = c.Id, PackageName = "Gói 12 buổi",
                TotalSessions = 12, RemainingSessions = sessions, ExpiresAt = expires, IsActive = true,
                CreatedAt = DateTime.UtcNow.AddDays(-10),
            });
        db.PosGymMemberDevices.Add(new PosGymMemberDevice
        {
            Id = Guid.NewGuid(), StoreId = store, CustomerId = c.Id, DeviceId = deviceId,
            Pin = GymVisitRules.PinFromPhone(phone)!, IsActive = true,
        });
        await db.SaveChangesAsync();
        return c.Id;
    }

    static Attendance Punch(string pin, DateTime utc) =>
        new() { Id = Guid.NewGuid(), PIN = pin, AttendanceTime = DateTime.SpecifyKind(utc.AddHours(7), DateTimeKind.Unspecified) };

    async Task<List<DeviceCommand>> CommandsAsync(Guid deviceId)
    {
        await using var db = Fx.NewDb();
        return await db.DeviceCommands.Where(c => c.DeviceId == deviceId).OrderBy(c => c.CreatedAt).ToListAsync();
    }

    [Fact]
    public async Task Con_han_thi_mo_cua_het_han_thi_khong_mo_va_bao_tren_may()
    {
        if (NoDb) return;
        var (store, device) = await SeedDeviceAsync(serverDoor: true);
        var ok = await AddMemberAsync(store, device.Id, "Nguyễn An", "0973024042", 10, DateTime.UtcNow.AddDays(20));
        var expired = await AddMemberAsync(store, device.Id, "Lê Bình", "0905111222", 5, DateTime.UtcNow.AddDays(-1));
        var notifier = new FakeNotifier();
        var now = DateTime.UtcNow;

        await using (var db = Fx.NewDb())
            await Service(db, notifier).ProcessPunchesAsync(device, [Punch("973024042", now), Punch("905111222", now.AddSeconds(5))]);

        var cmds = await CommandsAsync(device.Id);
        Assert.Single(cmds, c => c.CommandType == DeviceCommandTypes.OpenDoor && c.Command == "AC_UNLOCK");
        // Khách hết hạn: thông báo riêng gắn với PIN của khách, không mở cửa.
        Assert.Contains(cmds, c => c.Command.StartsWith("DATA UPDATE SMS MSG=THE TAP HET HAN") && c.Command.Contains("UID=905111222"));
        Assert.Contains(cmds, c => c.Command == "DATA UPDATE USER_SMS PIN=905111222\tUID=905111222");
        Assert.DoesNotContain(cmds, c => c.Command.Contains("973024042") && c.Command.Contains("SMS"));

        Assert.Equal(2, notifier.Events.Count);
        Assert.True(notifier.Events.Single(e => e.CustomerId == ok).DoorOpened);
        var bad = notifier.Events.Single(e => e.CustomerId == expired);
        Assert.False(bad.DoorOpened);
        Assert.Equal("Expired", bad.Status);

        await using (var db = Fx.NewDb())
        {
            var link = await db.PosGymMemberDevices.FirstAsync(m => m.CustomerId == expired);
            Assert.True(link.AccessBlocked);
            // Gia hạn → gỡ thông báo trên máy.
            db.PosCustomerSessionBalances.Add(new PosCustomerSessionBalance
            {
                Id = Guid.NewGuid(), StoreId = store, CustomerId = expired, PackageName = "Gói tháng",
                TotalSessions = 30, RemainingSessions = 30, ExpiresAt = DateTime.UtcNow.AddDays(30), IsActive = true,
            });
            await db.SaveChangesAsync();
        }
        await using (var db = Fx.NewDb())
            Assert.Equal(1, await Service(db, notifier).SyncDeviceAccessAsync(store));
        Assert.Contains(await CommandsAsync(device.Id), c => c.Command == "DATA DELETE SMS UID=905111222");
        await using (var db = Fx.NewDb())
            Assert.False((await db.PosGymMemberDevices.FirstAsync(m => m.CustomerId == expired)).AccessBlocked);
    }

    [Fact]
    public async Task Log_cu_gui_bu_khong_mo_cua_va_ra_luon_mo()
    {
        if (NoDb) return;
        var (store, device) = await SeedDeviceAsync(serverDoor: true);
        await AddMemberAsync(store, device.Id, "Trần Cường", "0912345678", 0, DateTime.UtcNow.AddDays(10)); // hết buổi
        var notifier = new FakeNotifier();
        var now = DateTime.UtcNow;

        // Máy mất mạng, 2 tiếng sau mới gửi log → chỉ ghi lượt, không mở cửa, không báo quầy.
        await using (var db = Fx.NewDb())
            await Service(db, notifier).ProcessPunchesAsync(device, [Punch("912345678", now.AddHours(-2))]);
        Assert.DoesNotContain(await CommandsAsync(device.Id), x => x.CommandType == DeviceCommandTypes.OpenDoor);
        Assert.Empty(notifier.Events);

        // Lượt vào (hết buổi) đang mở → quét RA ở máy: luôn mở cửa cho khách ra.
        await using (var db = Fx.NewDb())
            await Service(db, notifier).ProcessPunchesAsync(device, [Punch("912345678", now)]);
        Assert.Single(await CommandsAsync(device.Id), x => x.CommandType == DeviceCommandTypes.OpenDoor);
        Assert.Equal("out", notifier.Events.Single().Action);
    }

    [Fact]
    public async Task Che_do_chi_ghi_luot_khong_gui_lenh_mo_cua()
    {
        if (NoDb) return;
        var (store, device) = await SeedDeviceAsync(serverDoor: false);
        await AddMemberAsync(store, device.Id, "Phạm Dung", "0988000111", 10, null);
        await using (var db = Fx.NewDb())
            await Service(db, new FakeNotifier()).ProcessPunchesAsync(device, [Punch("988000111", DateTime.UtcNow)]);
        Assert.Empty(await CommandsAsync(device.Id));
        await using (var db = Fx.NewDb())
            Assert.Equal(1, await db.PosGymVisits.CountAsync(v => v.StoreId == store && v.Status == "Ok"));
    }

    [Fact]
    public async Task Tap_qua_nua_dem_la_ra_khong_tru_them_buoi()
    {
        if (NoDb) return;
        var (store, device) = await SeedDeviceAsync(serverDoor: false);
        var c = await AddMemberAsync(store, device.Id, "Hoàng Em", "0977000222", 10, null);
        var inUtc = new DateTime(2026, 10, 8, 15, 0, 0, DateTimeKind.Utc);   // 22:00 VN
        var outUtc = new DateTime(2026, 10, 8, 17, 30, 0, DateTimeKind.Utc); // 00:30 VN hôm sau
        await using (var db = Fx.NewDb())
        {
            var svc = Service(db, new FakeNotifier());
            await svc.RecordPunchAsync(store, c, inUtc, device.Id, "977000222", "Device", "t");
            var v = await svc.RecordPunchAsync(store, c, outUtc, device.Id, "977000222", "Device", "t");
            Assert.NotNull(v);
            Assert.Equal(outUtc, v!.CheckOutAt);
            Assert.Equal(150, v.DurationMinutes);
        }
        await using (var db = Fx.NewDb())
        {
            Assert.Equal(1, await db.PosGymVisits.CountAsync(v => v.CustomerId == c));
            Assert.Equal(9, (await db.PosCustomerSessionBalances.FirstAsync(b => b.CustomerId == c)).RemainingSessions);
        }
    }
}
