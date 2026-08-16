namespace ZKTecoADMS.Application.Authorization;

/// <summary>POS service package presets and catalog read paths for sell-only packages.</summary>
public static class PosPackageDefaults
{
    public const string BasicPackageName = "POS Cơ bản";

    /// <summary>14 báo cáo POS tách riêng — tick Super Admin / phân quyền.</summary>
    public static readonly string[] ReportModules =
    [
        "PosReportRevenue",
        "PosReportSoldGoods",
        "PosReportStock",
        "PosReportPurchases",
        "PosReportPayment",
        "PosReportDebt",
        "PosReportExpiry",
        "PosReportProfit",
        "PosReportExpense",
        "PosReportEndOfDay",
        "PosReportStaffRevenue",
        "PosReportCashbook",
        "PosReportPnl",
        "PosReportVoucher",
    ];

    /// <summary>Bán hàng lẻ cơ bản (không kho nâng cao / báo cáo).</summary>
    public static readonly string[] BasicModules =
    [
        "PosProducts",
        "PosSell",
        "PosPrintTemplates",
        "PosSaleOrders",
        "PosSaleReturns",
        "PosCustomers",
        "PosBooking",
        "PosWarranty",
        "PosCustomerDisplay",
        "PosEInvoice",
        "PosKds",
        "PosQrOrder",
        "PosCashierShift",
        "PosPrinters",
    ];

    /// <summary>Bán hàng + báo cáo doanh thu.</summary>
    public static readonly string[] SellModules =
    [
        "PosProducts",
        "PosSell",
        "PosPrintTemplates",
        "PosSaleOrders",
        "PosSaleReturns",
        "PosSalesReport",
        ..ReportModules,
        "HkdBooks",
        "PosCustomers",
        "PosBooking",
        "PosWarranty",
        "PosCustomerDisplay",
        "PosEInvoice",
        "PosKds",
        "PosQrOrder",
        "PosCashierShift",
        "PosPrinters",
    ];

    /// <summary>Bán hàng + kho (nhập / trả NCC / kiểm / xuất).</summary>
    public static readonly string[] SellWarehouseModules =
    [
        "PosProducts",
        "PosSell",
        "PosPrintTemplates",
        "PosSaleOrders",
        "PosSaleReturns",
        "PosPurchaseReceipts",
        "PosPurchaseReturns",
        "PosStockCounts",
        "PosDamageIssues",
        "PosInternalUseIssues",
        "PosSalesReport",
        ..ReportModules,
        "PosCustomers",
        "PosBooking",
        "PosWarranty",
        "PosCustomerDisplay",
        "PosEInvoice",
        "PosKds",
        "PosQrOrder",
        "PosCashierShift",
        "PosPrinters",
    ];

    /// <summary>Toàn bộ module POS trong catalog.</summary>
    public static readonly string[] FullModules = SellWarehouseModules;

    /// <summary>
    /// Addon tách từ PosSell — khi gói đã có PosSell thì seed bổ sung để không gãy cửa hàng cũ.
    /// </summary>
    public static readonly string[] SellAddonModules =
    [
        "PosCustomers",
        "PosBooking",
        "PosWarranty",
        "PosCustomerDisplay",
        "PosEInvoice",
        "PosKds",
        "PosQrOrder",
        "PosCashierShift",
        "PosPrinters",
    ];

    /// <summary>GET paths mapped to PosProducts but allowed when package only has PosSell.</summary>
    public static readonly string[] SellCatalogReadPrefixes =
    [
        "/api/pos/products",
        "/api/pos/catalog",
        "/api/pos/price-lists",
    ];

    /// <summary>GET mẫu in — thu ngân PosSell cần chọn mẫu khi bán.</summary>
    public const string SellPrintTemplatesReadPrefix = "/api/pos/print-templates";

    public static bool IsReportModule(string? module) =>
        !string.IsNullOrEmpty(module) &&
        ReportModules.Contains(module, StringComparer.OrdinalIgnoreCase);

    /// <summary>Gói được gọi API báo cáo nếu có đúng module (hoặc sibling dùng chung path).</summary>
    public static bool PackageAllowsReportApi(string path, IReadOnlyList<string> allowed)
    {
        bool Has(params string[] codes) =>
            codes.Any(c => allowed.Contains(c, StringComparer.OrdinalIgnoreCase));

        if (path.StartsWith("/api/pos/reports/sales", StringComparison.OrdinalIgnoreCase))
            return Has("PosSalesReport", "PosReportRevenue", "PosReportPayment",
                "PosReportStaffRevenue", "PosReportProfit");
        if (path.StartsWith("/api/pos/reports/goods", StringComparison.OrdinalIgnoreCase))
            return Has("PosReportSoldGoods", "PosProducts", "PosSalesReport");
        if (path.StartsWith("/api/pos/reports/stock/health", StringComparison.OrdinalIgnoreCase))
            return Has("PosProducts", "PosSalesReport");
        if (path.StartsWith("/api/pos/reports/stock/lots", StringComparison.OrdinalIgnoreCase))
            return Has("PosReportExpiry", "PosReportStock", "PosProducts");
        if (path.StartsWith("/api/pos/reports/stock", StringComparison.OrdinalIgnoreCase))
            return Has("PosReportStock", "PosProducts");
        if (path.StartsWith("/api/pos/reports/purchases", StringComparison.OrdinalIgnoreCase))
            return Has("PosReportPurchases");
        if (path.StartsWith("/api/pos/reports/customer-debt", StringComparison.OrdinalIgnoreCase)
            || path.StartsWith("/api/pos/reports/supplier-debt", StringComparison.OrdinalIgnoreCase))
            return Has("PosReportDebt", "PosSalesReport");
        if (path.StartsWith("/api/pos/reports/expenses", StringComparison.OrdinalIgnoreCase))
            return Has("PosReportExpense");
        if (path.StartsWith("/api/pos/reports/cashbook", StringComparison.OrdinalIgnoreCase))
            return Has("PosReportCashbook");
        if (path.StartsWith("/api/pos/reports/pnl", StringComparison.OrdinalIgnoreCase))
            return Has("PosReportPnl");
        if (path.StartsWith("/api/pos/reports/vouchers", StringComparison.OrdinalIgnoreCase))
            return Has("PosReportVoucher");
        if (path.StartsWith("/api/pos/reports/end-of-day", StringComparison.OrdinalIgnoreCase))
            return Has("PosReportEndOfDay", "PosProducts", "PosSalesReport");
        if (path.StartsWith("/api/pos/reports/profit", StringComparison.OrdinalIgnoreCase))
            return Has("PosReportProfit", "PosSalesReport");
        if (path.StartsWith("/api/pos/reports/analysis", StringComparison.OrdinalIgnoreCase))
            return Has("PosSalesReport");
        if (path.StartsWith("/api/pos/reports", StringComparison.OrdinalIgnoreCase))
            return Has("PosSalesReport") || ReportModules.Any(m => Has(m));
        return false;
    }
}
