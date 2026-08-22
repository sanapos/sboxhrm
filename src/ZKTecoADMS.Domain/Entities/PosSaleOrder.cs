using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Đơn bán hàng POS.</summary>
public class PosSaleOrder : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    [MaxLength(30)]
    public string OrderNo { get; set; } = string.Empty;

    public PosSaleOrderStatus Status { get; set; } = PosSaleOrderStatus.Completed;

    public decimal SubTotal { get; set; }
    public decimal Discount { get; set; }
    public decimal Total { get; set; }
    /// <summary>Tiền VAT của đơn (tính theo cấu hình POS lúc tạo/hoàn tất).</summary>
    public decimal VatAmount { get; set; }
    /// <summary>Phụ thu (tiền hoặc % trên màn thanh toán — chỉ khi cửa hàng bật).</summary>
    public decimal SurchargeAmount { get; set; }
    /// <summary>Phí giao hàng (số tiền — chỉ khi cửa hàng bật).</summary>
    public decimal DeliveryFee { get; set; }
    /// <summary>Số tiền khách phải trả = hàng + VAT + phụ thu + phí GH.</summary>
    public decimal PayableTotal => Math.Max(0m,
        Total + Math.Max(0m, VatAmount) + Math.Max(0m, SurchargeAmount) + Math.Max(0m, DeliveryFee));
    public decimal PaidAmount { get; set; }

    [MaxLength(50)]
    public string PaymentMethod { get; set; } = "Tiền mặt";

    [MaxLength(200)]
    public string? CustomerName { get; set; }

    public Guid? CustomerId { get; set; }
    public virtual PosCustomer? Customer { get; set; }

    public bool IsDelivery { get; set; }

    [MaxLength(500)]
    public string? DeliveryAddress { get; set; }

    [MaxLength(50)]
    public string? DeliveryPhone { get; set; }

    [MaxLength(100)]
    public string? DeliveryPartner { get; set; }

    [MaxLength(100)]
    public string? DeliveryProvince { get; set; }

    [MaxLength(100)]
    public string? DeliveryDistrict { get; set; }

    [MaxLength(100)]
    public string? DeliveryWard { get; set; }

    [MaxLength(50)]
    public string? DeliveryStatus { get; set; }

    public DateTime? DeliveryDate { get; set; }

    /// <summary>Mã vận đơn / tracking (GHN order_code, GHTK label_id…).</summary>
    [MaxLength(80)]
    public string? DeliveryTrackingCode { get; set; }

    /// <summary>Id đơn phía hãng (AhaMove order_id…).</summary>
    [MaxLength(120)]
    public string? DeliveryCarrierOrderId { get; set; }

    /// <summary>Ghn | Ghtk | ViettelPost | Ahamove — mã kỹ thuật đã đẩy API.</summary>
    [MaxLength(30)]
    public string? DeliveryCarrierCode { get; set; }

    [MaxLength(500)]
    public string? DeliveryLabelUrl { get; set; }

    [MaxLength(500)]
    public string? Note { get; set; }

    public DateTime? SaleDate { get; set; }

    [MaxLength(200)]
    public string? SoldBy { get; set; }

    public Guid? SoldByEmployeeId { get; set; }

    [MaxLength(100)]
    public string? SalesChannel { get; set; }

    [MaxLength(100)]
    public string? PriceListName { get; set; }

    /// <summary>Số lần đã in hóa đơn (lần 1 = in mới, >1 = in lại).</summary>
    public int PrintCount { get; set; }

    public DateTime? LastPrintedAt { get; set; }

    public Guid? PriceListId { get; set; }
    public virtual PosPriceList? PriceList { get; set; }

    public Guid? VoucherId { get; set; }
    public virtual PosVoucher? Voucher { get; set; }

    [MaxLength(50)]
    public string? VoucherCode { get; set; }

    public decimal VoucherDiscount { get; set; }

    public decimal PointsRedeemed { get; set; }

    public decimal PointsDiscount { get; set; }

    public decimal PointsEarned { get; set; }

    /// <summary>Bàn / phòng / ghế gắn đơn (F&amp;B, karaoke, salon).</summary>
    public Guid? ServiceResourceId { get; set; }
    public virtual PosServiceResource? ServiceResource { get; set; }

    public Guid? ResourceSessionId { get; set; }
    public virtual PosResourceSession? ResourceSession { get; set; }

    /// <summary>
    /// Đơn tách bill từ đơn bàn này. Thanh toán không đóng phiên / không xóa draft còn lại trên bàn.
    /// </summary>
    public Guid? SplitFromOrderId { get; set; }

    public DateTime? ServiceStartedAt { get; set; }
    public DateTime? ServiceEndedAt { get; set; }

    /// <summary>Optimistic concurrency cho Draft — tăng mỗi claim/save/complete.</summary>
    public int LockVersion { get; set; }

    public Guid? LockedByUserId { get; set; }
    public Guid? LockedByEmployeeId { get; set; }

    [MaxLength(200)]
    public string? LockedByDisplayName { get; set; }

    [MaxLength(80)]
    public string? LockedByDeviceId { get; set; }

    [MaxLength(120)]
    public string? LockedByDeviceName { get; set; }

    public DateTime? LockedAt { get; set; }
    public DateTime? LockExpiresAt { get; set; }

    /// <summary>
    /// Slot hóa đơn cố định trên POS (1..N). Chỉ gắn Draft.
    /// Null khi đã thanh toán — mã OrderNo thật (HDxxxx) gán lúc Complete.
    /// </summary>
    public int? InvoiceSlot { get; set; }

    /// <summary>None | Skipped | Pending | Issued | Failed</summary>
    [MaxLength(20)]
    public string EInvoiceStatus { get; set; } = "None";

    [MaxLength(20)]
    public string? EInvoiceProvider { get; set; }

    [MaxLength(36)]
    public string? EInvoiceTransactionUuid { get; set; }

    [MaxLength(30)]
    public string? EInvoiceNo { get; set; }

    [MaxLength(25)]
    public string? EInvoiceSeries { get; set; }

    [MaxLength(50)]
    public string? EInvoiceReservationCode { get; set; }

    [MaxLength(50)]
    public string? EInvoiceCode { get; set; }

    public DateTime? EInvoiceIssuedAt { get; set; }

    [MaxLength(1000)]
    public string? EInvoiceError { get; set; }

    [MaxLength(200)]
    public string? EInvoiceBuyerName { get; set; }

    /// <summary>Tên doanh nghiệp / đơn vị mua (Easy CusName) — khác Tên người mua hàng.</summary>
    [MaxLength(200)]
    public string? EInvoiceBuyerCompanyName { get; set; }

    [MaxLength(50)]
    public string? EInvoiceBuyerTaxCode { get; set; }

    [MaxLength(500)]
    public string? EInvoiceBuyerAddress { get; set; }

    [MaxLength(200)]
    public string? EInvoiceBuyerEmail { get; set; }

    [MaxLength(50)]
    public string? EInvoiceBuyerPhone { get; set; }

    public virtual ICollection<PosSaleOrderLine> Lines { get; set; } = [];
}
