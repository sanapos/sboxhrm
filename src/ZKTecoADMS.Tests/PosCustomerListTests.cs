using System.Security.Claims;
using System.Text.Encodings.Web;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>Danh sách khách POS: sinh nhật, lâu không mua, sắp xếp máy chủ, trùng SĐT, ngừng hoạt động.</summary>
public class PosCustomerListTests
{
    static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    readonly Guid _store = Guid.NewGuid();
    readonly ServiceProvider _sp;
    readonly ZKTecoDbContext _db;
    readonly DateTime _today = VnTimeHelper.NowVn().Date;

    public PosCustomerListTests()
    {
        var services = new ServiceCollection();
        services.AddDbContext<ZKTecoDbContext>(o => o.UseInMemoryDatabase(Guid.NewGuid().ToString())
            .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking));
        _sp = services.BuildServiceProvider();
        _db = _sp.CreateScope().ServiceProvider.GetRequiredService<ZKTecoDbContext>();
    }

    PosCustomersController Ctl() => new(_db)
    {
        ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                RequestServices = _sp,
                User = new ClaimsPrincipal(new ClaimsIdentity([
                    new Claim("id", Guid.NewGuid().ToString()),
                    new Claim(ClaimTypes.Role, "Admin"),
                    new Claim(ClaimTypeNames.StoreId, _store.ToString()),
                ], "test")),
            },
        },
    };

    static JsonElement Data(object? result)
    {
        var obj = result is ObjectResult o ? o.Value : result;
        var root = JsonDocument.Parse(JsonSerializer.Serialize(obj, Json)).RootElement;
        return root;
    }

    PosCustomer Cust(string code, string? phone = null, DateTime? birthday = null, bool active = true) => new()
    {
        Id = Guid.NewGuid(), StoreId = _store, CustomerCode = code, Name = "Khách " + code, Phone = phone,
        Birthday = birthday, IsActive = active, Province = "Hà Nội", Note = "VIP",
    };

    void Order(PosCustomer c, int daysAgo) => _db.PosSaleOrders.Add(new PosSaleOrder
    {
        Id = Guid.NewGuid(), StoreId = _store, CustomerId = c.Id, OrderNo = Guid.NewGuid().ToString()[..6],
        Status = PosSaleOrderStatus.Completed, Total = 100_000, IsActive = true, SaleDate = DateTime.UtcNow.AddDays(-daysAgo),
    });

    [Fact]
    public async Task Loc_sinh_nhat_lau_khong_mua_va_sap_xep()
    {
        var bdToday = Cust("KH1", birthday: new DateTime(1990, _today.Month, _today.Day));
        var bdIn3 = Cust("KH2", birthday: new DateTime(1991, _today.AddDays(3).Month, _today.AddDays(3).Day));
        var noBd = Cust("KH3");
        var inactive = Cust("KH4", active: false);
        _db.PosCustomers.AddRange(bdToday, bdIn3, noBd, inactive);
        Order(bdToday, 2);    // mua gần đây
        Order(bdIn3, 120);    // lâu không mua
        await _db.SaveChangesAsync();

        static List<string> Codes(JsonElement d) =>
            d.GetProperty("data").GetProperty("items").EnumerateArray().Select(i => i.GetProperty("customerCode").GetString()!).ToList();

        var today = Data((await Ctl().List(null, null, null, null, null, null, null, birthday: "today")).Result);
        Assert.Equal(["KH1"], Codes(today));
        var week = Data((await Ctl().List(null, null, null, null, null, null, null, birthday: "week")).Result);
        Assert.Equal(["KH1", "KH2"], Codes(week).OrderBy(x => x).ToList());

        var old = Data((await Ctl().List(null, null, null, null, null, null, null, inactiveDays: 90)).Result);
        Assert.Equal(["KH2"], Codes(old));   // KH3 chưa mua lần nào → không phải «khách cũ»

        var bySoonest = Data((await Ctl().List(null, null, null, null, null, null, null, sort: "birthday")).Result);
        Assert.Equal(["KH1", "KH2", "KH3"], Codes(bySoonest));

        var recent = Data((await Ctl().List(null, null, null, null, null, null, null, sort: "recent")).Result);
        var first = recent.GetProperty("data").GetProperty("items")[0];
        Assert.Equal("KH1", first.GetProperty("customerCode").GetString());
        Assert.Equal(1, first.GetProperty("orderCount").GetInt32());
        Assert.NotEqual(JsonValueKind.Null, first.GetProperty("lastPurchaseAt").ValueKind);
        // Danh sách đủ trường để mở form sửa (không làm mất tỉnh / ghi chú khi lưu).
        Assert.Equal("Hà Nội", first.GetProperty("province").GetString());
        Assert.Equal("VIP", first.GetProperty("note").GetString());

        var inactiveOnly = Data((await Ctl().List(null, null, null, null, null, null, null, status: "inactive")).Result);
        Assert.Equal(["KH4"], Codes(inactiveOnly));
    }

    [Fact]
    public async Task Chan_trung_so_dien_thoai_va_ngung_hoat_dong()
    {
        var a = Cust("KH1", phone: "0912 345 678");
        _db.PosCustomers.Add(a);
        await _db.SaveChangesAsync();

        var dto = new PosCustomersController.CustomerSaveDto("Khách mới", "+84912345678", null, null, null, null, null, null, null, null, null, null, null);
        var dup = Data((await Ctl().Create(dto)).Result);
        Assert.False(dup.GetProperty("isSuccess").GetBoolean());
        Assert.Contains("KH1", dup.GetProperty("message").GetString());

        // Ngừng hoạt động khách cũ → số này dùng được cho khách mới; kích hoạt lại khách cũ thì bị chặn.
        Assert.True(Data((await Ctl().Deactivate(a.Id)).Result).GetProperty("isSuccess").GetBoolean());
        Assert.True(Data((await Ctl().Create(dto)).Result).GetProperty("isSuccess").GetBoolean());
        Assert.False(Data((await Ctl().Activate(a.Id)).Result).GetProperty("isSuccess").GetBoolean());
    }

    [Theory]
    [InlineData("0912345678", "912345678")]
    [InlineData("+84 912 345 678", "912345678")]
    [InlineData("84912345678", "912345678")]
    public void Chuan_hoa_so_dien_thoai(string raw, string expected) =>
        Assert.Equal(expected, PosCustomersController.NormalizePhone(raw));
}
