using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

public class PosQuoteLine : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    public Guid QuoteId { get; set; }
    public virtual PosQuote? Quote { get; set; }

    public Guid? ProductId { get; set; }
    public virtual PosProduct? Product { get; set; }

    [MaxLength(50)]
    public string? ProductCode { get; set; }

    [Required]
    [MaxLength(500)]
    public string ProductName { get; set; } = string.Empty;

    [MaxLength(100)]
    public string? UnitName { get; set; }

    public decimal Qty { get; set; } = 1;
    public decimal UnitPrice { get; set; }
    public decimal DiscountAmount { get; set; }
    public decimal VatRate { get; set; }
    public decimal LineTotal { get; set; }

    [MaxLength(500)]
    public string? LineNote { get; set; }

    public int SortOrder { get; set; }
}
