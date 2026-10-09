using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Api.Middlewares;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>
/// MemoryCache của API có SizeLimit (DependencyInjectionExtensions) — mọi entry phải khai báo Size,
/// thiếu là InvalidOperationException → lỗi 500 trên MỌI request đi qua middleware.
/// </summary>
[Collection("pos-pg")]
public class SizeLimitedCacheTests(PosPgFixture fx)
{
    static MemoryCache ApiLikeCache() => new(new MemoryCacheOptions { SizeLimit = 10000 });

    [Fact]
    public async Task StorePackageModuleMiddleware_WorksWithSizeLimitedCache()
    {
        if (fx.ConnectionString == null) return;
        var store = await fx.NewStoreAsync();
        var http = new DefaultHttpContext
        {
            User = new ClaimsPrincipal(new ClaimsIdentity(
            [
                new Claim("storeId", store.ToString()),
                new Claim(ClaimTypes.Role, "Manager"),
            ], "test")),
        };
        http.Request.Path = "/api/employees";
        var mw = new StorePackageModuleMiddleware(_ => Task.CompletedTask,
            NullLogger<StorePackageModuleMiddleware>.Instance);
        await using var db = fx.NewDb();
        using var cache = ApiLikeCache();
        await mw.InvokeAsync(http, db, cache); // trước khi sửa: «Cache entry must specify a value for Size»
        await mw.InvokeAsync(http, db, cache); // lần 2 đọc từ cache
    }

    [Fact]
    public async Task ModulePermissionService_WorksWithSizeLimitedCache()
    {
        if (fx.ConnectionString == null) return;
        var store = await fx.NewStoreAsync();
        await using var db = fx.NewDb();
        using var cache = ApiLikeCache();
        var svc = new ModulePermissionService(db, cache);
        await svc.GetEffectivePermissionsAsync(Guid.NewGuid(), "Staff", store);
        var svc2 = new ModulePermissionService(db, cache);
        await svc2.GetEffectivePermissionsAsync(Guid.NewGuid(), "Staff", store);
    }
}
