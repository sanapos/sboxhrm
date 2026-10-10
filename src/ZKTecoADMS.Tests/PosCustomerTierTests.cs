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
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;
using Tier = ZKTecoADMS.Api.Controllers.PosCustomerTiers.Tier;

namespace ZKTecoADMS.Tests;

/// <summary>Hạng thành viên theo tổng mua: cấu hình, hạng của khách, lọc danh sách, đếm khách mỗi hạng.</summary>
public class PosCustomerTierTests
{
    static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    readonly Guid _store = Guid.NewGuid();
    readonly ServiceProvider _sp;
    readonly ZKTecoDbContext _db;

    public PosCustomerTierTests()
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
        return JsonDocument.Parse(JsonSerializer.Serialize(obj, Json)).RootElement.GetProperty("data");
    }

    void Cust(string code, decimal spend) => _db.PosCustomers.Add(new PosCustomer
    {
        Id = Guid.NewGuid(), StoreId = _store, CustomerCode = code, Name = "Khách " + code, IsActive = true, TotalPurchase = spend,
    });

    [Fact]
    public void Hang_theo_tong_mua_va_cau_hinh_hong()
    {
        var tiers = PosCustomerTiers.Normalize([new Tier(" Vàng ", 10_000_000), new Tier("Bạc", 2_000_000), new Tier("", 1), null]);
        Assert.Equal(["Bạc", "Vàng"], tiers.Select(t => t.Name).ToArray());
        Assert.Null(PosCustomerTiers.Resolve(tiers, 1_999_999));
        Assert.Equal("Bạc", PosCustomerTiers.Resolve(tiers, 2_000_000)!.Name);
        Assert.Equal("Vàng", PosCustomerTiers.Resolve(tiers, 50_000_000)!.Name);
        Assert.Empty(PosCustomerTiers.Parse("{không phải json"));
        Assert.NotNull(PosCustomerTiers.Validate([new Tier("A", 1), new Tier("a", 2)]));
        Assert.NotNull(PosCustomerTiers.Validate([new Tier("A", 1), new Tier("B", 1)]));
    }

    [Fact]
    public async Task Luu_hang_loc_danh_sach_va_dem_khach()
    {
        Cust("KH1", 500_000);
        Cust("KH2", 3_000_000);
        Cust("KH3", 12_000_000);
        Cust("KH4", 10_000_000);
        await _db.SaveChangesAsync();

        var bad = await Ctl().SaveTiers(new([new Tier("Bạc", 2_000_000), new Tier("bạc", 5_000_000)]));
        Assert.IsType<BadRequestObjectResult>(bad.Result);

        var saved = Data((await Ctl().SaveTiers(new([new Tier("Vàng", 10_000_000, "#F59E0B", "Giảm 5% sinh nhật"), new Tier("Bạc", 2_000_000)]))).Result);
        var tiers = saved.GetProperty("tiers").EnumerateArray().ToList();
        Assert.Equal(["Bạc", "Vàng"], tiers.Select(t => t.GetProperty("name").GetString()!).ToArray());
        Assert.Equal([1, 2], tiers.Select(t => t.GetProperty("customerCount").GetInt32()).ToArray());
        Assert.Equal(1, saved.GetProperty("noTierCount").GetInt32());
        Assert.Equal("Giảm 5% sinh nhật", tiers[1].GetProperty("benefit").GetString());

        static string[] Codes(JsonElement d) => d.GetProperty("items").EnumerateArray()
            .Select(i => i.GetProperty("customerCode").GetString()!).OrderBy(x => x).ToArray();
        var gold = Data((await Ctl().List(null, null, null, null, null, null, null, tier: "vàng")).Result);
        Assert.Equal(["KH3", "KH4"], Codes(gold));
        Assert.All(gold.GetProperty("items").EnumerateArray(), i => Assert.Equal("Vàng", i.GetProperty("tier").GetString()));
        Assert.Equal(["KH2"], Codes(Data((await Ctl().List(null, null, null, null, null, null, null, tier: "Bạc")).Result)));
        var none = Data((await Ctl().List(null, null, null, null, null, null, null, tier: "none")).Result);
        Assert.Equal(["KH1"], Codes(none));
        Assert.Equal(JsonValueKind.Null, none.GetProperty("items")[0].GetProperty("tier").ValueKind);

        // Xóa hết hạng → không còn hạng nào, lọc theo hạng bị bỏ qua.
        await Ctl().SaveTiers(new([]));
        Assert.Null(await _db.PosStoreSellSettings.Select(s => s.LoyaltyTiersJson).FirstAsync());
        Assert.Equal(4, Data((await Ctl().List(null, null, null, null, null, null, null, tier: "Vàng")).Result).GetProperty("total").GetInt32());
    }
}
