namespace ZKTecoADMS.Application.Authorization;

/// <summary>POS service package presets and catalog read paths for sell-only packages.</summary>
public static class PosPackageDefaults
{
    public const string BasicPackageName = "POS Cơ bản";

    /// <summary>Modules included in the default POS retail package.</summary>
    public static readonly string[] BasicModules =
    [
        "PosProducts",
        "PosSell",
        "PosPrintTemplates",
        "PosSaleOrders",
    ];

    /// <summary>GET paths mapped to PosProducts but allowed when package only has PosSell.</summary>
    public static readonly string[] SellCatalogReadPrefixes =
    [
        "/api/pos/products",
        "/api/pos/catalog",
        "/api/pos/customers",
    ];
}
