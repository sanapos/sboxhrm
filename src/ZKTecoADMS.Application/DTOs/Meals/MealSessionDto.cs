namespace ZKTecoADMS.Application.DTOs.Meals;

public class MealSessionDto
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public TimeSpan StartTime { get; set; }
    public TimeSpan EndTime { get; set; }
    public string? Description { get; set; }
    public bool IsActive { get; set; }
    public Guid? StoreId { get; set; }
    public DateTime CreatedAt { get; set; }
    public List<MealSessionShiftDto> MealSessionShifts { get; set; } = [];
}

public class MealSessionShiftDto
{
    public Guid Id { get; set; }
    public Guid MealSessionId { get; set; }
    public Guid ShiftTemplateId { get; set; }
    public string? ShiftTemplateName { get; set; }
}

public class CreateMealSessionRequest
{
    public string Name { get; set; } = string.Empty;
    public TimeSpan StartTime { get; set; }
    public TimeSpan EndTime { get; set; }
    public string? Description { get; set; }
    public List<Guid> ShiftTemplateIds { get; set; } = [];
}

public class UpdateMealSessionRequest
{
    public string Name { get; set; } = string.Empty;
    public TimeSpan StartTime { get; set; }
    public TimeSpan EndTime { get; set; }
    public string? Description { get; set; }
    public List<Guid> ShiftTemplateIds { get; set; } = [];
}
