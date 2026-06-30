using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Định nghĩa thuộc tính hàng hóa (Màu sắc, Dung tích…).</summary>
public class PosProductAttribute : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    [MaxLength(100)]
    public string Name { get; set; } = string.Empty;

    public int SortOrder { get; set; }

    public virtual ICollection<PosProductAttributeValue> Values { get; set; } = [];
}
