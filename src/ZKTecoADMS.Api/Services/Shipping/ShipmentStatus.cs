namespace ZKTecoADMS.Api.Services.Shipping;

/// <summary>
/// Bộ trạng thái vận đơn chuẩn — mọi hãng quy về đây để báo cáo / xử lý thống nhất.
/// Lưu ở PosSaleOrder.DeliveryStatusCode; DeliveryStatus giữ nhãn hiển thị (đơn online giữ mã online).
/// </summary>
public static class ShipmentStatus
{
    public const string Creating = "creating";
    public const string Created = "created";
    public const string Picking = "picking";
    public const string InTransit = "in_transit";
    public const string Delivering = "delivering";
    /// <summary>Giao không thành công — hãng sẽ giao lại hoặc chuyển hoàn. KHÔNG phải trạng thái cuối.</summary>
    public const string DeliveryFailed = "delivery_failed";
    public const string Delivered = "delivered";
    /// <summary>Đang chuyển hoàn về shop — hàng chưa về, chưa nhập kho.</summary>
    public const string Returning = "returning";
    /// <summary>Đã hoàn về shop — lúc này mới nhập kho lại / trừ doanh thu.</summary>
    public const string Returned = "returned";
    public const string Cancelled = "cancelled";
    /// <summary>Sự cố: thất lạc, hư hỏng, bồi hoàn.</summary>
    public const string Issue = "issue";

    public static readonly string[] All =
    [
        Created, Picking, InTransit, Delivering, DeliveryFailed, Delivered,
        Returning, Returned, Cancelled, Issue,
    ];

    public static string Label(string? code) => code switch
    {
        Creating => "Đang tạo vận đơn",
        Created => "Đã tạo vận đơn",
        Picking => "Đang lấy hàng",
        InTransit => "Đã lấy hàng / đang vận chuyển",
        Delivering => "Đang giao hàng",
        DeliveryFailed => "Giao thất bại",
        Delivered => "Đã giao hàng",
        Returning => "Đang hoàn hàng",
        Returned => "Đã hoàn về shop",
        Cancelled => "Đã hủy vận đơn",
        Issue => "Sự cố (thất lạc / hư hỏng)",
        _ => code ?? "",
    };

    /// <summary>Trạng thái cuối: không nhận chuyển tiếp nữa (trừ khi cùng trạng thái).</summary>
    public static bool IsTerminal(string? code) => code is Delivered or Returned or Cancelled;

    /// <summary>
    /// Có cho chuyển từ <paramref name="from"/> sang <paramref name="to"/> không.
    /// Giao thất bại / đang hoàn không phải cuối → vẫn nhận «Đã giao» nếu shipper giao lại được.
    /// Đã giao → chỉ nhận «đang hoàn / đã hoàn» (khách từ chối sau khi ký, hãng hoàn).
    /// </summary>
    public static bool CanTransition(string? from, string to)
    {
        if (string.IsNullOrWhiteSpace(from) || from == Creating) return true;
        if (from == to) return true;
        if (from == Cancelled) return false;
        if (from == Returned) return false;
        if (from == Delivered) return to is Returning or Returned or Issue;
        return true;
    }

    /// <summary>Mã trạng thái đơn QR online tương ứng (null = giữ nguyên).</summary>
    public static string? ToOnlineStatus(string code) => code switch
    {
        Created or Picking => QrOnlineOrderStatuses.Confirmed,
        InTransit or Delivering or DeliveryFailed or Returning or Issue => QrOnlineOrderStatuses.Shipping,
        Delivered => QrOnlineOrderStatuses.Delivered,
        Returned or Cancelled => QrOnlineOrderStatuses.Cancelled,
        _ => null,
    };

    // ── Quy đổi trạng thái từng hãng ──────────────────────────────────

    /// <summary>GHN: status dạng chữ (ready_to_pick, delivering, delivery_fail, returned…).</summary>
    public static string? FromGhn(string? raw)
    {
        var s = (raw ?? "").Trim().ToLowerInvariant();
        return s switch
        {
            "ready_to_pick" => Created,
            "picking" or "money_collect_picking" => Picking,
            "picked" or "storing" or "transporting" or "sorting" => InTransit,
            "delivering" or "money_collect_delivering" => Delivering,
            "delivered" => Delivered,
            "delivery_fail" => DeliveryFailed,
            "waiting_to_return" or "return" or "return_transporting" or "return_sorting"
                or "returning" or "return_fail" => Returning,
            "returned" => Returned,
            "cancel" => Cancelled,
            "exception" or "damage" or "lost" => Issue,
            _ => null,
        };
    }

    /// <summary>GHTK: status_id số.</summary>
    public static string? FromGhtk(int? statusId) => statusId switch
    {
        -1 or 7 => Cancelled,
        1 or 2 => Created,
        8 or 12 or 127 or 128 => Picking,
        3 or 123 => InTransit,
        4 or 10 or 410 => Delivering,
        5 or 6 or 45 => Delivered,
        9 or 49 => DeliveryFailed,
        20 => Returning,
        11 or 21 => Returned,
        13 => Issue,
        _ => null,
    };

    /// <summary>Viettel Post: ORDER_STATUS số.</summary>
    public static string? FromViettelPost(int? code) => code switch
    {
        null => null,
        501 => Delivered,
        504 => Returned,
        502 or 505 or 515 => Returning,
        503 or 107 or 201 or 101 => Cancelled,
        506 or 507 => DeliveryFailed,
        500 or 508 or 509 or 550 => Delivering,
        -100 or -108 or -109 or -110 or 100 or 102 or 103 or 104 or 106 => Created,
        105 or 200 or 202 or 300 or 301 or 302 or 303 or 400 or 401 or 402 or 403 or 404 => InTransit,
        _ => code >= 300 && code < 500 ? InTransit : null,
    };

    /// <summary>SPX: status dạng chữ.</summary>
    public static string? FromSpx(string? raw)
    {
        var n = (raw ?? "").Trim().ToLowerInvariant().Replace(' ', '_').Replace('-', '_');
        return n switch
        {
            "delivered" or "completed" or "success" => Delivered,
            "failed" or "undelivered" or "delivery_failed" or "failed_delivery" => DeliveryFailed,
            "returning" or "rto" or "return_in_transit" => Returning,
            "returned" or "return_completed" or "rto_delivered" => Returned,
            "cancelled" or "canceled" or "void" => Cancelled,
            "lost" or "damaged" => Issue,
            "pickup" or "picking" or "pending_pickup" => Picking,
            "picked_up" or "picked" or "collected" or "in_transit" or "transit" or "hub_in" or "hub_out" => InTransit,
            "delivering" or "out_for_delivery" or "on_delivery" => Delivering,
            "created" or "pending" or "new" or "order_created" or "on_hold" or "delay" => Created,
            _ => null,
        };
    }

    /// <summary>AhaMove: status đơn (IDLE, ASSIGNING, ACCEPTED, IN PROCESS, COMPLETED, CANCELLED, FAILED, RETURNED).</summary>
    public static string? FromAhamove(string? raw)
    {
        var s = (raw ?? "").Trim().ToUpperInvariant().Replace('_', ' ');
        if (s is "INPROCESS") s = "IN PROCESS";
        return s switch
        {
            "IDLE" or "ASSIGNING" or "CONFIRMING" => Created,
            "ACCEPTED" or "BOARDING" or "PICKING" => Picking,
            "IN PROCESS" => Delivering,
            "COMPLETED" => Delivered,
            "FAILED" => DeliveryFailed,
            "IN RETURN" => Returning,
            "RETURNED" => Returned,
            "CANCELLED" => Cancelled,
            _ => null,
        };
    }

    public static string? FromCarrier(string carrierCode, string? rawText, int? rawNumber) =>
        ShippingCarrierCodes.Normalize(carrierCode) switch
        {
            ShippingCarrierCodes.Ghn => FromGhn(rawText),
            ShippingCarrierCodes.Ghtk => FromGhtk(rawNumber),
            ShippingCarrierCodes.ViettelPost => FromViettelPost(rawNumber),
            ShippingCarrierCodes.Spx => FromSpx(rawText),
            ShippingCarrierCodes.Ahamove => FromAhamove(rawText),
            _ => null,
        };
}
