using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Báo cáo theo ngành: sổ khách lưu trú (giờ VN), thẻ tập / gói buổi sắp hết hạn (nhắc gia hạn).</summary>
[Collection("pos-pg")]
public class PosIndustryReportsTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    static JsonElement Json(IActionResult r)
    {
        var ok = Assert.IsType<OkObjectResult>(r);
        var data = ((AppResponse<object>)ok.Value!).Data!;
        return JsonSerializer.SerializeToElement(data, new JsonSerializerOptions(JsonSerializerDefaults.Web));
    }

    [Fact]
    public async Task So_khach_luu_tru_tra_gio_VN_va_dem_khach_thieu_giay_to()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        // Khách nhận phòng 21:30 ngày 10/10 giờ VN = 14:30 UTC.
        var checkInUtc = new DateTime(2026, 10, 10, 14, 30, 0);
        await using (var db = Fx.NewDb())
        {
            var area = new PosServiceArea { Id = Guid.NewGuid(), StoreId = store, Name = "Tầng 1" };
            var room = new PosServiceResource { Id = Guid.NewGuid(), StoreId = store, AreaId = area.Id, Code = "P101", Name = "Phòng 101" };
            var session = new PosResourceSession { Id = Guid.NewGuid(), StoreId = store, ResourceId = room.Id, StartedAt = checkInUtc };
            db.AddRange(area, room, session);
            db.PosStayGuests.AddRange(
                new PosStayGuest { Id = Guid.NewGuid(), StoreId = store, ResourceSessionId = session.Id, FullName = "Nguyễn Văn An",
                    IdNumber = "001090000001", DateOfBirth = new DateTime(1990, 5, 1), IsPrimary = true, CreatedAt = DateTime.UtcNow },
                new PosStayGuest { Id = Guid.NewGuid(), StoreId = store, ResourceSessionId = session.Id, FullName = "Trần Thị Bình",
                    CreatedAt = DateTime.UtcNow });
            await db.SaveChangesAsync();
        }

        await using var db2 = Fx.NewDb();
        var ctl = PosPgFixture.As(new PosStayGuestsController(db2), store);
        var data = Json(await ctl.Register(new DateTime(2026, 10, 10), new DateTime(2026, 10, 10)));
        Assert.Equal(2, data.GetProperty("total").GetInt32());
        Assert.Equal(1, data.GetProperty("missingIdCount").GetInt32());
        var first = data.GetProperty("items")[0];
        Assert.Equal(new DateTime(2026, 10, 10, 21, 30, 0), first.GetProperty("checkInAt").GetDateTime());
    }

    async Task<Guid> PackAsync(ZKTecoDbContext db, Guid store, string name, int total, int remaining, DateTime? expires,
        DateTime createdAt, bool frozen = false, bool customerDeleted = false)
    {
        var c = new PosCustomer { Id = Guid.NewGuid(), StoreId = store, CustomerCode = "KH" + Guid.NewGuid().ToString("N")[..6], Name = name, IsActive = true };
        if (customerDeleted) c.Deleted = DateTime.UtcNow;
        db.PosCustomers.Add(c);
        db.PosCustomerSessionBalances.Add(new PosCustomerSessionBalance
        {
            Id = Guid.NewGuid(), StoreId = store, CustomerId = c.Id, PackageName = "Gói " + total + " buổi",
            TotalSessions = total, RemainingSessions = remaining, ExpiresAt = expires, IsActive = true, CreatedAt = createdAt,
            FrozenAt = frozen ? DateTime.UtcNow.AddDays(-1) : null,
        });
        await Task.CompletedTask;
        return c.Id;
    }

    [Fact]
    public async Task The_sap_het_han_bo_the_bao_luu_khach_da_xoa_va_goi_het_buoi_lau_roi()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var now = DateTime.UtcNow;
        await using (var db = Fx.NewDb())
        {
            await PackAsync(db, store, "Sắp Hết Hạn", 12, 6, now.AddDays(3), now.AddDays(-20));
            await PackAsync(db, store, "Đang Bảo Lưu", 12, 6, now.AddDays(2), now.AddDays(-20), frozen: true);
            await PackAsync(db, store, "Khách Đã Xóa", 12, 6, now.AddDays(2), now.AddDays(-20), customerDeleted: true);
            await PackAsync(db, store, "Vừa Hết Buổi", 10, 0, null, now.AddDays(-5));
            await PackAsync(db, store, "Hết Buổi Năm Ngoái", 10, 0, null, now.AddDays(-400));
            await PackAsync(db, store, "Còn Một Buổi", 10, 1, null, now.AddDays(-5));
            await db.SaveChangesAsync();
        }

        await using var db2 = Fx.NewDb();
        var ctl = PosPgFixture.As(new PosSellIndustryController(db2, null!, null!, null!), store);
        var data = Json(await ctl.GetExpiringPacks());
        var names = data.GetProperty("items").EnumerateArray()
            .ToDictionary(x => x.GetProperty("customerName").GetString()!, x => x.GetProperty("status").GetString());
        Assert.Equal("Sắp hết hạn", names["Sắp Hết Hạn"]);
        Assert.Equal("Đã hết buổi", names["Vừa Hết Buổi"]);
        Assert.Equal("Sắp hết buổi", names["Còn Một Buổi"]);
        Assert.DoesNotContain("Đang Bảo Lưu", names.Keys);
        Assert.DoesNotContain("Khách Đã Xóa", names.Keys);
        Assert.DoesNotContain("Hết Buổi Năm Ngoái", names.Keys);
        Assert.Equal(1, data.GetProperty("usedUpCount").GetInt32());
        Assert.Equal(1, data.GetProperty("lowSessionsCount").GetInt32());
    }
}
