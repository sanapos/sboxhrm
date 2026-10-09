using Microsoft.AspNetCore.Mvc.Filters;

namespace ZKTecoADMS.Api.Controllers.Filters;

/// <summary>
/// Chặn tham số phân trang bất thường trên mọi API: pageSize/limit/take tối đa <see cref="MaxPageSize"/>
/// (không để ai kéo cả bảng lên RAM); page tối đa 1.000.000 (tránh tràn số khi nhân với pageSize).
/// Controller tự giới hạn chặt hơn thì vẫn giữ nguyên.
/// </summary>
public class PagingGuardFilter(ILogger<PagingGuardFilter> logger) : IActionFilter
{
    public const int MaxPageSize = 5000;
    const int MaxPage = 1_000_000;

    static readonly HashSet<string> SizeNames = new(StringComparer.OrdinalIgnoreCase) { "pageSize", "limit", "take", "top" };

    public void OnActionExecuting(ActionExecutingContext context)
    {
        foreach (var key in context.ActionArguments.Keys.ToList())
        {
            if (context.ActionArguments[key] is { } obj && obj is not int && obj.GetType() is { IsClass: true } t && t != typeof(string))
            {
                ClampObject(obj, t, context);
                continue;
            }
            if (context.ActionArguments[key] is not int v) continue;
            if (SizeNames.Contains(key))
            {
                if (v > MaxPageSize)
                {
                    logger.LogWarning("{Key}={Value} vượt giới hạn, hạ xuống {Max} ({Path})", key, v, MaxPageSize, context.HttpContext.Request.Path);
                    context.ActionArguments[key] = MaxPageSize;
                }
            }
            else if (key.Equals("page", StringComparison.OrdinalIgnoreCase) || key.Equals("pageNumber", StringComparison.OrdinalIgnoreCase))
            {
                if (v > MaxPage) context.ActionArguments[key] = MaxPage;
            }
        }
    }

    /// <summary>Query / body dạng DTO ([FromQuery] GetXxxQuery { PageSize }) — cùng giới hạn.</summary>
    void ClampObject(object obj, Type t, ActionExecutingContext context)
    {
        foreach (var name in SizeNames)
        {
            var prop = t.GetProperty(name, System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.IgnoreCase);
            if (prop is not { CanRead: true, CanWrite: true } || prop.PropertyType != typeof(int) || prop.GetIndexParameters().Length > 0) continue;
            if (prop.GetValue(obj) is int v && v > MaxPageSize)
            {
                logger.LogWarning("{Key}={Value} vượt giới hạn, hạ xuống {Max} ({Path})", name, v, MaxPageSize, context.HttpContext.Request.Path);
                prop.SetValue(obj, MaxPageSize);
            }
        }
    }

    public void OnActionExecuted(ActionExecutedContext context) { }
}
