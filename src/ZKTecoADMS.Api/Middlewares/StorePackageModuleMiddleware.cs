using System.Security.Claims;
using ZKTecoADMS.Application.Authorization;
using ZKTecoADMS.Infrastructure.Helpers;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Middlewares;

/// <summary>
/// Blocks store-scoped API calls when the route maps to a module outside the store's service package.
/// </summary>
public class StorePackageModuleMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<StorePackageModuleMiddleware> _logger;

    private static readonly string[] BypassPrefixes =
    [
        "/api/auth",
        "/api/agent",
        "/api/agentregistration",
        "/api/system-admin",
        "/api/settings/my-modules",
        "/api/settings/public",
        "/api/publicsettings",
        "/api/store/license",
        "/api/permission-management/my-permissions",
        "/api/notifications",
        "/api/notification-preferences",
        "/api/hubs/",
        "/health",
    ];

  private static readonly (string Prefix, string Module)[] RouteModuleMap =
    [
        ("/api/employees", "Employee"),
        ("/api/departments", "Department"),
        ("/api/deviceusers", "DeviceUser"),
        ("/api/leaves", "Leave"),
        ("/api/attendances", "Attendance"),
        ("/api/workschedules", "WorkSchedule"),
        ("/api/payroll", "Payroll"),
        ("/api/payslips", "Payslip"),
        ("/api/bonuspenalties", "BonusPenalty"),
        ("/api/penaltytickets", "PenaltyTickets"),
        ("/api/advancerequests", "AdvanceRequests"),
        ("/api/cashtransactions", "CashTransaction"),
        ("/api/assets", "Asset"),
        ("/api/tasks", "Task"),
        ("/api/communications", "Communication"),
        ("/api/kpi", "KPI"),
        ("/api/production", "Production"),
        ("/api/feedback", "Feedback"),
        ("/api/meals", "Meal"),
        ("/api/devices", "Device"),
        ("/api/shifts", "ShiftSetup"),
        ("/api/shift-salary-levels", "ShiftSetup"),
        ("/api/allowances", "Allowance"),
        ("/api/penalties", "PenaltySetup"),
        ("/api/insurance", "Insurance"),
        ("/api/tax", "Tax"),
        ("/api/users", "UserManagement"),
        ("/api/permission-management", "Role"),
        ("/api/orgchart", "OrgChart"),
        ("/api/geofences", "Geofence"),
        ("/api/mobile-attendance", "MobileAttendance"),
        ("/api/reports/attendance", "AttendanceReport"),
        ("/api/reports/attendance-analytics", "AttendanceReport"),
        ("/api/reports/finance", "CashReport"),
        ("/api/reports/assets", "AssetReport"),
        ("/api/reports/executive", "Dashboard"),
        ("/api/reports/performance", "KPI"),
        ("/api/dashboard", "Dashboard"),
        ("/api/pos/sales", "PosSell"),
        ("/api/pos/purchase/receipts", "PosPurchaseReceipts"),
        ("/api/pos/purchase/returns", "PosPurchaseReturns"),
        ("/api/pos/purchase/suppliers", "PosPurchaseReceipts"),
        ("/api/pos/stock/counts", "PosStockCounts"),
        ("/api/pos/stock/damage", "PosDamageIssues"),
        ("/api/pos/stock/internal-use", "PosInternalUseIssues"),
        ("/api/pos/stock/issues", "PosProducts"),
        ("/api/pos/print-templates", "PosPrintTemplates"),
        ("/api/pos/reports", "PosSalesReport"),
        ("/api/pos/customers", "PosProducts"),
        ("/api/pos/catalog", "PosProducts"),
        ("/api/pos/products", "PosProducts"),
    ];

    public StorePackageModuleMiddleware(RequestDelegate next, ILogger<StorePackageModuleMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context, ZKTecoDbContext db)
    {
        if (!context.User.Identity?.IsAuthenticated ?? true)
        {
            await _next(context);
            return;
        }

        var role = context.User.FindFirst(ClaimTypes.Role)?.Value;
        if (role is "SuperAdmin" or "Agent")
        {
            await _next(context);
            return;
        }

        var storeIdClaim = context.User.FindFirst("storeId")?.Value;
        if (string.IsNullOrEmpty(storeIdClaim) || !Guid.TryParse(storeIdClaim, out var storeId))
        {
            await _next(context);
            return;
        }

        var path = context.Request.Path.Value?.ToLowerInvariant() ?? string.Empty;
        if (BypassPrefixes.Any(p => path.StartsWith(p, StringComparison.OrdinalIgnoreCase)))
        {
            await _next(context);
            return;
        }

        var module = ResolveModule(path);
        if (module == null || FeatureModuleCatalog.IsSelfService(module))
        {
            await _next(context);
            return;
        }

        var allowed = await StorePackageHelper.ResolveAllowedModulesAsync(db, storeId, context.RequestAborted);
        if (!allowed.Contains(module, StringComparer.OrdinalIgnoreCase) &&
            !IsImplicitlyAllowed(path, context.Request.Method, module, allowed))
        {
            _logger.LogWarning(
                "Package block: store {StoreId} role {Role} path {Path} module {Module}",
                storeId, role, path, module);

            context.Response.StatusCode = StatusCodes.Status403Forbidden;
            context.Response.Headers["X-SBOX-Error-Code"] = "PACKAGE_MODULE_DENIED";
            await context.Response.WriteAsJsonAsync(new
            {
                isSuccess = false,
                message = $"Gói dịch vụ của cửa hàng không bao gồm chức năng \"{module}\". Vui lòng nâng cấp gói.",
                errors = new[] { "PACKAGE_MODULE_DENIED" }
            });
            return;
        }

        await _next(context);
    }

    private static string? ResolveModule(string path)
    {
        foreach (var (prefix, module) in RouteModuleMap)
        {
            if (path.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                return module;
        }
        return null;
    }

    /// <summary>Gói chỉ có PosSell vẫn được đọc danh mục hàng phục vụ bán.</summary>
    private static bool IsImplicitlyAllowed(
        string path, string method, string module, IReadOnlyList<string> allowed)
    {
        if (!HttpMethods.IsGet(method) && !HttpMethods.IsHead(method))
            return false;

        if (!module.Equals("PosProducts", StringComparison.OrdinalIgnoreCase))
            return false;

        if (!allowed.Contains("PosSell", StringComparer.OrdinalIgnoreCase))
            return false;

        return PosPackageDefaults.SellCatalogReadPrefixes.Any(p =>
            path.StartsWith(p, StringComparison.OrdinalIgnoreCase));
    }
}

public static class StorePackageModuleMiddlewareExtensions
{
    public static IApplicationBuilder UseStorePackageModuleCheck(this IApplicationBuilder app)
        => app.UseMiddleware<StorePackageModuleMiddleware>();
}
