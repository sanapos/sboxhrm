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
        "/api/webhooks/payment",
        "/api/webhooks/shipping",
        "/api/upload/public-serve",
        "/api/pos/customer-display/public-state",
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
        ("/api/businesstripcases", "BusinessTripExpense"),
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
        ("/api/pos/payment-gateway", "PosSell"),
        ("/api/pos/shipping", "PosShipping"),
        ("/api/pos/sales/return-history", "PosSaleReturns"),
        ("/api/pos/sales", "PosSell"),
        ("/api/pos/purchase/receipts", "PosPurchaseReceipts"),
        ("/api/pos/purchase/returns", "PosPurchaseReturns"),
        ("/api/pos/purchase/suppliers", "PosPurchaseReceipts"),
        ("/api/pos/stock/counts", "PosStockCounts"),
        ("/api/pos/stock/damage", "PosDamageIssues"),
        ("/api/pos/stock/internal-use", "PosInternalUseIssues"),
        ("/api/pos/stock/issues", "PosProducts"),
        // Ledger / phiếu nhập nhanh / điều chỉnh tồn — thuộc kho hàng (PosProducts).
        ("/api/pos/stock", "PosProducts"),
        ("/api/pos/print-templates", "PosPrintTemplates"),
        ("/api/pos/printers", "PosStorePrinters"),
        ("/api/pos/print-jobs", "PosSell"),
        ("/api/pos/product-printers", "PosStorePrinters"),
        ("/api/pos/kds", "PosKds"),
        ("/api/pos/qr-order", "PosQrOrder"),
        ("/api/pos/cashier-shifts", "PosCashierShift"),
        ("/api/pos/einvoice", "PosEInvoice"),
        ("/api/pos/vouchers", "PosProducts"),
        ("/api/pos/warranty", "PosSell"),
        ("/api/pos/topping-groups", "PosProducts"),
        // Báo cáo POS — path → module tách; sibling được phép qua IsImplicitlyAllowed.
        ("/api/pos/reports/sales", "PosReportRevenue"),
        ("/api/pos/reports/goods", "PosReportSoldGoods"),
        ("/api/pos/reports/stock/health", "PosProducts"),
        ("/api/pos/reports/stock/lots", "PosReportExpiry"),
        ("/api/pos/reports/stock", "PosReportStock"),
        ("/api/pos/reports/purchases", "PosReportPurchases"),
        ("/api/pos/reports/customer-debt", "PosReportDebt"),
        ("/api/pos/reports/supplier-debt", "PosReportDebt"),
        ("/api/pos/reports/expenses", "PosReportExpense"),
        ("/api/pos/reports/cashbook", "PosReportCashbook"),
        ("/api/pos/reports/pnl", "PosReportPnl"),
        ("/api/pos/reports/vouchers", "PosReportVoucher"),
        ("/api/pos/reports/end-of-day", "PosReportEndOfDay"),
        ("/api/pos/reports/profit", "PosReportProfit"),
        ("/api/pos/reports/analysis", "PosSalesReport"),
        ("/api/pos/reports", "PosSalesReport"),
        ("/api/hkd", "HkdBooks"),
        ("/api/pos/customers", "PosCustomers"),
        ("/api/pos/resource-reservations", "PosBooking"),
        ("/api/pos/warranty", "PosWarranty"),
        ("/api/pos/customer-display", "PosCustomerDisplay"),
        ("/api/pos/catalog", "PosProducts"),
        ("/api/pos/products", "PosProducts"),
        ("/api/pos/price-lists", "PosSell"),
        // Floor / ngành hàng / kitchen-void / cancel-return-audits / sell-settings…
        ("/api/pos", "PosSell"),
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
        // Trả hàng bán: /api/pos/sales/{id}/return|returns/... (không chỉ return-history).
        if (path.StartsWith("/api/pos/sales/", StringComparison.OrdinalIgnoreCase) &&
            path.Contains("/return", StringComparison.OrdinalIgnoreCase))
            return "PosSaleReturns";

        // Longer / more specific prefixes first (map order is not guaranteed to be path-length sorted).
        string? best = null;
        var bestLen = -1;
        foreach (var (prefix, module) in RouteModuleMap)
        {
            if (path.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) &&
                prefix.Length > bestLen)
            {
                best = module;
                bestLen = prefix.Length;
            }
        }
        return best;
    }

    /// <summary>Gói chỉ có PosSell vẫn đọc catalog/mẫu in; trả hàng cũng mở nếu có PosSell.</summary>
    private static bool IsImplicitlyAllowed(
        string path, string method, string module, IReadOnlyList<string> allowed)
    {
        // Gói có PosSell → coi như có Trả hàng bán (API + menu).
        if (module.Equals("PosSaleReturns", StringComparison.OrdinalIgnoreCase) &&
            allowed.Contains("PosSell", StringComparer.OrdinalIgnoreCase))
            return true;

        // Màn hình phụ: GET + PUT state khi bán (máy khác mở link) nếu gói có PosSell.
        if (module.Equals("PosCustomerDisplay", StringComparison.OrdinalIgnoreCase) &&
            allowed.Contains("PosSell", StringComparer.OrdinalIgnoreCase) &&
            path.StartsWith("/api/pos/customer-display", StringComparison.OrdinalIgnoreCase))
            return true;

        // Gói có PosSell → KDS / QR / ca / máy in thiết bị / HĐĐT / ĐVVC (gói cũ chưa tick addon).
        if (allowed.Contains("PosSell", StringComparer.OrdinalIgnoreCase) &&
            module is "PosKds" or "PosQrOrder" or "PosCashierShift" or "PosPrinters"
                or "PosEInvoice" or "PosShipping")
            return true;

        // Máy in cloud: Super Admin tick PosStorePrinters. Gói cũ chỉ có PosPrinters vẫn dùng được.
        if (module.Equals("PosStorePrinters", StringComparison.OrdinalIgnoreCase) &&
            (allowed.Contains("PosStorePrinters", StringComparer.OrdinalIgnoreCase) ||
             allowed.Contains("PosPrinters", StringComparer.OrdinalIgnoreCase)))
            return true;

        // POS A6: tạo thu ngân + phân quyền báo cáo (API /permission-management).
        if (allowed.Contains("PosSell", StringComparer.OrdinalIgnoreCase) &&
            module.Equals("Role", StringComparison.OrdinalIgnoreCase))
            return true;

        // Sổ thuế HKD: gói có báo cáo POS (gói cũ chưa tick HkdBooks).
        if (module.Equals("HkdBooks", StringComparison.OrdinalIgnoreCase) &&
            (allowed.Contains("HkdBooks", StringComparer.OrdinalIgnoreCase) ||
             allowed.Contains("PosSalesReport", StringComparer.OrdinalIgnoreCase) ||
             PosPackageDefaults.ReportModules.Any(m =>
                 allowed.Contains(m, StringComparer.OrdinalIgnoreCase))))
            return true;

        if (!HttpMethods.IsGet(method) && !HttpMethods.IsHead(method))
            return false;

        if (!allowed.Contains("PosSell", StringComparer.OrdinalIgnoreCase))
            return false;

        if (module.Equals("PosProducts", StringComparison.OrdinalIgnoreCase))
        {
            return PosPackageDefaults.SellCatalogReadPrefixes.Any(p =>
                path.StartsWith(p, StringComparison.OrdinalIgnoreCase));
        }

        if (module.Equals("PosPrintTemplates", StringComparison.OrdinalIgnoreCase))
        {
            return path.StartsWith(
                PosPackageDefaults.SellPrintTemplatesReadPrefix,
                StringComparison.OrdinalIgnoreCase);
        }

        // Thu ngân cần tra khách / bảo hành khi bán dù gói chưa tick CRM/BH (chỉ GET).
        if (module.Equals("PosCustomers", StringComparison.OrdinalIgnoreCase) &&
            path.StartsWith("/api/pos/customers", StringComparison.OrdinalIgnoreCase))
            return true;
        if (module.Equals("PosWarranty", StringComparison.OrdinalIgnoreCase) &&
            path.StartsWith("/api/pos/warranty", StringComparison.OrdinalIgnoreCase))
            return true;

        if (path.StartsWith("/api/pos/reports", StringComparison.OrdinalIgnoreCase) &&
            PosPackageDefaults.PackageAllowsReportApi(path, allowed))
            return true;

        return false;
    }
}

public static class StorePackageModuleMiddlewareExtensions
{
    public static IApplicationBuilder UseStorePackageModuleCheck(this IApplicationBuilder app)
        => app.UseMiddleware<StorePackageModuleMiddleware>();
}
