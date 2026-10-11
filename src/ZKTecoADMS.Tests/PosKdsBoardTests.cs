using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>KDS: vé không thao tác quá 60 giờ tự rời bảng bếp; danh sách vé đã ra món gần đây (gọi lại).</summary>
public class PosKdsBoardTests
{
    static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

    readonly Guid _store = Guid.NewGuid();
    readonly ServiceProvider _sp;
    readonly ZKTecoDbContext _db;
    readonly PosProduct _product;

    public PosKdsBoardTests()
    {
        var services = new ServiceCollection();
        services.AddDbContext<ZKTecoDbContext>(o => o.UseInMemoryDatabase(Guid.NewGuid().ToString())
            .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking));
        _sp = services.BuildServiceProvider();
        _db = _sp.CreateScope().ServiceProvider.GetRequiredService<ZKTecoDbContext>();
        var cat = new PosProductCategory { Id = Guid.NewGuid(), StoreId = _store, Name = "Món chính", IsActive = true };
        _product = new PosProduct { Id = Guid.NewGuid(), StoreId = _store, Name = "Bún chả", CategoryId = cat.Id, IsActive = true };
        _db.PosProductCategories.Add(cat);
        _db.PosProducts.Add(_product);
        _db.SaveChanges();
    }

    PosKdsController Ctl() => new(_db, null!)
    {
        ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                RequestServices = _sp,
                User = new ClaimsPrincipal(new ClaimsIdentity([
                    new Claim("id", Guid.NewGuid().ToString()),
                    new Claim(ClaimTypes.Role, "Admin"),
                    new Claim(ClaimTypes.Email, "bep@test"),
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

    /// Vé bếp: đơn nháp + 1 dòng đã báo bếp lúc [sentHoursAgo], thao tác cuối [touchedHoursAgo] (null = chưa).
    string AddTicket(string no, double sentHoursAgo, double? touchedHoursAgo = null, bool done = false)
    {
        var now = DateTime.UtcNow;
        var order = new PosSaleOrder
        {
            Id = Guid.NewGuid(), StoreId = _store, OrderNo = no, Status = PosSaleOrderStatus.Draft, IsActive = true,
        };
        _db.PosSaleOrders.Add(order);
        _db.PosSaleOrderLines.Add(new PosSaleOrderLine
        {
            Id = Guid.NewGuid(), StoreId = _store, SaleOrderId = order.Id, ProductId = _product.Id,
            ProductName = _product.Name, Qty = 2, KitchenSentQty = 2, KitchenDoneQty = done ? 2 : 0,
            KitchenPrepStatus = done ? "done" : "queued",
            KitchenSentAt = now.AddHours(-sentHoursAgo),
            CreatedAt = now.AddHours(-sentHoursAgo),
            UpdatedAt = touchedHoursAgo is double t ? now.AddHours(-t) : null,
            IsActive = true,
        });
        _db.SaveChanges();
        return no;
    }

    static List<string> OrderNos(JsonElement data, string arr) =>
        data.GetProperty(arr).EnumerateArray().Select(t => t.GetProperty("orderNo").GetString()!).ToList();

    [Fact]
    public async Task Tickets_drop_orders_idle_over_60_hours()
    {
        AddTicket("FRESH", sentHoursAgo: 1);
        AddTicket("STALE", sentHoursAgo: 70);
        AddTicket("TOUCHED", sentHoursAgo: 70, touchedHoursAgo: 2);

        var nos = OrderNos(Data((await Ctl().Tickets()).Result), "tickets");

        Assert.Contains("FRESH", nos);
        Assert.Contains("TOUCHED", nos);
        Assert.DoesNotContain("STALE", nos);
    }

    [Fact]
    public async Task Tickets_idle_filter_can_be_disabled()
    {
        AddTicket("STALE", sentHoursAgo: 70);

        var nos = OrderNos(Data((await Ctl().Tickets(idleHours: 0)).Result), "tickets");

        Assert.Contains("STALE", nos);
    }

    [Fact]
    public async Task RecentDone_lists_only_orders_finished_within_window_newest_first()
    {
        AddTicket("OLDER", sentHoursAgo: 3, touchedHoursAgo: 2, done: true);
        AddTicket("NEWER", sentHoursAgo: 1, touchedHoursAgo: 0.2, done: true);
        AddTicket("LONG_AGO", sentHoursAgo: 12, touchedHoursAgo: 10, done: true);
        AddTicket("COOKING", sentHoursAgo: 1, touchedHoursAgo: 0.1);

        var data = Data((await Ctl().RecentDone()).Result);
        var nos = OrderNos(data, "orders");

        Assert.Equal(["NEWER", "OLDER"], nos);
        var item = data.GetProperty("orders")[0].GetProperty("items")[0];
        Assert.Equal("Bún chả", item.GetProperty("productName").GetString());
        Assert.Equal(2m, item.GetProperty("qty").GetDecimal());
    }
}
