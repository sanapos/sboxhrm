using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Thư mục/danh mục nội dung (Nội quy, Đào tạo...)
/// </summary>
public class ContentCategory : Entity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }

    [Required]
    [MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    [MaxLength(500)]
    public string? Description { get; set; }

    /// <summary>
    /// Loại nội dung mà thư mục này thuộc về
    /// </summary>
    [Required]
    public CommunicationType ContentType { get; set; }

    /// <summary>
    /// Icon name (Material Icons)
    /// </summary>
    [MaxLength(100)]
    public string? IconName { get; set; }

    /// <summary>
    /// Màu sắc HEX
    /// </summary>
    [MaxLength(10)]
    public string? Color { get; set; }

    /// <summary>
    /// Thứ tự hiển thị
    /// </summary>
    public int DisplayOrder { get; set; } = 0;

    /// <summary>
    /// Thư mục cha (hỗ trợ cấu trúc cây)
    /// </summary>
    public Guid? ParentCategoryId { get; set; }

    public bool IsActive { get; set; } = true;

    // Navigation
    public virtual Store? Store { get; set; }
    public virtual ContentCategory? ParentCategory { get; set; }
    public virtual ICollection<ContentCategory> SubCategories { get; set; } = new List<ContentCategory>();
}
