namespace ZKTecoADMS.Domain.Enums;

/// <summary>Loại hàng: hàng hóa thường hoặc dịch vụ.</summary>
public enum PosProductType
{
    Goods = 0,
    Service = 1,
    Combo = 2,
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
