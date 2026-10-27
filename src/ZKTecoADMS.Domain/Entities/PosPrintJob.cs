using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Hàng đợi in cloud — payload ESC/POS hoặc PDF.</summary>
public class PosPrintJob : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    public Guid PrinterId { get; set; }
    public virtual PosStorePrinter? Printer { get; set; }

    public Guid? AgentId { get; set; }
    public virtual PosPrintAgent? Agent { get; set; }

    public PosPrintDocumentType DocumentType { get; set; }

    [MaxLength(64)]
    public string? ReferenceNo { get; set; }

    public Guid? ReferenceId { get; set; }

    public PosPrintPayloadFormat PayloadFormat { get; set; } = PosPrintPayloadFormat.EscPosBase64;

    /// <summary>Base64 hoặc HTML tùy PayloadFormat.</summary>
    public string Payload { get; set; } = string.Empty;

    /// <summary>SHA-256 (hex) của Payload — chống in trùng mà không so cả chuỗi lớn trong SQL.</summary>
    public string? PayloadHash { get; set; }

    /// <summary>Agent nhả job gần nhất — ClaimNext không giao lại cho chính Agent đó trong 60s
    /// (trước đây nhả → nhận lại → nhả… liên tục giữa các Agent).</summary>
    public Guid? ReleasedByAgentId { get; set; }

    public DateTime? ReleasedAt { get; set; }

    public int Copies { get; set; } = 1;

    public PosPrintJobStatus Status { get; set; } = PosPrintJobStatus.Queued;

    [MaxLength(450)]
    public string? RequestedByUserId { get; set; }

    [MaxLength(200)]
    public string? RequestedByName { get; set; }

    public DateTime? ClaimedAt { get; set; }

    public DateTime? StartedAt { get; set; }

    public DateTime? CompletedAt { get; set; }

    [MaxLength(64)]
    public string? ErrorCode { get; set; }

    [MaxLength(500)]
    public string? ErrorMessage { get; set; }

    public int AttemptCount { get; set; }

    /// <summary>Mã chống trùng của máy gửi — gửi lại do lỗi mạng trả về đúng job này.</summary>
    [MaxLength(64)]
    public string? ClientRequestId { get; set; }

    public DateTime ExpiresAt { get; set; }

    /// <summary>Phiếu bếp server tự gửi (QR / online / Tingee): các dòng món đã đánh dấu «đã báo bếp» theo
    /// lệnh này — JSON [{"l":lineId,"q":qty}]. Lệnh hủy / lỗi mà chắc chắn chưa in → trả món về «chưa báo bếp».</summary>
    public string? KitchenLinesJson { get; set; }

    /// <summary>Đã trả các dòng món về «chưa báo bếp» (In lại / báo in xong muộn → đánh dấu lại).</summary>
    public bool KitchenLinesReverted { get; set; }
}
