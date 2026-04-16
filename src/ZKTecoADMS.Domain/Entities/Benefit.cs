using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

public class Benefit : AuditableEntity<Guid>
{
    [Required]
    [MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    [MaxLength(500)]
    public string? Description { get; set; }

    [Required]
    public SalaryRateType RateType { get; set; }

    [Required]
    public decimal Rate { get; set; }

    public int? StandardHoursPerDay { get; set; }

    public StandardWorkMode StandardWorkMode { get; set; }

    [MaxLength(10)]
    public string Currency { get; set; } = "VND";

    public decimal? OvertimeMultiplier { get; set; }

    public decimal? HolidayMultiplier { get; set; }

    public decimal? NightShiftMultiplier { get; set; }


    // Base Salary Configuration (Monthly profiles)
    public decimal? SalaryPerDay { get; set; }
    
    // Leave & Attendance Rules
    [MaxLength(100)]
    public string? WeeklyOffDays { get; set; } // Comma-separated days like "Saturday,Sunday"
    
    public decimal? PaidLeaveDays { get; set; }
    
    public decimal? UnpaidLeaveDays { get; set; }

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
    
    // Holiday overtime: 0=Fixed daily, 1=Legal coefficient
    public int? HolidayOvertimeType { get; set; }
    public decimal? HolidayOvertimeDailyRate { get; set; }
    
    // Hourly overtime: 0=Fixed hourly, 1=Legal coefficient
    public int? HourlyOvertimeType { get; set; }
    public decimal? HourlyOvertimeFixedRate { get; set; }
    
    // Social insurance: 0=None, 1=Base salary, 2=Base+Completion, 3=Regional min wage, 4=Custom amount
    public int? SocialInsuranceType { get; set; }
    
    // The exact salary amount used for BHXH contribution
    public decimal? InsuranceSalary { get; set; }
    
    // Daily fixed rate (for Daily salary type)
    public decimal? DailyFixedRate { get; set; }
    
    // Shift salary: 0=Fixed per shift, 1=Per shift template
    public int? ShiftSalaryType { get; set; }
    public decimal? FixedShiftRate { get; set; }
    
    // Shifts per day for work day calculation
    public int? ShiftsPerDay { get; set; }
    
    // Attendance mode: none, checkin, checkout, any
    [MaxLength(20)]
    public string? AttendanceMode { get; set; }
    
    // Paid leave type: leave, sunday, saturday, sat-sun, sat-afternoon-sun
    [MaxLength(30)]
    public string? PaidLeaveType { get; set; }

    /// <summary>
    /// Cửa hàng sở hữu profile lương này
    /// </summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }

    // Navigation Properties - Many-to-many with Employee through EmployeeBenefit
    public virtual ICollection<EmployeeBenefit> EmployeeBenefits { get; set; } = new List<EmployeeBenefit>();

    public virtual ICollection<Employee> Employees {get;set;} = new List<Employee>();
}
