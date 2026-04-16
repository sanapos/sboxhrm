namespace ZKTecoADMS.Application.DTOs.Meals;

public class MealRecordDto
{
    public Guid Id { get; set; }
    public Guid EmployeeUserId { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public string? PIN { get; set; }
    public Guid MealSessionId { get; set; }
    public string? MealSessionName { get; set; }
    public DateTime MealTime { get; set; }
    public DateTime Date { get; set; }
    public Guid? ShiftId { get; set; }
    public Guid? DeviceId { get; set; }
    public string? DeviceName { get; set; }
    public Guid? StoreId { get; set; }
    public DateTime CreatedAt { get; set; }
}

public class MealEstimateDto
{
    public Guid MealSessionId { get; set; }
    public string MealSessionName { get; set; } = string.Empty;
    public TimeSpan StartTime { get; set; }
    public TimeSpan EndTime { get; set; }
    public int EstimatedCount { get; set; }
    public int ActualCount { get; set; }
    public int Remaining => EstimatedCount - ActualCount;
}

public class MealSummaryDto
{
    public DateTime Date { get; set; }
    public List<MealEstimateDto> Sessions { get; set; } = [];
    public int TotalEstimated { get; set; }
    public int TotalActual { get; set; }
}

public class EmployeeMealSummaryDto
{
    public Guid EmployeeUserId { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public string? EmployeeCode { get; set; }
    public int TotalMeals { get; set; }
    public List<MealDetailDto> Details { get; set; } = [];
}

public class MealDetailDto
{
    public DateTime Date { get; set; }
    public string MealSessionName { get; set; } = string.Empty;
    public DateTime MealTime { get; set; }
}
