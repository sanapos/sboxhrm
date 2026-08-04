namespace ZKTecoADMS.Application.Authorization;

/// <summary>POS service package presets and catalog read paths for sell-only packages.</summary>
public static class PosPackageDefaults
{
    public const string BasicPackageName = "POS Cơ bản";

    /// <summary>Bán hàng lẻ cơ bản (không kho nâng cao / báo cáo).</summary>
    public static readonly string[] BasicModules =
    [
        "PosProducts",
        "PosSell",
        "PosPrintTemplates",
        "PosSaleOrders",
        "PosSaleReturns",
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
    ];

    /// <summary>Toàn bộ module POS trong catalog.</summary>
    public static readonly string[] FullModules = SellWarehouseModules;

    /// <summary>GET paths mapped to PosProducts but allowed when package only has PosSell.</summary>
    public static readonly string[] SellCatalogReadPrefixes =
    [
        "/api/pos/products",
        "/api/pos/catalog",
        "/api/pos/customers",
        "/api/pos/price-lists",
    ];

    /// <summary>GET mẫu in — thu ngân PosSell cần chọn mẫu khi bán.</summary>
    public const string SellPrintTemplatesReadPrefix = "/api/pos/print-templates";
}
