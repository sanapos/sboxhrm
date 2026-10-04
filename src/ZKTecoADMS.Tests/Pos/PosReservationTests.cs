using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>
/// Đặt bàn giữ chỗ (nhà hàng): DB lưu ReservedAt = lúc bấm đặt, ReservedUntil = giờ khách đến.
/// Lịch theo ngày phải xếp theo giờ khách đến và trả giờ đến làm mốc chính.
/// </summary>
[Collection("pos-pg")]
public class PosReservationTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    [Fact]
    public async Task Dat_ban_ngay_mai_khong_hien_hom_nay_va_tra_gio_khach_den()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var vnToday = DateTime.UtcNow.AddHours(7).Date;
        // Khách đến 19:00 ngày mai (giờ VN), bấm đặt lúc này.
        var arrivalUtc = DateTime.SpecifyKind(vnToday.AddDays(1).AddHours(19 - 7), DateTimeKind.Utc);
        Guid resId;
        await using (var db = Fx.NewDb())
        {
            var area = new PosServiceArea { Id = Guid.NewGuid(), StoreId = store, Name = "Tầng 1", IsActive = true };
            var res = new PosServiceResource { Id = Guid.NewGuid(), StoreId = store, AreaId = area.Id, Code = "B01", Name = "Bàn 1", IsActive = true };
            db.PosServiceAreas.Add(area);
            db.PosServiceResources.Add(res);
            db.PosResourceReservations.Add(new PosResourceReservation
            {
                Id = Guid.NewGuid(), StoreId = store, ResourceId = res.Id, CustomerName = "Cô Hoa", GuestCount = 2,
                ReservedAt = DateTime.UtcNow, ReservedUntil = arrivalUtc, Status = PosResourceReservationStatus.Booked, IsActive = true,
            });
            await db.SaveChangesAsync();
            resId = res.Id;
        }

        await using var db2 = Fx.NewDb();
        var ctl = PosPgFixture.As(new PosSellIndustryController(db2, null!, null!, null!), store);
        var today = Data(await ctl.ListReservations(day: vnToday));
        Assert.Empty(today);

        var tomorrow = Data(await ctl.ListReservations(day: vnToday.AddDays(1)));
        var b = Assert.Single(tomorrow);
        Assert.Equal(arrivalUtc, DateTime.SpecifyKind(b.ReservedAt, DateTimeKind.Utc), TimeSpan.FromSeconds(1));
        Assert.Null(b.ReservedUntil);
        Assert.Equal(resId, b.ResourceId);

        // Dòng tổng theo ngày cũng tính theo ngày khách đến.
        var pipe = Data(await ctl.ReservationPipeline(DateTime.SpecifyKind(vnToday, DateTimeKind.Utc),
            DateTime.SpecifyKind(vnToday.AddDays(1), DateTimeKind.Utc)));
        var days = ((System.Collections.IEnumerable)pipe.GetType().GetProperty("days")!.GetValue(pipe)!).Cast<object>().ToList();
        int booked(object d) => (int)d.GetType().GetProperty("Booked")!.GetValue(d)!;
        Assert.Equal(0, booked(days[0]));
        Assert.Equal(1, booked(days[1]));
    }

    [Fact]
    public async Task Lich_luc_1h_sang_thuoc_dung_ngay_VN()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var vnToday = DateTime.UtcNow.AddHours(7).Date;
        // 01:30 sáng mai (giờ VN) = 18:30 UTC hôm nay.
        var arrivalUtc = DateTime.SpecifyKind(vnToday.AddDays(1).AddHours(1.5 - 7), DateTimeKind.Utc);
        await using (var db = Fx.NewDb())
        {
            var area = new PosServiceArea { Id = Guid.NewGuid(), StoreId = store, Name = "Tầng 1", IsActive = true };
            var res = new PosServiceResource { Id = Guid.NewGuid(), StoreId = store, AreaId = area.Id, Code = "P1", Name = "Phòng 1", IsActive = true };
            db.PosServiceAreas.Add(area);
            db.PosServiceResources.Add(res);
            db.PosResourceReservations.Add(new PosResourceReservation
            {
                Id = Guid.NewGuid(), StoreId = store, ResourceId = res.Id, CustomerName = "Khách khuya",
                ReservedAt = arrivalUtc, ReservedUntil = arrivalUtc.AddHours(2), DurationMinutes = 120,
                Status = PosResourceReservationStatus.Booked, IsActive = true,
            });
            await db.SaveChangesAsync();
        }
        await using var db2 = Fx.NewDb();
        var ctl = PosPgFixture.As(new PosSellIndustryController(db2, null!, null!, null!), store);
        // App gửi ngày lịch dưới dạng 00:00 UTC.
        Assert.Empty(Data(await ctl.ListReservations(day: DateTime.SpecifyKind(vnToday, DateTimeKind.Utc))));
        Assert.Single(Data(await ctl.ListReservations(day: DateTime.SpecifyKind(vnToday.AddDays(1), DateTimeKind.Utc))));
    }

    static PosResourceReservation Hold(DateTime bookedAtUtc, DateTime arrivalUtc) => new()
    {
        Id = Guid.NewGuid(), CustomerName = "K", ReservedAt = bookedAtUtc, ReservedUntil = arrivalUtc,
        Status = PosResourceReservationStatus.Booked,
    };

    [Fact]
    public void Khach_vang_lai_ngoai_khung_giu_khong_lam_mat_lich_dat()
    {
        var now = DateTime.UtcNow;
        var b = Hold(now, now.AddHours(6)); // đặt bàn 6 tiếng nữa
        // Mở bàn cho khách vãng lai bây giờ → KHÔNG được coi là khách đặt đã đến (trước đây xóa mất lịch).
        Assert.False(PosSellIndustryController.ReservationConflictsWithLiveSession(b, now, now));
        // Mở bàn trong khung giữ (30′ trước giờ đến) → đúng là khách đặt tới.
        Assert.True(PosSellIndustryController.ReservationConflictsWithLiveSession(b, now.AddHours(5.5), now.AddHours(5.5)));
    }

    [Fact]
    public void So_do_ban_chi_hien_lich_giu_cho_trong_ngay()
    {
        var now = DateTime.UtcNow;
        var tomorrow = DateTime.SpecifyKind(now.AddHours(7).Date.AddDays(1).AddHours(19 - 7), DateTimeKind.Utc);
        Assert.Null(PosSellIndustryController.PickFloorBooking([Hold(now, tomorrow)], now));
        var soon = Hold(now, now.AddMinutes(30));
        Assert.Same(soon, PosSellIndustryController.PickFloorBooking([Hold(now, tomorrow), soon], now));
    }

    [Fact]
    public async Task Mot_ban_nhan_nhieu_lich_khac_gio_nhung_chan_lich_sat_gio()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        Guid resId;
        await using (var db = Fx.NewDb())
        {
            var area = new PosServiceArea { Id = Guid.NewGuid(), StoreId = store, Name = "T1", IsActive = true };
            var res = new PosServiceResource { Id = Guid.NewGuid(), StoreId = store, AreaId = area.Id, Code = "B1", Name = "Bàn 1", IsActive = true };
            db.PosServiceAreas.Add(area); db.PosServiceResources.Add(res);
            await db.SaveChangesAsync();
            resId = res.Id;
        }
        var day = DateTime.UtcNow.AddHours(7).Date.AddDays(2);
        DateTime Vn(int h) => DateTime.SpecifyKind(day.AddHours(h - 7), DateTimeKind.Utc);
        async Task<string?> Book(int hour)
        {
            await using var db = Fx.NewDb();
            var ctl = PosPgFixture.As(new PosSellIndustryController(db, null!, null!, null!), store);
            return Error(await ctl.CreateReservation(new PosSellIndustryController.CreateReservationDto(resId, $"Khách {hour}h", ReservedUntil: Vn(hour))));
        }
        Assert.Null(await Book(11));      // trưa
        Assert.Null(await Book(19));      // tối cùng bàn — trước đây bị chặn «Bàn đã có đặt trước»
        Assert.NotNull(await Book(20));   // sát lịch 19h → chặn
    }
}
