using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Lịch chăm sóc / làm việc với khách trên từng báo giá.</summary>
public class PosQuoteActivity : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }

    [Required]
    public Guid QuoteId { get; set; }
    public virtual PosQuote? Quote { get; set; }

    /// <summary>Created, Edit, Call, Note, Meeting, FollowUp, Status.</summary>
    [Required]
    [MaxLength(30)]
    public string Kind { get; set; } = "Note";

    [Required]
    [MaxLength(2000)]
    public string Content { get; set; } = string.Empty;

    public DateTime? NextFollowUpAt { get; set; }

    public Guid? EmployeeId { get; set; }

    /// <summary>Độ tiềm năng khách tại lần chăm sóc này, thang 0–10.</summary>
    public int? PotentialScore { get; set; }
}
