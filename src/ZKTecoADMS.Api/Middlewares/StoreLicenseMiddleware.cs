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
/// Chặn mọi API (trừ whitelist) khi license cửa hàng đã hết hạn.
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

        var cacheKey = $"__store_license_expired__{storeId}";
        var isExpired = await _cache.GetOrCreateAsync(cacheKey, async entry =>
        {
            entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromSeconds(60);
            entry.Size = 1;
            try
            {
                var store = await storeRepository.GetByIdAsync(storeId, cancellationToken: ctx.RequestAborted);
                if (store == null || !store.IsActive)
                    return true;
                return StoreLicenseHelper.IsExpired(store);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to evaluate store license for {StoreId}", storeId);
                return false;
            }
        });

        if (isExpired)
        {
            ctx.Response.StatusCode = StatusCodes.Status403Forbidden;
            ctx.Response.ContentType = "application/json; charset=utf-8";
            ctx.Response.Headers["X-SBOX-Error-Code"] = StoreLicenseHelper.ExpiredErrorCode;
            var body = new
            {
                isSuccess = false,
                message = StoreLicenseHelper.ExpiredMessage,
                errors = new[] { StoreLicenseHelper.ExpiredErrorCode }
            };
            await ctx.Response.WriteAsync(JsonSerializer.Serialize(body), ctx.RequestAborted);
            return;
        }

        await _next(ctx);
    }
}

public static class StoreLicenseMiddlewareExtensions
{
    public static IApplicationBuilder UseStoreLicenseCheck(this IApplicationBuilder app)
        => app.UseMiddleware<StoreLicenseMiddleware>();
}
