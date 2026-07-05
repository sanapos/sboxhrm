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
    EndOfDayReport = 11,
    StockIssue = 12,
    BarcodeLabel = 13,
    StockCount = 14,
}

/// <summary>Loại kết nối máy in cửa hàng.</summary>
public enum PosPrinterConnectionType
{
    Bluetooth = 0,
    Lan = 1,
    Sunmi = 2,
    Usb = 3,
}

/// <summary>Trạng thái sức khỏe máy in.</summary>
public enum PosPrinterHealthStatus
{
    Unknown = 0,
    Online = 1,
    Offline = 2,
    Error = 3,
    Busy = 4,
}

/// <summary>Trạng thái job in cloud.</summary>
public enum PosPrintJobStatus
{
    Queued = 0,
    Claimed = 1,
    Printing = 2,
    Completed = 3,
    Failed = 4,
    Cancelled = 5,
}

/// <summary>Định dạng payload job in.</summary>
public enum PosPrintPayloadFormat
{
    EscPosBase64 = 0,
    PdfBase64 = 1,
    HtmlUtf8 = 2,
}

/// <summary>Khổ giấy in.</summary>
public enum PosPrintPaperSize
{
    K58 = 0,
    K80 = 1,
    A5 = 2,
    A4 = 3,
}
