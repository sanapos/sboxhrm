namespace ZKTecoADMS.Application.DTOs.Meals;

public class MealMenuDto
{
    public Guid Id { get; set; }
    public DateTime Date { get; set; }
    public DayOfWeek DayOfWeek { get; set; }
    public Guid MealSessionId { get; set; }
    public string? MealSessionName { get; set; }
    public string? Note { get; set; }
    public bool IsActive { get; set; }
    public Guid? StoreId { get; set; }
    public DateTime CreatedAt { get; set; }
    public List<MealMenuItemDto> Items { get; set; } = [];
}

public class MealMenuItemDto
{
    public Guid Id { get; set; }
    public string DishName { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string? Category { get; set; }
    public int SortOrder { get; set; }
}

public class CreateMealMenuRequest
{
    public DateTime Date { get; set; }
    public Guid MealSessionId { get; set; }
    public string? Note { get; set; }
    public List<CreateMealMenuItemRequest> Items { get; set; } = [];
}

public class CreateMealMenuItemRequest
{
    public string DishName { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string? Category { get; set; }
    public int SortOrder { get; set; }
}

public class UpdateMealMenuRequest
{
    public string? Note { get; set; }
    public List<CreateMealMenuItemRequest> Items { get; set; } = [];
}
