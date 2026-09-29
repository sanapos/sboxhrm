using System.Security.Claims;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.Extensions.Options;
using ZKTecoADMS.Application.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;

namespace ZKTecoADMS.Api.Authorization;

/// <summary>
/// Che giá vốn / giá trị tồn / lãi trong dữ liệu trả về khi người xem không có quyền «Xem giá vốn & lợi nhuận»
/// (PosViewCost). Chủ / giám đốc / quản trị luôn thấy.
/// </summary>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method, AllowMultiple = false)]
public sealed class MaskCostDataAttribute : TypeFilterAttribute
{
    /// <param name="extraKeys">Tên trường riêng của endpoint (vd «totalValue» ở kho chi nhánh).</param>
    public MaskCostDataAttribute(params string[] extraKeys) : base(typeof(MaskCostDataFilter))
    {
        Arguments = [extraKeys];
    }
}

public sealed class MaskCostDataFilter(string[] extraKeys, IModulePermissionService permissions) : IAsyncResultFilter
{
    public const string Module = "PosViewCost";

    static readonly HashSet<string> CostKeys = new(StringComparer.OrdinalIgnoreCase)
    {
        "costPrice", "defaultCostPrice", "avgCost", "averageCost", "lastCost", "lastCostPrice", "totalCost",
        "costAmount", "costValue", "lineCost", "unitCost", "cogs", "stockValue", "grossProfit", "profit",
        "profitMargin", "grossMarginPct", "marginPct",
    };

    public async Task OnResultExecutionAsync(ResultExecutingContext context, ResultExecutionDelegate next)
    {
        if (context.Result is ObjectResult { Value: not null } result &&
            context.HttpContext.User.Identity?.IsAuthenticated == true &&
            !await CanViewCostAsync(context.HttpContext.User, context.HttpContext.RequestAborted))
        {
            var options = context.HttpContext.RequestServices
                .GetService<IOptions<JsonOptions>>()?.Value.JsonSerializerOptions
                ?? new JsonSerializerOptions(JsonSerializerDefaults.Web);
            var node = JsonSerializer.SerializeToNode(result.Value, result.Value.GetType(), options);
            if (node != null)
            {
                Strip(node, extraKeys);
                result.Value = node;
                result.DeclaredType = typeof(JsonNode);
            }
        }
        await next();
    }

    async Task<bool> CanViewCostAsync(ClaimsPrincipal user, CancellationToken ct)
    {
        var role = user.FindFirst(ClaimTypes.Role)?.Value ?? "";
        if (ModulePermissionDefaults.IsSuperRole(role)) return true;
        if (!Guid.TryParse(user.FindFirst("id")?.Value ?? user.FindFirst(ClaimTypes.NameIdentifier)?.Value, out var userId))
            return true;
        Guid? storeId = Guid.TryParse(user.FindFirst("storeId")?.Value, out var sid) ? sid : null;
        return await permissions.HasPermissionAsync(userId, role, storeId, Module, ModulePermissionAction.View, ct);
    }

    static void Strip(JsonNode node, string[] extra)
    {
        switch (node)
        {
            case JsonObject obj:
                foreach (var key in obj.Select(kv => kv.Key).ToList())
                {
                    if (CostKeys.Contains(key) || extra.Contains(key, StringComparer.OrdinalIgnoreCase))
                        obj.Remove(key);
                    else if (obj[key] is { } child)
                        Strip(child, extra);
                }
                break;
            case JsonArray arr:
                foreach (var item in arr)
                    if (item != null) Strip(item, extra);
                break;
        }
    }
}
