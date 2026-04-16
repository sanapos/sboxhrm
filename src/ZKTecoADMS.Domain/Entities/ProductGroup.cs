using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Nhóm sản phẩm - dùng để phân loại sản phẩm tính lương theo sản lượng
/// </summary>
public class ProductGroup : AuditableEntity<Guid>
{
    [Required, MaxLength(100)]
    public string Name { get; set; } = string.Empty;

    [MaxLength(500)]
    public string? Description { get; set; }

    public int SortOrder { get; set; }

    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }

    public virtual ICollection<ProductItem> Products { get; set; } = new List<ProductItem>();
}
