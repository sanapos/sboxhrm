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
}
