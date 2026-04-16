using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.DTOs.Payslips;

public class PayslipDto
{
    public Guid Id { get; set; }
    public Guid EmployeeUserId { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public Guid SalaryProfileId { get; set; }
    public string SalaryProfileName { get; set; } = string.Empty;
    public int Year { get; set; }
    public int Month { get; set; }
    public DateTime PeriodStart { get; set; }
    public DateTime PeriodEnd { get; set; }
    public decimal RegularWorkUnits { get; set; }
    public decimal? OvertimeUnits { get; set; }
    public decimal? HolidayUnits { get; set; }
    public decimal? NightShiftUnits { get; set; }
    public decimal BaseSalary { get; set; }
    public decimal? OvertimePay { get; set; }
    public decimal? HolidayPay { get; set; }
    public decimal? NightShiftPay { get; set; }
    public decimal? Bonus { get; set; }
    public decimal? Deductions { get; set; }
    public decimal? Allowances { get; set; }
    public decimal? SocialInsurance { get; set; }
    public decimal? HealthInsurance { get; set; }
    public decimal? UnemploymentInsurance { get; set; }
    public decimal? Tax { get; set; }
    public decimal GrossSalary { get; set; }
    public decimal NetSalary { get; set; }
    public string Currency { get; set; } = "USD";
    public PayslipStatus Status { get; set; }
    public string StatusName { get; set; } = string.Empty;
    public DateTime? GeneratedDate { get; set; }
    public string? GeneratedByUserName { get; set; }
    public DateTime? ApprovedDate { get; set; }
    public string? ApprovedByUserName { get; set; }
    public DateTime? PaidDate { get; set; }
    public string? Notes { get; set; }
    public DateTime CreatedAt { get; set; }
}
