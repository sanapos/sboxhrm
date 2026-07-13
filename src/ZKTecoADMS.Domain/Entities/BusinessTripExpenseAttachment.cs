using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

public class BusinessTripExpenseAttachment : AuditableEntity<Guid>
{
    [Required]
    public Guid LineId { get; set; }
    public virtual BusinessTripExpenseLine? Line { get; set; }

    [Required]
    [MaxLength(300)]
    public string FileName { get; set; } = string.Empty;

    [Required]
    [MaxLength(1000)]
    public string FileUrl { get; set; } = string.Empty;

    [MaxLength(100)]
    public string? ContentType { get; set; }
    public long? FileSize { get; set; }

    public BusinessTripAttachmentType AttachmentType { get; set; } = BusinessTripAttachmentType.Invoice;

    public Guid? StoreId { get; set; }
}
