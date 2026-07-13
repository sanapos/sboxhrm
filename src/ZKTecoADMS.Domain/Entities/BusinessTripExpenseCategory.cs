using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

public class BusinessTripExpenseCategory : AuditableEntity<Guid>
{
    public Guid? StoreId { get; set; }

    [Required]
    [MaxLength(50)]
    public string Code { get; set; } = string.Empty;

    [Required]
    [MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    [MaxLength(500)]
    public string? Description { get; set; }

    public decimal? MaxAmountPerLine { get; set; }
    public decimal? MaxAmountPerMonth { get; set; }
    public bool RequiresInvoice { get; set; }
    public int SortOrder { get; set; }
}
