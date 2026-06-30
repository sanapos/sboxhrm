using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Nhóm hàng POS (cây phân cấp tùy chọn).</summary>
public class PosProductCategory : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    public Guid? ParentId { get; set; }
    public virtual PosProductCategory? Parent { get; set; }
    public virtual ICollection<PosProductCategory> Children { get; set; } = [];

    [Required]
    [MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    public int SortOrder { get; set; }

    public virtual ICollection<PosProduct> Products { get; set; } = [];
}
