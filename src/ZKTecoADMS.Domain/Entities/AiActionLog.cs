using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Nhật ký thao tác của Trợ lý ảo: mỗi phiếu AI đề xuất (thêm / sửa / xóa / duyệt) là một dòng — ai yêu cầu, câu lệnh gốc,
/// nội dung sẽ gửi API, kết quả, mã chứng từ, cách hoàn tác. Đề xuất chờ xác nhận nằm ở đây nên khởi động lại máy chủ
/// không mất thẻ; bấm Xác nhận hai lần cũng chỉ ghi một lần (Status chuyển proposed → running nguyên tử).
/// </summary>
public class AiActionLog : Entity<Guid>
{
    public Guid StoreId { get; set; }

    /// <summary>Tài khoản yêu cầu (chỉ người này xác nhận / hoàn tác được).</summary>
    public Guid UserId { get; set; }

    [MaxLength(60)]
    public string Kind { get; set; } = string.Empty;

    [MaxLength(200)]
    public string Title { get; set; } = string.Empty;

    /// <summary>normal | high.</summary>
    [MaxLength(10)]
    public string Risk { get; set; } = "normal";

    /// <summary>Câu người dùng nói / gõ khi trợ lý lập phiếu.</summary>
    public string? Prompt { get; set; }

    /// <summary>Đề xuất đầy đủ (JSON) — dựng lại thẻ và lời gọi API khi xác nhận.</summary>
    public string PendingJson { get; set; } = string.Empty;

    /// <summary>proposed | running | done | failed | discarded | undoing | undone.</summary>
    [MaxLength(20)]
    public string Status { get; set; } = "proposed";

    public string? ResultMessage { get; set; }

    [MaxLength(60)]
    public string? DocNo { get; set; }

    [MaxLength(60)]
    public string? DocId { get; set; }

    /// <summary>Các bước hoàn tác (JSON) — null = không hoàn tác được.</summary>
    public string? UndoJson { get; set; }

    public DateTime? ExecutedAt { get; set; }

    public DateTime? UndoneAt { get; set; }
}
