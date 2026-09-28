using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Truyền thông nội bộ - Internal Communication
/// </summary>
public class InternalCommunication : Entity<Guid>
{
    /// <summary>
    /// ID cửa hàng/công ty
    /// </summary>
    [Required]
    public Guid StoreId { get; set; }

    /// <summary>
    /// Tiêu đề bài viết
    /// </summary>
    [Required]
    [MaxLength(500)]
    public string Title { get; set; } = string.Empty;

    /// <summary>
    /// Nội dung bài viết (HTML hoặc plain text)
    /// </summary>
    [Required]
    public string Content { get; set; } = string.Empty;

    /// <summary>
    /// Tóm tắt ngắn
    /// </summary>
    [MaxLength(1000)]
    public string? Summary { get; set; }

    /// <summary>
    /// Ảnh đại diện/thumbnail
    /// </summary>
    [MaxLength(1000)]
    public string? ThumbnailUrl { get; set; }

    /// <summary>
    /// Danh sách ảnh đính kèm (JSON array of URLs)
    /// </summary>
    public string? AttachedImages { get; set; }

    /// <summary>
    /// Loại bài viết
    /// </summary>
    [Required]
    public CommunicationType Type { get; set; } = CommunicationType.News;

    /// <summary>
    /// Ưu tiên/độ quan trọng
    /// </summary>
    public CommunicationPriority Priority { get; set; } = CommunicationPriority.Normal;

    /// <summary>
    /// Trạng thái bài viết
    /// </summary>
    public CommunicationStatus Status { get; set; } = CommunicationStatus.Draft;

    /// <summary>
    /// Người tạo bài viết
    /// </summary>
    [Required]
    public Guid AuthorId { get; set; }

    /// <summary>
    /// Tên tác giả (cache)
    /// </summary>
    [MaxLength(200)]
    public string? AuthorName { get; set; }

    /// <summary>
    /// ID phòng ban (null = toàn công ty)
    /// </summary>
    public Guid? TargetDepartmentId { get; set; }

    /// <summary>
    /// Ngày xuất bản
    /// </summary>
    public DateTime? PublishedAt { get; set; }

    /// <summary>
    /// Ngày hết hiệu lực (null = không hết hạn)
    /// </summary>
    public DateTime? ExpiresAt { get; set; }

    /// <summary>
    /// Số lượt xem
    /// </summary>
    public int ViewCount { get; set; } = 0;

    /// <summary>
    /// Số lượt thích
    /// </summary>
    public int LikeCount { get; set; } = 0;

    /// <summary>
    /// Có ghim lên đầu không
    /// </summary>
    public bool IsPinned { get; set; } = false;

    /// <summary>
    /// Bài viết được tạo bởi AI
    /// </summary>
    public bool IsAiGenerated { get; set; } = false;

    /// <summary>
    /// Prompt AI đã dùng để tạo bài viết
    /// </summary>
    [MaxLength(2000)]
    public string? AiPrompt { get; set; }

    /// <summary>
    /// Tags/từ khóa (comma separated)
    /// </summary>
    [MaxLength(500)]
    public string? Tags { get; set; }

    /// <summary>
    /// ID thư mục/danh mục
    /// </summary>
    public Guid? CategoryId { get; set; }

    /// <summary>
    /// Cho phép xem bài qua link công khai (không cần đăng nhập).
    /// </summary>
    public bool IsPublicShareEnabled { get; set; }

    /// <summary>
    /// Token ngẫu nhiên trong URL chia sẻ (/share/{token}).
    /// </summary>
    [MaxLength(64)]
    public string? PublicShareToken { get; set; }

    // ─── Truyền thông v2 (mạng xã hội nội bộ) ───

    /// <summary>Kênh đăng bài</summary>
    public Guid? ChannelId { get; set; }

    /// <summary>"html" = bài soạn bằng trình soạn thảo mới; null = văn bản cũ</summary>
    [MaxLength(10)]
    public string? ContentFormat { get; set; }

    /// <summary>Nội dung dạng Quill Delta (JSON) để mở lại trình soạn thảo giữ nguyên định dạng</summary>
    public string? ContentDelta { get; set; }

    /// <summary>JSON: [{"url","name","mime","size","kind"}] — ảnh, Word, PDF, Excel…</summary>
    public string? Attachments { get; set; }

    /// <summary>Bắt buộc bấm «Tôi đã đọc và cam kết»</summary>
    public bool RequireAck { get; set; }

    public DateTime? AckDeadline { get; set; }

    /// <summary>Phiên bản văn bản (nội quy/chính sách) — tăng khi cập nhật, phải xác nhận lại</summary>
    public int Version { get; set; } = 1;

    /// <summary>JSON đối tượng nhận: {"all":true} hoặc {"branchIds":[],"departmentIds":[],"positions":[],"employeeIds":[]}</summary>
    public string? Audience { get; set; }

    /// <summary>JSON bình chọn: {"question","options":[{"id","text"}],"multiple":false,"closesAt":null,"anonymous":false}</summary>
    public string? Poll { get; set; }

    public DateTime? EventAt { get; set; }

    [MaxLength(300)]
    public string? EventLocation { get; set; }

    /// <summary>Đăng hẹn giờ (dịch vụ nền xuất bản khi đến giờ)</summary>
    public DateTime? ScheduledAt { get; set; }

    public bool AllowComments { get; set; } = true;

    public virtual CommChannel? Channel { get; set; }

    // Navigation properties
    public virtual Store? Store { get; set; }
    public virtual ApplicationUser? Author { get; set; }
    public virtual Department? TargetDepartment { get; set; }
    public virtual ContentCategory? Category { get; set; }
    public virtual ICollection<CommunicationComment> Comments { get; set; } = new List<CommunicationComment>();
    public virtual ICollection<CommunicationReaction> Reactions { get; set; } = new List<CommunicationReaction>();
}

/// <summary>
/// Bình luận bài viết
/// </summary>
public class CommunicationComment : Entity<Guid>
{
    [Required]
    public Guid CommunicationId { get; set; }

    [Required]
    public Guid UserId { get; set; }

    [MaxLength(200)]
    public string? UserName { get; set; }

    [Required]
    [MaxLength(2000)]
    public string Content { get; set; } = string.Empty;

    public Guid? ParentCommentId { get; set; }

    public int LikeCount { get; set; } = 0;

    // Navigation
    public virtual InternalCommunication? Communication { get; set; }
    public virtual CommunicationComment? ParentComment { get; set; }
    public virtual ICollection<CommunicationComment> Replies { get; set; } = new List<CommunicationComment>();
}

/// <summary>
/// Reaction/Like bài viết
/// </summary>
public class CommunicationReaction : Entity<Guid>
{
    [Required]
    public Guid CommunicationId { get; set; }

    [Required]
    public Guid UserId { get; set; }

    public ReactionType ReactionType { get; set; } = ReactionType.Like;

    // Navigation
    public virtual InternalCommunication? Communication { get; set; }
}
