using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Lịch sử duyệt từng cấp cho yêu cầu chỉnh công
/// </summary>
public class ApprovalRecord : Entity<Guid>
{
    /// <summary>
    /// ID yêu cầu chỉnh công
    /// </summary>
    [Required]
    public Guid CorrectionRequestId { get; set; }
    public virtual AttendanceCorrectionRequest? CorrectionRequest { get; set; }

    /// <summary>
    /// Bước duyệt (1, 2, 3...)
    /// </summary>
    public int StepOrder { get; set; }

    /// <summary>
    /// Tên hiển thị bước duyệt (vd: "Quản lý trực tiếp", "Giám đốc")
    /// </summary>
    [MaxLength(200)]
    public string? StepName { get; set; }

    /// <summary>
    /// Người được chỉ định duyệt bước này
    /// </summary>
    public Guid? AssignedUserId { get; set; }
    public virtual ApplicationUser? AssignedUser { get; set; }

    /// <summary>
    /// Tên người được chỉ định (cached)
    /// </summary>
    [MaxLength(200)]
    public string? AssignedUserName { get; set; }

    /// <summary>
    /// Người thực tế duyệt (có thể khác AssignedUser nếu ủy quyền)
    /// </summary>
    public Guid? ActualUserId { get; set; }
    public virtual ApplicationUser? ActualUser { get; set; }

    /// <summary>
    /// Tên người thực tế duyệt (cached)
    /// </summary>
    [MaxLength(200)]
    public string? ActualUserName { get; set; }

    /// <summary>
    /// Trạng thái bước duyệt
    /// </summary>
    public ApprovalStatus Status { get; set; } = ApprovalStatus.Pending;

    /// <summary>
    /// Ghi chú của người duyệt
    /// </summary>
    [MaxLength(1000)]
    public string? Note { get; set; }

    /// <summary>
    /// Thời điểm duyệt/từ chối
    /// </summary>
    public DateTime? ActionDate { get; set; }

    /// <summary>
    /// Cửa hàng
    /// </summary>
    public Guid? StoreId { get; set; }
}
