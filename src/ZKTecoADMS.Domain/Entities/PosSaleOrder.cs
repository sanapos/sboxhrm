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
    /// <summary>Số tiền khách phải trả = Total + VatAmount (VAT cộng thêm).</summary>
    public decimal PayableTotal => Math.Max(0m, Total + Math.Max(0m, VatAmount));
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

    [MaxLength(50)]
    public string? DeliveryStatus { get; set; }

    public DateTime? DeliveryDate { get; set; }

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

    public virtual ICollection<PosSaleOrderLine> Lines { get; set; } = [];
}
