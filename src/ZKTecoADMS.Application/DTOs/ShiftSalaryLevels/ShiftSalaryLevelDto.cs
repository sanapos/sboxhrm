namespace ZKTecoADMS.Application.DTOs.ShiftSalaryLevels;

public class ShiftSalaryLevelDto
{
    public Guid Id { get; set; }
    public Guid ShiftTemplateId { get; set; }
    public string LevelName { get; set; } = string.Empty;
    public int SortOrder { get; set; }
    public string RateType { get; set; } = "fixed";
    public decimal FixedRate { get; set; }
    public decimal HourlyRate { get; set; }
    public decimal Multiplier { get; set; } = 1.0m;
    public decimal ShiftAllowance { get; set; }
    public bool IsNightShift { get; set; }
    public string? EmployeeIds { get; set; }
    public string? Description { get; set; }
    public bool IsActive { get; set; } = true;
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
}

public class CreateShiftSalaryLevelDto
{
    public Guid ShiftTemplateId { get; set; }
    public string LevelName { get; set; } = string.Empty;
    public int SortOrder { get; set; }
    public string? RateType { get; set; } = "fixed";
    public decimal FixedRate { get; set; }
    public decimal HourlyRate { get; set; }
    public decimal Multiplier { get; set; } = 1.0m;
    public decimal ShiftAllowance { get; set; }
    public bool IsNightShift { get; set; }
    public List<string>? EmployeeIds { get; set; }
    public string? Description { get; set; }
}

public class UpdateShiftSalaryLevelDto
{
    public string LevelName { get; set; } = string.Empty;
    public int SortOrder { get; set; }
    public string? RateType { get; set; } = "fixed";
    public decimal FixedRate { get; set; }
    public decimal HourlyRate { get; set; }
    public decimal Multiplier { get; set; } = 1.0m;
    public decimal ShiftAllowance { get; set; }
    public bool IsNightShift { get; set; }
    public List<string>? EmployeeIds { get; set; }
    public string? Description { get; set; }
    public bool IsActive { get; set; } = true;
}
