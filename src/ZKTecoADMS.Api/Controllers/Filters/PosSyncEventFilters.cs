using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.AspNetCore.SignalR;
using ZKTecoADMS.Api.Hubs;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;

namespace ZKTecoADMS.Api.Controllers.Filters;

/// <summary>
/// Phát PosFloorChanged sau khi API ghi thành công (2xx) — các máy khác cập nhật ngay
/// thay vì chờ vòng hỏi định kỳ. [IdKind] cho biết route {id} là đơn / bàn / phiên.
/// </summary>
[AttributeUsage(AttributeTargets.Method)]
public sealed class NotifyPosFloorAttribute(string reason, string idKind = "none") : Attribute, IAsyncActionFilter
{
    public string Reason { get; } = reason;

    public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
    {
        var executed = await next();
        if (executed.Exception != null && !executed.ExceptionHandled) return;
        if (!PosSyncEvents.IsSuccess(executed.Result)) return;
        var storeId = PosSyncEvents.StoreId(context.HttpContext);
        if (storeId == Guid.Empty) return;

        Guid? id = context.RouteData.Values.TryGetValue("id", out var raw) && Guid.TryParse($"{raw}", out var g)
            ? g : null;
        var hub = context.HttpContext.RequestServices.GetService<IHubContext<AttendanceHub>>();
        PosFloorRealtimeHelper.Notify(hub, storeId, Reason,
            orderId: idKind == "order" ? id : null,
            resourceId: idKind == "resource" ? id : null,
            sessionId: idKind == "session" ? id : null);
    }
}

/// <summary>
/// Hàng hóa / giá / tồn đổi (sửa món, nhập / xuất / kiểm kho, bảng giá, khuyến mãi, topping…)
/// → phát «catalogChanged»: máy bán đồng bộ phần thay đổi của danh mục ngay (không đợi 2 phút).
/// </summary>
public sealed class PosCatalogChangedFilter : IAsyncActionFilter
{
    static readonly string[] Prefixes =
    [
        "/api/pos/products",
        "/api/pos/catalog",
        "/api/pos/stock",
        "/api/pos/purchase/receipts",
        "/api/pos/purchase/returns",
        "/api/pos/price-lists",
        "/api/pos/promotions",
        "/api/pos/topping-groups",
        "/api/branch-ops",
    ];

    public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
    {
        var executed = await next();
        var method = context.HttpContext.Request.Method;
        if (method is not ("POST" or "PUT" or "PATCH" or "DELETE")) return;
        if (executed.Exception != null && !executed.ExceptionHandled) return;
        if (!PosSyncEvents.IsSuccess(executed.Result)) return;
        var path = context.HttpContext.Request.Path.Value ?? "";
        if (!Prefixes.Any(p => path.StartsWith(p, StringComparison.OrdinalIgnoreCase))) return;
        var storeId = PosSyncEvents.StoreId(context.HttpContext);
        if (storeId == Guid.Empty) return;
        var hub = context.HttpContext.RequestServices.GetService<IHubContext<AttendanceHub>>();
        PosFloorRealtimeHelper.Notify(hub, storeId, "catalogChanged");
    }
}

static class PosSyncEvents
{
    public static bool IsSuccess(IActionResult? result) => result switch
    {
        ObjectResult o => (o.StatusCode ?? 200) is >= 200 and < 300,
        StatusCodeResult s => s.StatusCode is >= 200 and < 300,
        EmptyResult => true,
        null => false,
        _ => true,
    };

    public static Guid StoreId(HttpContext http) =>
        Guid.TryParse(http.User.FindFirst(ClaimTypeNames.StoreId)?.Value, out var g) ? g : Guid.Empty;
}
