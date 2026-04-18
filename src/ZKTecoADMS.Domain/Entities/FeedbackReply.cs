using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Phản hồi qua lại trong cuộc hội thoại phản ánh / ý kiến
/// </summary>
public class FeedbackReply : Entity<Guid>
{
    /// <summary>Phản ánh gốc</summary>
    [Required]
    public Guid FeedbackId { get; set; }
    public virtual Feedback? Feedback { get; set; }

    /// <summary>Người gửi reply</summary>
    public Guid? SenderEmployeeId { get; set; }
    public virtual Employee? SenderEmployee { get; set; }

    /// <summary>Nội dung phản hồi</summary>
    [Required]
    [MaxLength(5000)]
    public string Content { get; set; } = string.Empty;

    /// <summary>Danh sách URL hình ảnh đính kèm (JSON)</summary>
    [MaxLength(2000)]
    public string? ImageUrls { get; set; }

    /// <summary>true = người gửi phản ánh gốc, false = người được gửi (quản lý)</summary>
    public bool IsFromSender { get; set; }

    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }
}
