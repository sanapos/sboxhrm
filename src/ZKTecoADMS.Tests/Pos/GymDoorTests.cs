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

    [Fact]
    public async Task Het_han_quet_lai_sau_3_phut_van_khong_mo_cua()
    {
        if (NoDb) return;
        var (store, device) = await SeedDeviceAsync(serverDoor: true);
        var c = await AddMemberAsync(store, device.Id, "Lý Hạnh", "0988111222", 5, DateTime.UtcNow.AddDays(-1)); // hết hạn
        var notifier = new FakeNotifier();

        await using (var db = Fx.NewDb())
            await Service(db, notifier).ProcessPunchesAsync(device, [Punch("988111222", DateTime.UtcNow)]);
        // Lượt bị từ chối đóng ngay (vào = ra), khách chưa vào phòng.
        await using (var db = Fx.NewDb())
        {
            var v = await db.PosGymVisits.AsTracking().SingleAsync(x => x.CustomerId == c);
            Assert.Equal(v.CheckInAt, v.CheckOutAt);
            Assert.True(GymVisitRules.IsDenied(v.Status, v.CheckInAt, v.CheckOutAt));
            // Giả lập khách đứng chờ 4 phút rồi quét lại (trước đây thành «RA» → mở cửa).
            v.CheckInAt = v.CheckInAt.AddMinutes(-4);
            v.CheckOutAt = v.CheckInAt;
            await db.SaveChangesAsync();
        }
        await using (var db = Fx.NewDb())
            await Service(db, notifier).ProcessPunchesAsync(device, [Punch("988111222", DateTime.UtcNow)]);

        Assert.DoesNotContain(await CommandsAsync(device.Id), x => x.CommandType == DeviceCommandTypes.OpenDoor);
        Assert.All(notifier.Events, e => Assert.Equal("in", e.Action));
        await using (var db = Fx.NewDb())
            Assert.Equal(0, await db.PosGymVisits.CountAsync(v => v.CustomerId == c && v.CheckOutAt == null));
    }

    [Fact]
    public async Task Quen_quet_ra_qua_4_gio_thi_lan_quet_sau_la_vao_moi()
    {
        if (NoDb) return;
        var (store, device) = await SeedDeviceAsync(serverDoor: false);
        var c = await AddMemberAsync(store, device.Id, "Phan Khoa", "0966333444", 10, null);
        var in1 = new DateTime(2026, 10, 9, 0, 0, 0, DateTimeKind.Utc);   // 07:00 VN, quên quét ra
        var back = in1.AddHours(5);                                         // 12:00 VN quay lại
        var leave = back.AddHours(1);
        await using (var db = Fx.NewDb())
        {
            var svc = Service(db, new FakeNotifier());
            await svc.RecordPunchAsync(store, c, in1, device.Id, "966333444", "Device", "t");
            var v2 = await svc.RecordPunchAsync(store, c, back, device.Id, "966333444", "Device", "t");
            Assert.Equal(back, v2!.CheckInAt);               // vào mới, không phải «ra» của lượt 07:00
            Assert.False(v2.SessionDeducted);               // cùng ngày → không trừ thêm
            var v3 = await svc.RecordPunchAsync(store, c, leave, device.Id, "966333444", "Device", "t");
            Assert.Equal(leave, v3!.CheckOutAt);
            Assert.Equal(60, v3.DurationMinutes);
        }
        await using (var db = Fx.NewDb())
        {
            var first = await db.PosGymVisits.SingleAsync(v => v.CustomerId == c && v.CheckInAt == in1);
            Assert.Null(first.CheckOutAt);
            Assert.Contains(GymVisitRules.ForgotCheckoutNote, first.Note);
            Assert.Equal(9, (await db.PosCustomerSessionBalances.FirstAsync(b => b.CustomerId == c)).RemainingSessions);
        }
    }

    [Fact]
    public async Task Da_tru_buoi_tai_quay_hom_nay_thi_quet_may_khong_tru_them()
    {
        if (NoDb) return;
        var (store, device) = await SeedDeviceAsync(serverDoor: false);
        var c = await AddMemberAsync(store, device.Id, "Võ Lan", "0955444555", 10, null);
        var now = DateTime.UtcNow;
        await using (var db = Fx.NewDb())
        {
            var b = await db.PosCustomerSessionBalances.AsTracking().FirstAsync(x => x.CustomerId == c);
            b.RemainingSessions = 9;
            db.PosCustomerSessionTransactions.Add(new PosCustomerSessionTransaction
            {
                Id = Guid.NewGuid(), StoreId = store, BalanceId = b.Id, CustomerId = c,
                TransactionType = PosSessionTxnType.Redeem, SessionDelta = -1, RemainingAfter = 9,
                UsedAt = now.AddMinutes(-30), Note = "Trừ buổi tại quầy", IsActive = true,
            });
            await db.SaveChangesAsync();
        }
        await using (var db = Fx.NewDb())
        {
            var v = await Service(db, new FakeNotifier()).RecordPunchAsync(store, c, now, device.Id, "955444555", "Device", "t");
            Assert.Equal("Ok", v!.Status);
            Assert.False(v.SessionDeducted);
        }
        await using (var db = Fx.NewDb())
            Assert.Equal(9, (await db.PosCustomerSessionBalances.FirstAsync(b => b.CustomerId == c)).RemainingSessions);
    }

    [Fact]
    public async Task Check_in_tai_quay_khach_het_han_phai_xac_nhan()
    {
        if (NoDb) return;
        var (store, device) = await SeedDeviceAsync(serverDoor: false);
        var c = await AddMemberAsync(store, device.Id, "Đỗ Minh", "0944555666", 0, null); // hết buổi
        await using (var db = Fx.NewDb())
        {
            var ctl = PosPgFixture.As(new ZKTecoADMS.Api.Controllers.PosGymController(db, null!, Service(db, new FakeNotifier())), store);
            var res = await ctl.CheckIn(new(c));
            Assert.IsType<Microsoft.AspNetCore.Mvc.ConflictObjectResult>(res.Result);
            Assert.Equal("Gói đã hết buổi", Error(res));
            Assert.Equal(0, await db.PosGymVisits.CountAsync(v => v.CustomerId == c));

            var forced = Data(await ctl.CheckIn(new(c, Force: true)));
            Assert.Equal("OutOfSessions", forced.Status);
            Assert.False(forced.Denied);                    // lễ tân cho vào → đang tập
        }
    }

    static ZKTecoADMS.Api.Controllers.PosGymController Gym(ZKTecoDbContext db, Guid store) =>
        PosPgFixture.As(new ZKTecoADMS.Api.Controllers.PosGymController(db, null!, Service(db, new FakeNotifier())), store);

    [Fact]
    public async Task Bao_luu_khong_check_in_duoc_mo_bao_luu_cong_ngay_vao_han()
    {
        if (NoDb) return;
        var (store, device) = await SeedDeviceAsync(serverDoor: false);
        var expires = DateTime.UtcNow.AddDays(20);
        var c = await AddMemberAsync(store, device.Id, "Ngô Bảo", "0933111000", 10, expires);
        Guid balanceId;
        await using (var db = Fx.NewDb())
        {
            balanceId = (await db.PosCustomerSessionBalances.FirstAsync(b => b.CustomerId == c)).Id;
            var r = Data(await Gym(db, store).Freeze(balanceId, new(10, "Đi công tác")));
            Assert.Equal("Frozen", r.Status);
        }
        await using (var db = Fx.NewDb())
        {
            // Check-in tại quầy báo bảo lưu (chưa ghi lượt).
            var res = await Gym(db, store).CheckIn(new(c));
            Assert.Contains("bảo lưu", Error(res));
            var v = await Service(db, new FakeNotifier()).RecordPunchAsync(store, c, DateTime.UtcNow, device.Id, "933111000", "Device", "t");
            Assert.Equal("Frozen", v!.Status);
            Assert.Contains("bảo lưu", v.Note);
            Assert.False(v.SessionDeducted);
        }
        await using (var db = Fx.NewDb())
        {
            // Đã bảo lưu được 3 ngày → mở sớm: hạn cộng 3 ngày.
            var b = await db.PosCustomerSessionBalances.AsTracking().FirstAsync(x => x.Id == balanceId);
            b.FrozenAt = b.FrozenAt!.Value.AddDays(-3).AddHours(1);
            await db.SaveChangesAsync();
            var r = Data(await Gym(db, store).Unfreeze(balanceId));
            Assert.Equal("Active", r.Status);
            Assert.Equal(expires.AddDays(3), r.ExpiresAt!.Value, TimeSpan.FromSeconds(1));
        }
    }

    [Fact]
    public async Task Het_ngay_bao_luu_tu_mo_va_cong_du_ngay()
    {
        if (NoDb) return;
        var (store, device) = await SeedDeviceAsync(serverDoor: false);
        var expires = DateTime.UtcNow.AddDays(5);
        var c = await AddMemberAsync(store, device.Id, "Mai Chi", "0933222000", 10, expires);
        await using (var db = Fx.NewDb())
        {
            var b = await db.PosCustomerSessionBalances.AsTracking().FirstAsync(x => x.CustomerId == c);
            b.FrozenAt = DateTime.UtcNow.AddDays(-7);
            b.FrozenUntil = DateTime.UtcNow.AddHours(-1); // bảo lưu ~7 ngày, đã hết
            await db.SaveChangesAsync();
        }
        await using (var db = Fx.NewDb())
        {
            var v = await Service(db, new FakeNotifier()).RecordPunchAsync(store, c, DateTime.UtcNow, device.Id, "933222000", "Device", "t");
            Assert.Equal("Ok", v!.Status);
        }
        await using (var db = Fx.NewDb())
        {
            var b = await db.PosCustomerSessionBalances.FirstAsync(x => x.CustomerId == c);
            Assert.Null(b.FrozenAt);
            Assert.Equal(expires.AddDays(7), b.ExpiresAt!.Value, TimeSpan.FromSeconds(1));
        }
    }

    [Fact]
    public async Task The_sang_ngoai_khung_gio_khong_vao_duoc()
    {
        if (NoDb) return;
        var (store, device) = await SeedDeviceAsync(serverDoor: true);
        var c = await AddMemberAsync(store, device.Id, "Lâm Sáng", "0933333000", 10, null);
        await using (var db = Fx.NewDb())
        {
            var b = await db.PosCustomerSessionBalances.FirstAsync(x => x.CustomerId == c);
            Assert.Equal("05:00-16:00", Data(await Gym(db, store).SetAccessHours(b.Id, new(" 5h-16h "))).AccessHours);
            Assert.NotNull(Error(await Gym(db, store).SetAccessHours(b.Id, new("25:00-26:00"))));
        }
        var morning = new DateTime(2026, 10, 9, 1, 0, 0, DateTimeKind.Utc);  // 08:00 VN
        var evening = new DateTime(2026, 10, 10, 12, 0, 0, DateTimeKind.Utc); // 19:00 VN hôm sau
        await using (var db = Fx.NewDb())
        {
            var svc = Service(db, new FakeNotifier());
            Assert.Equal("Ok", (await svc.RecordPunchAsync(store, c, morning, device.Id, "933333000", "Device", "t"))!.Status);
            var late = await svc.RecordPunchAsync(store, c, evening, device.Id, "933333000", "Device", "t");
            Assert.Equal("OutOfHours", late!.Status);
            Assert.Contains("05:00-16:00", late.Note);
        }
        Assert.True(GymVisitRules.IsWithinHours("22:00-02:00", new DateTime(2026, 1, 1, 17, 30, 0))); // 00:30 VN
        Assert.False(GymVisitRules.IsWithinHours("22:00-02:00", new DateTime(2026, 1, 1, 5, 0, 0)));  // 12:00 VN
    }

    [Fact]
    public async Task Danh_sach_nhac_gia_han()
    {
        if (NoDb) return;
        var (store, device) = await SeedDeviceAsync(serverDoor: false);
        var soon = await AddMemberAsync(store, device.Id, "Sắp Hết", "0933444001", 10, DateTime.UtcNow.AddDays(3));
        var gone = await AddMemberAsync(store, device.Id, "Đã Hết", "0933444002", 4, DateTime.UtcNow.AddDays(-2));
        var fine = await AddMemberAsync(store, device.Id, "Còn Lâu", "0933444003", 10, DateTime.UtcNow.AddDays(60));
        var low = await AddMemberAsync(store, device.Id, "Còn Ít", "0933444004", 1, DateTime.UtcNow.AddDays(60));
        await using var db = Fx.NewDb();
        var list = Data(await Gym(db, store).Expiring(7));
        Assert.Contains(list, r => r.CustomerId == soon && r.Reason == "Còn 3 ngày");
        Assert.Contains(list, r => r.CustomerId == gone && r.Reason == "Đã hết hạn");
        Assert.Contains(list, r => r.CustomerId == low && r.Reason == "Còn 1 buổi");
        Assert.DoesNotContain(list, r => r.CustomerId == fine);
    }
}
