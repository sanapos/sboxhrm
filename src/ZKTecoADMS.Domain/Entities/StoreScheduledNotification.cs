using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Thông báo quản lý hẹn giờ gửi cho nhân viên. Người nhận được tính lại vào lúc gửi.</summary>
public class StoreScheduledNotification : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }

    [Required]
    public Guid CreatedByUserId { get; set; }

    /// <summary>Giờ gửi (UTC).</summary>
    public DateTime SendAt { get; set; }

    /// <summary>Yêu cầu gửi gốc (JSON): tiêu đề, nội dung, loại, người nhận…</summary>
    [Required]
    public string PayloadJson { get; set; } = "{}";

    /// <summary>0 chờ gửi · 1 đang gửi · 2 đã gửi · 3 lỗi · 4 đã hủy.</summary>
    public int Status { get; set; }

    public DateTime? SentAt { get; set; }
    public Guid? BatchId { get; set; }

    [MaxLength(300)]
    public string? Error { get; set; }

    /// <summary>Tiêu đề tóm tắt để hiện trong danh sách.</summary>
    [MaxLength(200)]
    public string? Title { get; set; }

    public int RecipientCount { get; set; }
}
