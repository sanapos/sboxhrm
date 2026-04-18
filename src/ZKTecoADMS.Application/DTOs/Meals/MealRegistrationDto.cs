namespace ZKTecoADMS.Application.DTOs.Meals;

public class MealRegistrationDto
{
    public Guid Id { get; set; }
    public Guid EmployeeUserId { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public Guid MealSessionId { get; set; }
    public DateTime Date { get; set; }
    public bool IsRegistered { get; set; }
    public DateTime RegisteredAt { get; set; }
    public DateTime? CancelledAt { get; set; }
    public string? Note { get; set; }
}
