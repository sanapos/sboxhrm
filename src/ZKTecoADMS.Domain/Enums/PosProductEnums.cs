namespace ZKTecoADMS.Domain.Enums;

/// <summary>Loại hàng POS — 5 loại độc lập.</summary>
public enum PosProductType
{
    Goods = 0,
    Service = 1,
    Combo = 2,
    Material = 3,
    Topping = 4,
}

/// <summary>Nhóm mẫu Super Admin: hàng đóng gói (có mã vạch) / món ăn / đồ uống.</summary>
public enum PosProductSampleKind
{
    Packaged = 0,
    Food = 1,
    Drink = 2,
}

public static class PosProductTypeRules
{
    public static bool TracksInventory(PosProductType t) =>
        t is PosProductType.Goods or PosProductType.Material or PosProductType.Topping;

    public static bool AllowsRecipe(PosProductType t) =>
        t is PosProductType.Goods or PosProductType.Service or PosProductType.Topping;

    public static bool IsRecipeComponent(PosProductType t) =>
        t is PosProductType.Material or PosProductType.Goods;

    public static bool IsComboComponent(PosProductType t) =>
        t is not PosProductType.Combo and not PosProductType.Service;

    public static string CodePrefix(PosProductType t) => t switch
    {
        PosProductType.Service => "DV",
        PosProductType.Combo => "CB",
        PosProductType.Material => "NVL",
        PosProductType.Topping => "TP",
        _ => "HH",
    };

    public static string DisplayName(PosProductType t) => t switch
    {
        PosProductType.Service => "Dịch vụ",
        PosProductType.Combo => "Combo",
        PosProductType.Material => "Nguyên vật liệu",
        PosProductType.Topping => "Topping",
        _ => "Hàng hóa",
    };

    public static PosProductType Parse(string? raw, PosProductType fallback = PosProductType.Goods)
    {
        if (string.IsNullOrWhiteSpace(raw)) return fallback;
        var s = raw.Trim().ToLowerInvariant();
        if (s is "1" or "service" or "dịch vụ" or "dich vu") return PosProductType.Service;
        if (s is "2" or "combo") return PosProductType.Combo;
        if (s is "3" or "material" or "nvl" or "nguyên vật liệu" or "nguyen vat lieu")
            return PosProductType.Material;
        if (s is "4" or "topping" or "tp") return PosProductType.Topping;
        if (s is "0" or "goods" or "hàng hóa" or "hang hoa") return PosProductType.Goods;
        if (s.Contains("topping")) return PosProductType.Topping;
        if (s.Contains("nvl") || s.Contains("nguyên vật") || s.Contains("nguyen vat") ||
            s.Contains("material"))
            return PosProductType.Material;
        if (s.Contains("combo")) return PosProductType.Combo;
        if (s.Contains("dịch vụ") || s.Contains("dich vu") || s.Contains("service"))
            return PosProductType.Service;
        return fallback;
    }
}

/// <summary>Lọc tồn kho trên danh sách hàng hóa.</summary>
public enum PosStockFilter
{
    All = 0,
    BelowMin = 1,
    OutOfStock = 2,
    AboveMax = 3,
}

/// <summary>Loại biến động tồn kho.</summary>
public enum PosStockTransactionType
{
    StockIn = 0,
    StockOut = 1,
    Adjust = 2,
    Sale = 3,
    Purchase = 4,
    Return = 5,
    PurchaseReturn = 6,
}

/// <summary>Trạng thái đơn bán POS.</summary>
public enum PosSaleOrderStatus
{
    Draft = 0,
    Completed = 1,
    Cancelled = 2,
}

/// <summary>Lọc dự kiến hết hàng.</summary>
public enum PosStockoutFilter
{
    All = 0,
    Within7Days = 1,
    Within30Days = 2,
}

/// <summary>Sắp xếp danh sách hàng hóa.</summary>
public enum PosProductSortBy
{
    Name = 0,
    Code = 1,
    Price = 2,
    Stock = 3,
    CreatedAt = 4,
}

/// <summary>Trạng thái phiếu kiểm kê POS.</summary>
public enum PosStockCountStatus
{
    InProgress = 0,
    Completed = 1,
    Cancelled = 2,
}

/// <summary>Trạng thái phiếu nhập hàng (Mua hàng).</summary>
public enum PosPurchaseReceiptStatus
{
    Draft = 0,
    Completed = 1,
    Cancelled = 2,
}

/// <summary>Trạng thái phiếu trả hàng nhập.</summary>
public enum PosPurchaseReturnStatus
{
    Draft = 0,
    Completed = 1,
    Cancelled = 2,
}

/// <summary>Loại phiếu xuất kho POS.</summary>
public enum PosStockIssueKind
{
    Generic = 0,
    Damage = 1,
    InternalUse = 2,
}

/// <summary>Trạng thái phiếu xuất kho POS.</summary>
public enum PosStockIssueStatus
{
    Draft = 0,
    Completed = 1,
    Cancelled = 2,
}

/// <summary>Trạng thái lô hàng POS.</summary>
public enum PosStockLotStatus
{
    Active = 0,
    Depleted = 1,
    Voided = 2,
}
