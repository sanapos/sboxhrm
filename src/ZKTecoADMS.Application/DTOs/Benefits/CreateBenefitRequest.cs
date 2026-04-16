using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.DTOs.Benefits;

public class CreateBenefitRequest
{
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public SalaryRateType RateType { get; set; }
    public decimal Rate { get; set; }
    public string Currency { get; set; } = "USD";
    public decimal? OvertimeMultiplier { get; set; }
    public decimal? HolidayMultiplier { get; set; }
    public decimal? NightShiftMultiplier { get; set; }
    
    // Base Salary Configuration (Monthly profiles)
    public int? StandardHoursPerDay { get; set; }

    // Leave & Attendance Rules
    public string? WeeklyOffDays { get; set; }
    public int? PaidLeaveDays { get; set; }
    public int? UnpaidLeaveDays { get; set; }

    public TimeOnly? CheckIn { get; set; }
    public TimeOnly? CheckOut { get; set; }

    // Allowances
    public decimal? MealAllowance { get; set; }
    public decimal? TransportAllowance { get; set; }
    public decimal? HousingAllowance { get; set; }
    public decimal? ResponsibilityAllowance { get; set; }
    public decimal? AttendanceBonus { get; set; }
    public decimal? PhoneSkillShiftAllowance { get; set; }

    // Overtime Configuration (for Monthly profiles)
    public decimal? OTRateWeekday { get; set; }
    public decimal? OTRateWeekend { get; set; }
    public decimal? OTRateHoliday { get; set; }
    public decimal? NightShiftRate { get; set; }

    // Health Insurance
    public bool? HasHealthInsurance { get; set; }
    public decimal? HealthInsuranceRate { get; set; }

    // New salary settings fields
    public decimal? CompletionSalary { get; set; }
    public int? HolidayOvertimeType { get; set; }
    public decimal? HolidayOvertimeDailyRate { get; set; }
    public int? HourlyOvertimeType { get; set; }
    public decimal? HourlyOvertimeFixedRate { get; set; }
    public int? SocialInsuranceType { get; set; }
    public decimal? InsuranceSalary { get; set; }
    public decimal? DailyFixedRate { get; set; }
    public int? ShiftSalaryType { get; set; }
    public decimal? FixedShiftRate { get; set; }
    public int? ShiftsPerDay { get; set; }
    public string? AttendanceMode { get; set; }
    public string? PaidLeaveType { get; set; }

}
