using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Món ăn cụ thể trong menu
/// </summary>
public class MealMenuItem : Entity<Guid>
{
    [Required]
    public Guid MealMenuId { get; set; }
    public virtual MealMenu MealMenu { get; set; } = null!;

    [Required]
    [MaxLength(200)]
    public string DishName { get; set; } = string.Empty;

    [MaxLength(500)]
    public string? Description { get; set; }

    [MaxLength(100)]
    public string? Category { get; set; }

    public int SortOrder { get; set; }
}
