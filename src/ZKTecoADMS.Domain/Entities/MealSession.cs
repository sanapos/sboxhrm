using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Định nghĩa bữa ăn theo khung giờ (Bữa trưa, Bữa tối...)
/// </summary>
public class MealSession : AuditableEntity<Guid>
{
    [Required]
    [MaxLength(100)]
    public string Name { get; set; } = string.Empty;

    [Required]
    public TimeSpan StartTime { get; set; }

    [Required]
    public TimeSpan EndTime { get; set; }

    [MaxLength(500)]
    public string? Description { get; set; }

    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }

    public virtual ICollection<MealSessionShift> MealSessionShifts { get; set; } = new List<MealSessionShift>();
    public virtual ICollection<MealMenu> MealMenus { get; set; } = new List<MealMenu>();
    public virtual ICollection<MealRecord> MealRecords { get; set; } = new List<MealRecord>();
}
