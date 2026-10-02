using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>Token FCM phải theo người đang đăng nhập trên máy — không gửi nhầm thông báo sang máy người khác.</summary>
public class DeviceTokenRegistryTests
{
    private static ServiceProvider Provider()
    {
        var services = new ServiceCollection();
        var name = Guid.NewGuid().ToString();
        // Giống production: mặc định NoTracking.
        services.AddDbContext<ZKTecoDbContext>(o => o
            .UseInMemoryDatabase(name)
            .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking));
        return services.BuildServiceProvider();
    }

    private static async Task<T> Scoped<T>(ServiceProvider sp, Func<ZKTecoDbContext, Task<T>> f)
    {
        using var scope = sp.CreateScope();
        return await f(scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>());
    }

    [Fact]
    public async Task Same_device_new_login_moves_token_to_new_user()
    {
        using var sp = Provider();
        var a = Guid.NewGuid();
        var b = Guid.NewGuid();
        await Scoped(sp, db => DeviceTokenRegistry.RegisterAsync(db, a, "tok-X", "android", null, null, "dev-1"));
        // A bị đánh dấu token hỏng trước đó → đăng nhập lại phải bật lại.
        await Scoped(sp, async db =>
        {
            var t = await db.UserDeviceTokens.AsTracking().SingleAsync();
            t.IsDisabled = true;
            return await db.SaveChangesAsync();
        });

        var prev = await Scoped(sp, db => DeviceTokenRegistry.RegisterAsync(db, b, "tok-X", "android", null, null, "dev-1"));

        Assert.Equal(a, prev);
        var row = await Scoped(sp, db => db.UserDeviceTokens.SingleAsync());
        Assert.Equal(b, row.UserId);      // trước đây vẫn là A → thông báo của A đổ về máy B
        Assert.False(row.IsDisabled);
    }

    [Fact]
    public async Task New_token_on_same_device_removes_old_token_of_previous_user()
    {
        using var sp = Provider();
        var a = Guid.NewGuid();
        var b = Guid.NewGuid();
        await Scoped(sp, db => DeviceTokenRegistry.RegisterAsync(db, a, "tok-old", "ios", null, null, "dev-1"));
        await Scoped(sp, db => DeviceTokenRegistry.RegisterAsync(db, a, "tok-other-phone", "ios", null, null, "dev-2"));

        await Scoped(sp, db => DeviceTokenRegistry.RegisterAsync(db, b, "tok-new", "ios", null, null, "dev-1"));

        var rows = await Scoped(sp, db => db.UserDeviceTokens.OrderBy(t => t.Token).ToListAsync());
        Assert.Equal(new[] { "tok-new", "tok-other-phone" }, rows.Select(r => r.Token));
        Assert.Equal(b, rows.Single(r => r.Token == "tok-new").UserId);
        Assert.Equal(a, rows.Single(r => r.Token == "tok-other-phone").UserId); // máy khác của A giữ nguyên
    }
}
