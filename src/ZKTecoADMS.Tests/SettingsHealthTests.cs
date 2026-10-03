using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>Tình trạng thiết lập: chưa cấu hình / cần chú ý / xong.</summary>
public class SettingsHealthTests
{
    [Fact]
    public void Status_rules()
    {
        Assert.Equal("todo", SettingsHealthController.Shift(0).Status);
        Assert.Equal("ok", SettingsHealthController.Shift(3).Status);
        Assert.Equal("todo", SettingsHealthController.Holiday(0, 0, 2026, 5).Status);
        Assert.Equal("warn", SettingsHealthController.Holiday(8, 0, 2026, 12).Status);     // cuối năm chưa có lịch lễ năm sau
        Assert.Equal("ok", SettingsHealthController.Holiday(8, 0, 2026, 6).Status);
        Assert.Equal("todo", SettingsHealthController.Holiday(4, 0, 2026, 6).Status);      // quá ít → còn thiếu ngày lễ chuẩn
        Assert.Equal("warn", SettingsHealthController.Devices(3, 1).Status);
        Assert.Equal("info", SettingsHealthController.Devices(0, 0).Status);
        Assert.Equal("todo", SettingsHealthController.Payment(0, false).Status);
        Assert.Equal("warn", SettingsHealthController.Payment(2, false).Status);
        Assert.Equal("ok", SettingsHealthController.Payment(1, true).Status);
    }

    [Fact]
    public async Task Endpoint_reports_store_items()
    {
        var services = new ServiceCollection();
        services.AddDbContext<ZKTecoDbContext>(o => o.UseInMemoryDatabase(Guid.NewGuid().ToString())
            .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking));
        var sp = services.BuildServiceProvider();
        var db = sp.CreateScope().ServiceProvider.GetRequiredService<ZKTecoDbContext>();
        var store = Guid.NewGuid();
        db.Add(new Device { Id = Guid.NewGuid(), StoreId = store, LastOnline = DateTime.UtcNow.AddHours(-2) });
        db.Add(new Device { Id = Guid.NewGuid(), StoreId = store, LastOnline = DateTime.UtcNow });
        db.Add(new Holiday { Id = Guid.NewGuid(), StoreId = null, Name = "Tết Dương lịch", Date = new DateTime(2026, 1, 1), IsRecurring = true });
        await db.SaveChangesAsync();
        var ctl = new SettingsHealthController(db)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    RequestServices = sp,
                    User = new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypeNames.StoreId, store.ToString())], "t")),
                },
            },
        };
        var ok = Assert.IsType<OkObjectResult>((await ctl.Get()).Result);
        var items = ((AppResponse<List<SettingsHealthController.HealthItem>>)ok.Value!).Data!.ToDictionary(i => i.Key);
        Assert.Equal("todo", items["shift"].Status);
        Assert.Equal("todo", items["holiday"].Status); // ngày lễ chung (StoreId null) không tính lương → không tính
        Assert.Equal("1/2 máy mất kết nối", items["device"].Text);
        Assert.Equal("todo", items["payment"].Status);
    }
}
