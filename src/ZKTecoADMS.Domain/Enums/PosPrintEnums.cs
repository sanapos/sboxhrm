namespace ZKTecoADMS.Domain.Enums;

/// <summary>Loại chứng từ mẫu in POS.</summary>
public enum PosPrintDocumentType
{
    SaleOrder = 0,
    SaleInvoice = 1,
    Delivery = 2,
    SaleReturn = 3,
    SaleExchange = 4,
    PurchaseOrder = 5,
    PurchaseReceipt = 6,
    PurchaseReturn = 7,
    StockTransfer = 8,
    CashReceipt = 9,
    CashPayment = 10,
}

/// <summary>Khổ giấy in.</summary>
public enum PosPrintPaperSize
{
    K58 = 0,
    K80 = 1,
    A5 = 2,
    A4 = 3,
}
