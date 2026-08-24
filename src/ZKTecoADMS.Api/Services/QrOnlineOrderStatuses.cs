namespace ZKTecoADMS.Api.Services;

/// <summary>Trạng thái đơn QR online (lưu PosSaleOrder.DeliveryStatus).</summary>
public static class QrOnlineOrderStatuses
{
    public const string Channel = "QR online";

    public const string Pending = "pending";
    public const string Confirmed = "confirmed";
    public const string Preparing = "preparing";
    public const string Shipping = "shipping";
    public const string Delivered = "delivered";
    public const string Cancelled = "cancelled";

    public static readonly string[] All =
    [
        Pending, Confirmed, Preparing, Shipping, Delivered, Cancelled,
    ];

    public static string Label(string? code) => (code ?? "").Trim().ToLowerInvariant() switch
    {
        Pending => "Chờ xác nhận",
        Confirmed => "Đã xác nhận",
        Preparing => "Đang chuẩn bị",
        Shipping => "Đang giao",
        Delivered => "Giao thành công",
        Cancelled => "Đã hủy",
        _ => string.IsNullOrWhiteSpace(code) ? "Chờ xác nhận" : code.Trim(),
    };

    public static string Normalize(string? code)
    {
        var c = (code ?? "").Trim().ToLowerInvariant();
        if (c is "cho_xac_nhan" or "chờ xác nhận" or "cho xac nhan") return Pending;
        if (c is "da_xac_nhan" or "đã xác nhận" or "da xac nhan") return Confirmed;
        if (c is "dang_chuan_bi" or "đang chuẩn bị" or "dang chuan bi") return Preparing;
        if (c is "dang_giao" or "đang giao" or "shipping" or "đang vận chuyển" or "dang van chuyen")
            return Shipping;
        if (c is "da_giao" or "đã giao" or "giao thành công" or "giao thanh cong" or "success")
            return Delivered;
        if (c is "huy" or "đã hủy" or "da huy" or "cancel") return Cancelled;
        if (All.Contains(c)) return c;
        return Pending;
    }

    public static bool IsValid(string? code) => All.Contains(Normalize(code));

    public static bool IsTerminal(string? code)
    {
        var n = Normalize(code);
        return n is Delivered or Cancelled;
    }

    /// <summary>Các trạng thái tiếp theo hợp lệ (ẩn bước cũ trên UI thu ngân).</summary>
    public static IReadOnlyList<string> ForwardStatuses(string? code)
    {
        return Normalize(code) switch
        {
            // Chờ → thẳng Đang chuẩn bị (nút «Xác nhận đơn»); Confirmed giữ cho đơn cũ.
            Pending => [Preparing, Cancelled],
            Confirmed => [Preparing, Cancelled],
            Preparing => [Shipping, Cancelled],
            Shipping => [Delivered],
            _ => [],
        };
    }

    public static string ActionLabel(string? code) => Normalize(code) switch
    {
        Confirmed => "Xác nhận đơn",
        Preparing => "Xác nhận đơn",
        Shipping => "Giao cho shipper",
        Delivered => "Hoàn thành giao",
        Cancelled => "Hủy đơn",
        _ => Label(code),
    };
}
