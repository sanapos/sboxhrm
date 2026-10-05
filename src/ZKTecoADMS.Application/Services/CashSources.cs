namespace ZKTecoADMS.Application.Services;

/// <summary>
/// Nguồn chứng từ của phiếu thu / chi (CashTransaction.SourceType + SourceId) — một danh mục chung cho HRM và POS.
/// Trước đây liên kết nằm trong InternalNote (chuỗi «… #&lt;id&gt;») mà người dùng sửa được → mất liên kết, hủy / xóa
/// không đồng bộ. Nay mọi phiếu tự sinh mang SourceType/SourceId; chuỗi cũ chỉ còn để đọc dữ liệu cũ.
/// </summary>
public static class CashSources
{
    /// <summary>Phiếu kế toán tự lập trên màn Thu chi (không gắn chứng từ).</summary>
    public const string Manual = "manual";

    // ── Nhân sự ──
    public const string Payslip = "payslip";
    public const string Advance = "advance";
    public const string Reward = "reward";
    public const string PenaltyTicket = "penalty_ticket";
    public const string TripAdvance = "trip_advance";
    public const string TripSettlement = "trip_settlement";
    public const string TripRefund = "trip_refund";

    // ── Bán hàng (POS) ──
    public const string PosSale = "pos_sale";
    public const string PosDeposit = "pos_deposit";
    public const string PosDepositRefund = "pos_deposit_refund";
    public const string PosPurchaseReceipt = "pos_purchase_receipt";
    public const string PosSupplierPayment = "pos_supplier_payment";
    public const string PosCustomerReturn = "pos_customer_return";
    public const string PosCustomerPayment = "pos_customer_payment";
    public const string PosPurchaseReturnRefund = "pos_purchase_return_refund";
    /// <summary>Thu tiền hợp đồng (giữ tên cũ «PosQuote» đã lưu trong dữ liệu).</summary>
    public const string PosContract = "PosQuote";

    /// <summary>
    /// Chuỗi đánh dấu cũ trong InternalNote → nguồn. Thứ tự: cụ thể trước (vd «thu hoàn ứng công tác #» trước «ứng công tác #»).
    /// Mã chứng từ là GUID ngay sau dấu «#».
    /// </summary>
    static readonly (string Marker, string Type)[] Markers =
    [
        ("pos hoàn cọc đặt chỗ #", PosDepositRefund),
        ("pos cọc đặt chỗ #", PosDeposit),
        ("pos bán hàng #", PosSale),
        ("pos nhập hàng #", PosPurchaseReceipt),
        ("pos thanh toán ncc #", PosSupplierPayment),
        ("pos trả khách #", PosCustomerReturn),
        ("pos thu nợ kh #", PosCustomerPayment),
        ("pos thu trả ncc #", PosPurchaseReturnRefund),
        ("pos thu hđ #", PosContract),
        ("phiếu lương #", Payslip),
        ("yêu cầu ứng lương #", Advance),
        ("thanh toán ứng lương #", Advance),
        ("phiếu thưởng/phạt #", Reward),
        // Phạt tự duyệt (PaymentTransaction) — khác phiếu phạt (PenaltyTicket).
        ("tự động tạo từ phiếu phạt #", Reward),
        ("thu hoàn ứng công tác #", TripRefund),
        ("quyết toán công tác phí #", TripSettlement),
        ("ứng công tác #", TripAdvance),
        ("phiếu phạt #", PenaltyTicket),
    ];

    public static bool IsLinked(string? sourceType) =>
        !string.IsNullOrWhiteSpace(sourceType) && !string.Equals(sourceType, Manual, StringComparison.OrdinalIgnoreCase);

    /// <summary>Chứng từ bán hàng: tiền đã thu / chi ngay khi hoàn tất chứng từ — sửa / hủy ở chứng từ gốc.</summary>
    public static bool IsPos(string? sourceType) =>
        sourceType != null && (sourceType.StartsWith("pos_", StringComparison.Ordinal) || sourceType == PosContract);

    /// <summary>Chứng từ nhân sự mà phiếu thu / chi là bước «thanh toán» (bỏ thanh toán / xóa → hoàn trạng thái chứng từ).</summary>
    public static bool IsHrmPayable(string? sourceType) => sourceType is Advance or Reward or PenaltyTicket
        or TripAdvance or TripSettlement or TripRefund;

    public static string Label(string? sourceType) => sourceType switch
    {
        Payslip => "Phiếu lương",
        Advance => "Ứng lương",
        Reward => "Thưởng / phạt",
        PenaltyTicket => "Phiếu phạt",
        TripAdvance => "Ứng công tác",
        TripSettlement => "Quyết toán công tác phí",
        TripRefund => "Thu hoàn ứng công tác",
        PosSale => "Đơn bán hàng",
        PosDeposit => "Cọc đặt chỗ",
        PosDepositRefund => "Hoàn cọc đặt chỗ",
        PosPurchaseReceipt => "Phiếu nhập hàng",
        PosSupplierPayment => "Trả tiền nhà cung cấp",
        PosCustomerReturn => "Khách trả hàng",
        PosCustomerPayment => "Khách trả nợ",
        PosPurchaseReturnRefund => "Nhà cung cấp hoàn tiền",
        PosContract => "Thu tiền hợp đồng",
        _ => "",
    };

    /// <summary>Đọc (nguồn, mã) từ chuỗi đánh dấu cũ trong InternalNote.</summary>
    public static (string Type, Guid Id)? ParseNote(string? note)
    {
        if (string.IsNullOrWhiteSpace(note)) return null;
        foreach (var (marker, type) in Markers)
        {
            var i = note.IndexOf(marker, StringComparison.OrdinalIgnoreCase);
            if (i < 0) continue;
            var start = i + marker.Length;
            if (note.Length - start < 36) continue;
            if (Guid.TryParse(note.AsSpan(start, 36), out var id)) return (type, id);
        }
        return null;
    }

    /// <summary>Nguồn của phiếu: SourceType/SourceId chuẩn, không có thì đọc chuỗi đánh dấu cũ.</summary>
    public static (string Type, Guid Id)? Resolve(string? sourceType, Guid? sourceId, string? internalNote)
    {
        if (IsLinked(sourceType) && sourceId is Guid id) return (sourceType!, id);
        if (string.Equals(sourceType, Manual, StringComparison.OrdinalIgnoreCase)) return null;
        return ParseNote(internalNote);
    }
}
