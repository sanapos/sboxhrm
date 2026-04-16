using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Danh mục giao dịch thu chi
/// </summary>
public class TransactionCategory : AuditableEntity<Guid>
{
    /// <summary>
    /// Tên danh mục
    /// </summary>
    [Required]
    [MaxLength(100)]
    public string Name { get; set; } = string.Empty;

    /// <summary>
    /// Mô tả
    /// </summary>
    [MaxLength(500)]
    public string? Description { get; set; }

    /// <summary>
    /// Loại: Income (Thu) hoặc Expense (Chi)
    /// </summary>
    [Required]
    public CashTransactionType Type { get; set; }

    /// <summary>
    /// Icon name (Material Icons)
    /// </summary>
    [MaxLength(50)]
    public string? Icon { get; set; }

    /// <summary>
    /// Màu sắc (hex code)
    /// </summary>
    [MaxLength(10)]
    public string? Color { get; set; }

    /// <summary>
    /// Thứ tự sắp xếp
    /// </summary>
    public int SortOrder { get; set; } = 0;

    /// <summary>
    /// Danh mục cha (để phân cấp)
    /// </summary>
    public Guid? ParentCategoryId { get; set; }

    /// <summary>
    /// Cửa hàng sở hữu danh mục
    /// </summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }

    /// <summary>
    /// Là danh mục hệ thống (không xóa được)
    /// </summary>
    public bool IsSystem { get; set; } = false;

    // Navigation Properties
    public virtual TransactionCategory? ParentCategory { get; set; }
    public virtual ICollection<TransactionCategory> SubCategories { get; set; } = new List<TransactionCategory>();
    public virtual ICollection<CashTransaction> Transactions { get; set; } = new List<CashTransaction>();
}
