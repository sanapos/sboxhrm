using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Api.Middlewares;

/// <summary>
/// Chặn mọi API (trừ whitelist) khi license cửa hàng đã hết hạn hoặc cửa hàng bị khoá.
/// SuperAdmin vẫn truy cập được để gia hạn.
/// </summary>
public class StoreLicenseMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<StoreLicenseMiddleware> _logger;
    private readonly IMemoryCache _cache;

    private static readonly string[] BypassPrefixes =
    {
        "/health",
        "/api/auth/",
        "/api/maintenance/active",
        "/api/system-admin/",
        "/api/communications/public/",
        "/hubs/",
        "/iclock/",
    };

    public StoreLicenseMiddleware(
        RequestDelegate next,
        ILogger<StoreLicenseMiddleware> logger,
        IMemoryCache cache)
    {
        _next = next;
        _logger = logger;
        _cache = cache;
    }

    public async Task InvokeAsync(HttpContext ctx, IRepository<Store> storeRepository)
    {
        var path = ctx.Request.Path.Value ?? string.Empty;

        foreach (var prefix in BypassPrefixes)
        {
            if (path.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            {
                await _next(ctx);
                return;
            }
        }

        if (ctx.User?.Identity?.IsAuthenticated != true)
        {
            await _next(ctx);
            return;
        }

        if (ctx.User.IsInRole(nameof(Roles.SuperAdmin)))
        {
            await _next(ctx);
            return;
        }

        var storeIdClaim = ctx.User.FindFirst(ClaimTypeNames.StoreId)?.Value;
        if (string.IsNullOrEmpty(storeIdClaim) || !Guid.TryParse(storeIdClaim, out var storeId))
        {
            await _next(ctx);
            return;
        }

        // null = cho qua; ngược lại là (mã lỗi, thông báo) — hết hạn / ngừng hoạt động hoặc bị khoá.
        var block = await _cache.GetOrCreateAsync(StoreLicenseHelper.AccessCacheKey(storeId), async entry =>
        {
            entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromSeconds(60);
            entry.Size = 1;
            try
            {
                var store = await storeRepository.GetByIdAsync(storeId, cancellationToken: ctx.RequestAborted);
                if (store == null || !store.IsActive || StoreLicenseHelper.IsExpired(store))
                    return new StoreBlock(StoreLicenseHelper.ExpiredErrorCode, StoreLicenseHelper.ExpiredMessage);
                if (store.IsLocked)
                    return new StoreBlock(StoreLicenseHelper.LockedErrorCode, StoreLicenseHelper.LockedMessage(store.LockReason));
                return null;
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to evaluate store license for {StoreId}", storeId);
                return null;
            }
        });

        if (block != null)
        {
            ctx.Response.StatusCode = StatusCodes.Status403Forbidden;
            ctx.Response.ContentType = "application/json; charset=utf-8";
            ctx.Response.Headers["X-SBOX-Error-Code"] = block.Code;
            var body = new
            {
                isSuccess = false,
                message = block.Message,
                errors = new[] { block.Code }
            };
            await ctx.Response.WriteAsync(JsonSerializer.Serialize(body), ctx.RequestAborted);
            return;
        }

        await _next(ctx);
    }

    private sealed record StoreBlock(string Code, string Message);
}

public static class StoreLicenseMiddlewareExtensions
{
    public static IApplicationBuilder UseStoreLicenseCheck(this IApplicationBuilder app)
        => app.UseMiddleware<StoreLicenseMiddleware>();
}
