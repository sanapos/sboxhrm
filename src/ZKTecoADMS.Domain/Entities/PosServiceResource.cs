using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Khu vực phục vụ (tầng / khu bàn / khu ghế).</summary>
public class PosServiceArea : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    [MaxLength(100)]
    public string Name { get; set; } = string.Empty;

    [MaxLength(50)]
    public string? Code { get; set; }

    public int SortOrder { get; set; }

    [MaxLength(50)]
    public string? AreaType { get; set; }

    public virtual ICollection<PosServiceResource> Resources { get; set; } = [];
}

/// <summary>Ghế / bàn / phòng.</summary>
public class PosServiceResource : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    public Guid AreaId { get; set; }
    public virtual PosServiceArea? Area { get; set; }

    [Required]
    [MaxLength(50)]
    public string Code { get; set; } = string.Empty;

    [Required]
    [MaxLength(100)]
    public string Name { get; set; } = string.Empty;

    public PosResourceKind ResourceKind { get; set; } = PosResourceKind.Table;

    public int Capacity { get; set; } = 1;
    public int SortOrder { get; set; }

    /// <summary>Giá mặc định theo giờ (RoomHourly) — có thể ghi đè bằng SP dịch vụ.</summary>
    public decimal? DefaultHourlyRate { get; set; }

    /// <summary>SP dịch vụ tính giờ tự thêm khi mở bàn/phòng (ưu tiên hơn settings cửa hàng).</summary>
    public Guid? DefaultServiceProductId { get; set; }
    public virtual PosProduct? DefaultServiceProduct { get; set; }

    /// <summary>Vị trí trên sơ đồ (px logic, 0 = auto grid).</summary>
    public double? LayoutX { get; set; }
    public double? LayoutY { get; set; }
    public double LayoutW { get; set; } = 120;
    public double LayoutH { get; set; } = 100;

    /// <summary>Cần dọn sau khi khách ra (F&B).</summary>
    public bool NeedsCleaning { get; set; }

    /// <summary>Token công khai cho QR order tại bàn (URL /o/{token}).</summary>
    [MaxLength(32)]
    public string? QrOrderToken { get; set; }

    public virtual ICollection<PosResourceSession> Sessions { get; set; } = [];
}

/// <summary>Phiên mở bàn/phòng/ghế gắn đơn Draft.</summary>
public class PosResourceSession : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    public Guid ResourceId { get; set; }
    public virtual PosServiceResource? Resource { get; set; }

    public Guid? SaleOrderId { get; set; }
    public virtual PosSaleOrder? SaleOrder { get; set; }

    public Guid? CustomerId { get; set; }
    public virtual PosCustomer? Customer { get; set; }

    public DateTime StartedAt { get; set; }
    public DateTime? EndedAt { get; set; }
    public DateTime? PausedAt { get; set; }

    /// <summary>Tổng phút đã tạm dừng (cộng dồn).</summary>
    public int AccumulatedPauseMinutes { get; set; }

    public int GuestCount { get; set; } = 1;

    /// <summary>Khách xin thanh toán — tô màu ô trên sơ đồ.</summary>
    public bool BillRequested { get; set; }

    public PosResourceSessionStatus Status { get; set; } = PosResourceSessionStatus.Open;

    [MaxLength(500)]
    public string? Note { get; set; }
}

/// <summary>Đặt bàn trước — lưu khách + món đặt trước; khi đến mới mở phiên.</summary>
public class PosResourceReservation : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    public Guid ResourceId { get; set; }
    public virtual PosServiceResource? Resource { get; set; }

    public Guid? CustomerId { get; set; }
    public virtual PosCustomer? Customer { get; set; }

    [MaxLength(200)]
    public string CustomerName { get; set; } = string.Empty;

    [MaxLength(30)]
    public string? Phone { get; set; }

    public int GuestCount { get; set; } = 1;

    public DateTime ReservedAt { get; set; }

    public DateTime? ReservedUntil { get; set; }

    public PosResourceReservationStatus Status { get; set; } = PosResourceReservationStatus.Booked;

    /// <summary>JSON món đặt trước: [{productId,variantId,name,qty,unitPrice,note}].</summary>
    public string? PreOrderJson { get; set; }

    [MaxLength(500)]
    public string? Note { get; set; }

    public Guid? SeatedSessionId { get; set; }

    /// <summary>Số tiền cọc yêu cầu / dự kiến.</summary>
    public decimal DepositAmount { get; set; }

    /// <summary>Số tiền cọc đã thu.</summary>
    public decimal DepositPaid { get; set; }

    public PosReservationDepositStatus DepositStatus { get; set; } =
        PosReservationDepositStatus.None;

    [MaxLength(50)]
    public string? DepositPaymentMethod { get; set; }

    public DateTime? DepositPaidAt { get; set; }

    /// <summary>Đơn Draft/Completed đã trừ cọc (khi seat).</summary>
    public Guid? DepositAppliedOrderId { get; set; }

    /// <summary>
    /// Lịch hẹn có khung giờ (salon): ReservedAt = bắt đầu, ReservedUntil = kết thúc.
    /// Null/0 = đặt bàn cổ điển (1 Booked / resource).
    /// </summary>
    public int? DurationMinutes { get; set; }

    /// <summary>SP dịch vụ gắn lịch hẹn (cắt tóc, nail…).</summary>
    public Guid? ServiceProductId { get; set; }
    public virtual PosProduct? ServiceProduct { get; set; }

    /// <summary>NV phụ trách (stylist / kỹ thuật viên).</summary>
    public Guid? AssignedEmployeeId { get; set; }
    public virtual Employee? AssignedEmployee { get; set; }

    public bool IsTimedSlot => DurationMinutes is > 0;
}
