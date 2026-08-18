using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Nhóm hàng của catalog mẫu Super Admin (dùng chung mọi cửa hàng).
/// Khi cửa hàng adopt, CategoryName được copy sang PosProductCategory của store.
/// </summary>
public class PosProductSampleCategory : AuditableEntity<Guid>
{
    [Required]
    [MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    public Guid? ParentId { get; set; }
    public virtual PosProductSampleCategory? Parent { get; set; }
    public virtual ICollection<PosProductSampleCategory> Children { get; set; } = [];

    /// <summary>Gợi ý nhóm mẫu (Packaged/Food/Drink); null = dùng cho mọi loại.</summary>
    public PosProductSampleKind? Kind { get; set; }

    public int SortOrder { get; set; }

    public virtual ICollection<PosProductSampleCatalog> Samples { get; set; } = [];
}
