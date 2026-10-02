using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Kênh truyền thông nội bộ (Bảng tin, Thông báo, Nội quy & chính sách, Nhân sự, Sự kiện, Đào tạo, Tài liệu,
/// kênh chi nhánh / nhóm). Quyết định ai được đăng và có cần duyệt.
/// </summary>
public class CommChannel : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }

    /// <summary>Khóa ổn định cho kênh hệ thống (feed, announcement, policy, hr, event, training, docs, culture)</summary>
    [MaxLength(40)]
    public string? Key { get; set; }

    [Required]
    [MaxLength(120)]
    public string Name { get; set; } = string.Empty;

    [MaxLength(500)]
    public string? Description { get; set; }

    [MaxLength(40)]
    public string? Icon { get; set; }

    [MaxLength(9)]
    public string? Color { get; set; }

    /// <summary>0 = mọi nhân viên được đăng, 1 = chỉ quản lý / người được chỉ định</summary>
    public int PostPolicy { get; set; }

    /// <summary>Bài của nhân viên cần quản lý duyệt trước khi hiện</summary>
    public bool RequireApproval { get; set; }

    /// <summary>Kênh riêng một chi nhánh (null = toàn công ty)</summary>
    public Guid? BranchId { get; set; }

    /// <summary>Kênh riêng phòng ban (null = không giới hạn)</summary>
    public Guid? DepartmentId { get; set; }

    public int SortOrder { get; set; }

    public bool IsSystem { get; set; }
}

/// <summary>Lượt xem / xác nhận đã đọc của từng người (thay cho chỉ đếm ViewCount).</summary>
public class CommunicationRead : Entity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }

    [Required]
    public Guid CommunicationId { get; set; }

    [Required]
    public Guid UserId { get; set; }

    public Guid? EmployeeId { get; set; }

    public DateTime FirstViewedAt { get; set; } = DateTime.UtcNow;
    public DateTime LastViewedAt { get; set; } = DateTime.UtcNow;
    public int ViewCount { get; set; } = 1;

    /// <summary>Thời điểm bấm «Tôi đã đọc và cam kết»</summary>
    public DateTime? AcknowledgedAt { get; set; }

    /// <summary>Phiên bản bài lúc xác nhận — bài lên phiên bản mới thì phải xác nhận lại</summary>
    public int AckVersion { get; set; }

    public virtual InternalCommunication? Communication { get; set; }
}

/// <summary>Phiếu bình chọn.</summary>
public class CommunicationPollVote : Entity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }

    [Required]
    public Guid CommunicationId { get; set; }

    [Required]
    public Guid UserId { get; set; }

    [Required]
    [MaxLength(40)]
    public string OptionId { get; set; } = string.Empty;
}

/// <summary>Bài đã lưu của người dùng.</summary>
public class CommunicationBookmark : Entity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }

    [Required]
    public Guid CommunicationId { get; set; }

    [Required]
    public Guid UserId { get; set; }
}

/// <summary>Lượt thích bình luận (mỗi người một lượt).</summary>
public class CommunicationCommentLike : Entity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }

    [Required]
    public Guid CommentId { get; set; }

    [Required]
    public Guid UserId { get; set; }
}
