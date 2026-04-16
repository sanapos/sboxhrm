using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Đơn đăng ký tăng ca
/// </summary>
public class Overtime : AuditableEntity<Guid>
{
    /// <summary>
    /// Nhân viên đăng ký tăng ca
    /// </summary>
    [Required]
    public Guid EmployeeUserId { get; set; }

    /// <summary>
    /// Quản lý phê duyệt
    /// </summary>
    [Required]
    public Guid ManagerId { get; set; }

    /// <summary>
    /// Loại tăng ca
    /// </summary>
    [Required]
    public OvertimeType Type { get; set; }

    /// <summary>
    /// Ngày tăng ca
    /// </summary>
    [Required]
    public DateTime Date { get; set; }

    /// <summary>
    /// Thời gian bắt đầu tăng ca
    /// </summary>
    [Required]
    public TimeSpan StartTime { get; set; }

    /// <summary>
    /// Thời gian kết thúc tăng ca
    /// </summary>
    [Required]
    public TimeSpan EndTime { get; set; }

    /// <summary>
    /// Số giờ tăng ca dự kiến
    /// </summary>
    public decimal PlannedHours { get; set; }

    /// <summary>
    /// Số giờ tăng ca thực tế (sau khi chấm công)
    /// </summary>
    public decimal? ActualHours { get; set; }

    /// <summary>
    /// Hệ số lương tăng ca
    /// </summary>
    public decimal Multiplier { get; set; } = 1.5m;

    /// <summary>
    /// Lý do tăng ca
    /// </summary>
    [Required]
    [MaxLength(1000)]
    public string Reason { get; set; } = string.Empty;

    /// <summary>
    /// Nội dung công việc tăng ca
    /// </summary>
    [MaxLength(2000)]
    public string? WorkContent { get; set; }

    /// <summary>
    /// Trạng thái đơn
    /// </summary>
    [Required]
    public OvertimeStatus Status { get; set; } = OvertimeStatus.Pending;

    /// <summary>
    /// Lý do từ chối (nếu bị từ chối)
    /// </summary>
    [MaxLength(500)]
    public string? RejectionReason { get; set; }

    /// <summary>
    /// Thời điểm phê duyệt
    /// </summary>
    public DateTime? ApprovedAt { get; set; }

    /// <summary>
    /// Ghi chú
    /// </summary>
    [MaxLength(500)]
    public string? Note { get; set; }

    /// <summary>
    /// Cửa hàng mà đơn tăng ca thuộc về
    /// </summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }

    // Navigation Properties
    public virtual ApplicationUser EmployeeUser { get; set; } = null!;
    public virtual ApplicationUser Manager { get; set; } = null!;
}
