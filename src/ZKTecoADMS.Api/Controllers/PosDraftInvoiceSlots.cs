namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Slot hóa đơn động trên cửa hàng (mặc định 3, thêm/xóa được).
/// OrderNo tạm TMP{nn} đến khi thanh toán.
/// </summary>
public static class PosDraftInvoiceSlots
{
    public const int DefaultCount = 3;
    public const int MinCount = 1;
    public const int MaxCount = 24;

    public static string TempOrderNo(int slot) => $"TMP{slot:D2}";

    public static bool IsTempOrderNo(string? orderNo) =>
        !string.IsNullOrWhiteSpace(orderNo)
        && orderNo.StartsWith("TMP", StringComparison.OrdinalIgnoreCase);

    public static int ClampCount(int? count)
    {
        var n = count ?? DefaultCount;
        if (n < MinCount) n = DefaultCount;
        if (n > MaxCount) n = MaxCount;
        return n;
    }
}
