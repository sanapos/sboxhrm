using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Master dish list - danh sách món ăn cố định trong hệ thống
/// </summary>
public class MealDish : AuditableEntity<Guid>
{
    [Required]
    [MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    [MaxLength(100)]
    public string? Category { get; set; }

    public int SortOrder { get; set; }

    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }
}
