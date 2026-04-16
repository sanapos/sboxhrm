using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Đăng ký lịch làm việc - Schedule Registration Request
/// </summary>
public class ScheduleRegistration : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }

    [Required]
    public Guid EmployeeUserId { get; set; }

    /// <summary>
    /// Ngày đăng ký
    /// </summary>
    [Required]
    public DateTime Date { get; set; }

    /// <summary>
    /// Ca làm việc đăng ký
    /// </summary>
    public Guid? ShiftId { get; set; }

    /// <summary>
    /// Đăng ký nghỉ phép?
    /// </summary>
    public bool IsDayOff { get; set; } = false;

    /// <summary>
    /// Ghi chú
    /// </summary>
    [MaxLength(500)]
    public string? Note { get; set; }

    /// <summary>
    /// Trạng thái đăng ký
    /// </summary>
    [Required]
    public ScheduleRegistrationStatus Status { get; set; } = ScheduleRegistrationStatus.Pending;

    /// <summary>
    /// Người duyệt
    /// </summary>
    public Guid? ApprovedById { get; set; }

    /// <summary>
    /// Ngày duyệt
    /// </summary>
    public DateTime? ApprovedDate { get; set; }

    /// <summary>
    /// Lý do từ chối (nếu có)
    /// </summary>
    [MaxLength(500)]
    public string? RejectionReason { get; set; }

    // Navigation Properties
    public virtual Store Store { get; set; } = null!;
    public virtual Employee Employee { get; set; } = null!;
    public virtual ShiftTemplate? Shift { get; set; }
    public virtual ApplicationUser? ApprovedBy { get; set; }
}
