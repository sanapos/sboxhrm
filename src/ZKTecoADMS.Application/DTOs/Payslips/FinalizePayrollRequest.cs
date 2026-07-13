using System.Text.Json;

namespace ZKTecoADMS.Application.DTOs.Payslips;

public class FinalizePayrollRequest
{
    public int Year { get; set; }
    public int Month { get; set; }
    public DateTime PeriodStart { get; set; }
    public DateTime PeriodEnd { get; set; }
    public bool OverwriteExisting { get; set; } = true;
    public List<FinalizePayrollItemDto> Items { get; set; } = [];
}

public class FinalizePayrollItemDto
{
    public Guid? EmployeeUserId { get; set; }
    public Guid? EmployeeId { get; set; }
    public Guid SalaryProfileId { get; set; }
    public decimal RegularWorkUnits { get; set; }
    public decimal? OvertimeUnits { get; set; }
    public decimal BaseSalary { get; set; }
    public decimal? OvertimePay { get; set; }
    public decimal? Bonus { get; set; }
    public decimal? Deductions { get; set; }
    public decimal? Allowances { get; set; }
    public decimal? SocialInsurance { get; set; }
    public decimal? HealthInsurance { get; set; }
    public decimal? UnemploymentInsurance { get; set; }
    public decimal? Tax { get; set; }
    public decimal GrossSalary { get; set; }
    public decimal NetSalary { get; set; }
    public decimal? TravelHours { get; set; }
    public decimal? TravelSalary { get; set; }
    public string? Notes { get; set; }
    /// <summary>Bản chụp chấm công kỳ lương (JSON) — lưu độc lập khi chốt.</summary>
    public JsonElement? AttendanceSnapshot { get; set; }
}

public class FinalizePayrollResultDto
{
    public int Created { get; set; }
    public int Updated { get; set; }
    public int Skipped { get; set; }
    public List<string> Errors { get; set; } = [];
}
