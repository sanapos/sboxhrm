using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Menu món ăn theo ngày và bữa
/// </summary>
public class MealMenu : AuditableEntity<Guid>
{
    [Required]
    public DateTime Date { get; set; }

    public DayOfWeek DayOfWeek { get; set; }

    [Required]
    public Guid MealSessionId { get; set; }
    public virtual MealSession MealSession { get; set; } = null!;

    [MaxLength(500)]
    public string? Note { get; set; }

    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }

    public virtual ICollection<MealMenuItem> Items { get; set; } = new List<MealMenuItem>();
}
