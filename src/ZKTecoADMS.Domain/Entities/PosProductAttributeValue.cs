using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Giá trị thuộc tính của từng hàng hóa.</summary>
public class PosProductAttributeValue : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    public Guid ProductId { get; set; }
    public virtual PosProduct? Product { get; set; }

    [Required]
    public Guid AttributeId { get; set; }
    public virtual PosProductAttribute? Attribute { get; set; }

    [Required]
    [MaxLength(500)]
    public string Value { get; set; } = string.Empty;
}
