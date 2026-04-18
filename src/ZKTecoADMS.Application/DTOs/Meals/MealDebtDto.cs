namespace ZKTecoADMS.Application.DTOs.Meals;

public class MealDebtDto
{
    public Guid Id { get; set; }
    public Guid EmployeeUserId { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    /// <summary>0=Charge, 1=Payment</summary>
    public int Type { get; set; }
    public decimal Amount { get; set; }
    public DateTime Date { get; set; }
    public Guid? MealSessionId { get; set; }
    public string? MealSessionName { get; set; }
    public string? Period { get; set; }
    public string? Note { get; set; }
    public string? RecordedByName { get; set; }
    public DateTime CreatedAt { get; set; }
}

public class MealDebtSummaryDto
{
    public Guid EmployeeUserId { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public string? EmployeeCode { get; set; }
    public int TotalMeals { get; set; }
    public decimal TotalCharged { get; set; }
    public decimal TotalPaid { get; set; }
    public decimal Balance { get; set; }
}

public class CreateMealDebtRequest
{
    public Guid EmployeeUserId { get; set; }
    /// <summary>0=Charge, 1=Payment</summary>
    public int Type { get; set; }
    public decimal Amount { get; set; }
    public string? Note { get; set; }
    public string? Period { get; set; }
}

public class BatchChargeRequest
{
    public string Period { get; set; } = string.Empty;
}
