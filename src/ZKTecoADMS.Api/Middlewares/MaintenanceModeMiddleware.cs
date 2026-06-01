using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Middlewares;

/// <summary>
/// Trả 503 với JSON body khi đang trong cửa sổ bảo trì có BlockAccess=true.
/// Bypass cho:
///  - SuperAdmin (có thể tiếp tục thao tác để cập nhật / huỷ maintenance)
///  - Endpoint whitelist: /health, /api/auth/*, /api/system-admin/maintenance/*, /api/maintenance/active
/// Cache trạng thái 30s để giảm tải DB.
/// </summary>
public class MaintenanceModeMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<MaintenanceModeMiddleware> _logger;
    private readonly IMemoryCache _cache;
    private const string CacheKey = "__maintenance_active__";

    private static readonly string[] BypassPrefixes =
    {
        "/health",
        "/api/auth/",
        "/api/maintenance/active",
        "/api/system-admin/maintenance",
        "/api/communications/public/",
        "/hubs/",
    };

    public MaintenanceModeMiddleware(RequestDelegate next, ILogger<MaintenanceModeMiddleware> logger, IMemoryCache cache)
    {
        _next = next;
        _logger = logger;
        _cache = cache;
    }

    public async Task InvokeAsync(HttpContext ctx, IMaintenanceService svc)
    {
        var path = ctx.Request.Path.Value ?? string.Empty;

        // Bypass whitelist
        foreach (var p in BypassPrefixes)
        {
            if (path.StartsWith(p, StringComparison.OrdinalIgnoreCase))
            {
                await _next(ctx);
                return;
            }
        }

        // Bypass SuperAdmin
        if (ctx.User?.Identity?.IsAuthenticated == true && ctx.User.IsInRole(nameof(Roles.SuperAdmin)))
        {
            await _next(ctx);
            return;
        }

        var active = await _cache.GetOrCreateAsync(CacheKey, async entry =>
        {
            entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromSeconds(30);
            entry.Size = 1;
            try { return await svc.GetActiveAsync(ctx.RequestAborted); }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to load maintenance state");
                return null;
            }
        });

        if (active is { InMaintenance: true, BlockAccess: true })
        {
            ctx.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
            ctx.Response.ContentType = "application/json; charset=utf-8";
            ctx.Response.Headers["Retry-After"] = "120";
            var body = new
            {
                isSuccess = false,
                message = "Hệ thống đang bảo trì, vui lòng thử lại sau.",
                data = new
                {
                    inMaintenance = true,
                    title = active.Title,
                    message = active.Message,
                    startAt = active.StartAt,
                    endAt = active.EndAt
                }
            };
            await ctx.Response.WriteAsync(JsonSerializer.Serialize(body));
            return;
        }

        await _next(ctx);
    }
}

public static class MaintenanceModeMiddlewareExtensions
{
    public static IApplicationBuilder UseMaintenanceMode(this IApplicationBuilder app)
        => app.UseMiddleware<MaintenanceModeMiddleware>();
}
