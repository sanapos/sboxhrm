using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Phản ánh / Ý kiến - hỗ trợ ẩn danh hoặc công khai,
/// gửi cho quản lý cụ thể hoặc hòm thư chung
/// </summary>
public class Feedback : AuditableEntity<Guid>
{
    /// <summary>Người gửi (null nếu ẩn danh)</summary>
    public Guid? SenderEmployeeId { get; set; }
    public virtual Employee? SenderEmployee { get; set; }

    /// <summary>true = ẩn danh</summary>
    [Required]
    public bool IsAnonymous { get; set; }

    /// <summary>Người nhận - quản lý cụ thể (null = hòm thư chung)</summary>
    public Guid? RecipientEmployeeId { get; set; }
    public virtual Employee? RecipientEmployee { get; set; }

    /// <summary>Tiêu đề</summary>
    [Required]
    [MaxLength(300)]
    public string Title { get; set; } = string.Empty;

    /// <summary>Nội dung phản ánh</summary>
    [Required]
    [MaxLength(5000)]
    public string Content { get; set; } = string.Empty;

    /// <summary>Danh sách URL hình ảnh đính kèm (JSON)</summary>
    [MaxLength(2000)]
    public string? ImageUrls { get; set; }

    /// <summary>Phân loại: General, Complaint, Suggestion, Other</summary>
    [Required]
    [MaxLength(50)]
    public string Category { get; set; } = "General";

    /// <summary>Trạng thái: Pending, InProgress, Resolved, Closed</summary>
    [Required]
    [MaxLength(30)]
    public string Status { get; set; } = "Pending";

    /// <summary>Phản hồi từ quản lý</summary>
    [MaxLength(5000)]
    public string? Response { get; set; }

    /// <summary>Người phản hồi</summary>
    public Guid? RespondedByEmployeeId { get; set; }
    public virtual Employee? RespondedByEmployee { get; set; }

    /// <summary>Thời gian phản hồi</summary>
    public DateTime? RespondedAt { get; set; }

    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }

    /// <summary>Danh sách phản hồi qua lại</summary>
    public virtual ICollection<FeedbackReply> Replies { get; set; } = new List<FeedbackReply>();
}
