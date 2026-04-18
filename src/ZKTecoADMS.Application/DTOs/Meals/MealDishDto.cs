namespace ZKTecoADMS.Application.DTOs.Meals;

public class MealDishDto
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? Category { get; set; }
    public int SortOrder { get; set; }
    public bool IsActive { get; set; }
}

public class CreateMealDishRequest
{
    public string Name { get; set; } = string.Empty;
    public string? Category { get; set; }
    public int SortOrder { get; set; }
}

public class UpdateMealDishRequest
{
    public string Name { get; set; } = string.Empty;
    public string? Category { get; set; }
    public int SortOrder { get; set; }
}
