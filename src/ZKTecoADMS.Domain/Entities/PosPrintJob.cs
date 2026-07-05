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

    public DateTime ExpiresAt { get; set; }
}
