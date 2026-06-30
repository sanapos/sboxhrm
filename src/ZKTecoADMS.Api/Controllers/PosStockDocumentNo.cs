namespace ZKTecoADMS.Api.Controllers;

/// <summary>Sinh số chứng từ thẻ kho (kiểu KiotViet).</summary>
internal static class PosStockDocumentNo
{
    public static string NewAdjust() =>
        "DC" + DateTime.UtcNow.ToString("yyMMdd") + Random.Shared.Next(1000, 9999);

    public static string NewCostUpdate() =>
        "CP" + DateTime.UtcNow.ToString("yyMMdd") + Random.Shared.Next(1000, 9999);

    public static string NewIssue() =>
        "XK" + DateTime.UtcNow.ToString("yyMMdd") + Random.Shared.Next(1000, 9999);

    public static string NewCount() =>
        "KK" + DateTime.UtcNow.ToString("yyMMdd") + Random.Shared.Next(1000, 9999);

    public static string NewReturn() =>
        "TH" + DateTime.UtcNow.ToString("yyMMdd") + Random.Shared.Next(1000, 9999);

    public static string NewPurchaseReceipt() =>
        "PN" + DateTime.UtcNow.ToString("yyMMdd") + Random.Shared.Next(1000, 9999);

    public static string NewPurchaseReturn() =>
        "THN" + DateTime.UtcNow.ToString("yyMMdd") + Random.Shared.Next(1000, 9999);

    public static string NewSupplierPayment() =>
        "TTN" + DateTime.UtcNow.ToString("yyMMdd") + Random.Shared.Next(1000, 9999);
}
