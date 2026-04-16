using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Phiếu phạt - tự động tạo khi nhân viên đi trễ/về sớm
/// Nếu không hủy trước ngày hôm sau → tự động duyệt → tạo phiếu thu
/// </summary>
public class PenaltyTicket : AuditableEntity<Guid>
{
    /// <summary>
    /// Mã phiếu phạt (tự động: PP-YYYYMMDD-XXXX)
    /// </summary>
    [Required]
    [MaxLength(50)]
    public string TicketCode { get; set; } = string.Empty;

    /// <summary>
    /// Nhân viên bị phạt
    /// </summary>
    [Required]
    public Guid EmployeeId { get; set; }

    /// <summary>
    /// Loại phạt
    /// </summary>
    [Required]
    public PenaltyTicketType Type { get; set; }

    /// <summary>
    /// Trạng thái phiếu
    /// </summary>
    [Required]
    public PenaltyTicketStatus Status { get; set; } = PenaltyTicketStatus.Pending;

    /// <summary>
    /// Số tiền phạt (VND)
    /// </summary>
    [Required]
    public decimal Amount { get; set; }

    /// <summary>
    /// Ngày vi phạm
    /// </summary>
    [Required]
    public DateTime ViolationDate { get; set; }

    /// <summary>
    /// Số phút đi trễ / về sớm
    /// </summary>
    public int? MinutesLateOrEarly { get; set; }

    /// <summary>
    /// Giờ ca bắt đầu (thực tế)
    /// </summary>
    public TimeSpan? ShiftStartTime { get; set; }

    /// <summary>
    /// Giờ ca kết thúc (thực tế)
    /// </summary>
    public TimeSpan? ShiftEndTime { get; set; }

    /// <summary>
    /// Giờ chấm công thực tế (check-in hoặc check-out)
    /// </summary>
    public DateTime? ActualPunchTime { get; set; }

    /// <summary>
    /// Bậc phạt áp dụng (1, 2, 3)
    /// </summary>
    public int PenaltyTier { get; set; } = 1;

    /// <summary>
    /// Số lần tái phạm trong tháng (nếu là phạt tái phạm)
    /// </summary>
    public int? RepeatCountInMonth { get; set; }

    /// <summary>
    /// Mô tả tự động
    /// </summary>
    [MaxLength(500)]
    public string? Description { get; set; }

    /// <summary>
    /// Lý do hủy (nếu manager hủy phạt)
    /// </summary>
    [MaxLength(500)]
    public string? CancellationReason { get; set; }

    /// <summary>
    /// Người duyệt/hủy
    /// </summary>
    public Guid? ProcessedById { get; set; }

    /// <summary>
    /// Ngày duyệt/hủy
    /// </summary>
    public DateTime? ProcessedDate { get; set; }

    /// <summary>
    /// ID phiếu thu tạo ra (khi duyệt)
    /// </summary>
    public Guid? CashTransactionId { get; set; }

    /// <summary>
    /// Liên kết ca làm việc
    /// </summary>
    public Guid? ShiftId { get; set; }

    /// <summary>
    /// Liên kết chấm công
    /// </summary>
    public Guid? AttendanceId { get; set; }

    /// <summary>
    /// Cửa hàng
    /// </summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }

    // Navigation properties
    public virtual Employee Employee { get; set; } = null!;
    public virtual ApplicationUser? ProcessedBy { get; set; }
    public virtual CashTransaction? CashTransaction { get; set; }
    public virtual Shift? Shift { get; set; }
    public virtual Attendance? Attendance { get; set; }
}
