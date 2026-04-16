using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Lịch sử duyệt từng cấp cho đơn nghỉ phép
/// </summary>
public class LeaveApprovalRecord : Entity<Guid>
{
    [Required]
    public Guid LeaveId { get; set; }
    public virtual Leave? Leave { get; set; }

    public int StepOrder { get; set; }

    [MaxLength(200)]
    public string? StepName { get; set; }

    public Guid? AssignedUserId { get; set; }
    public virtual ApplicationUser? AssignedUser { get; set; }

    [MaxLength(200)]
    public string? AssignedUserName { get; set; }

    public Guid? ActualUserId { get; set; }
    public virtual ApplicationUser? ActualUser { get; set; }

    [MaxLength(200)]
    public string? ActualUserName { get; set; }

    public ApprovalStatus Status { get; set; } = ApprovalStatus.Pending;

    [MaxLength(1000)]
    public string? Note { get; set; }

    public DateTime? ActionDate { get; set; }

    public Guid? StoreId { get; set; }
}
