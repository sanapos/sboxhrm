using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Mapping ca làm việc ↔ bữa ăn (ca nào được ăn bữa nào)
/// </summary>
public class MealSessionShift : Entity<Guid>
{
    public Guid MealSessionId { get; set; }
    public virtual MealSession MealSession { get; set; } = null!;

    public Guid ShiftTemplateId { get; set; }
    public virtual ShiftTemplate ShiftTemplate { get; set; } = null!;
}
