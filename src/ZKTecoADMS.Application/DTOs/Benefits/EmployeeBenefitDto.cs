using ZKTecoADMS.Application.DTOs.Employees;

namespace ZKTecoADMS.Application.DTOs.Benefits;

public class EmployeeBenefitDto
{
    public Guid Id { get; set; }
    public Guid EmployeeId { get; set; }
    public EmployeeDto? Employee { get; set; }
    public Guid BenefitId {get;set;}
    public BenefitDto? Benefit { get; set; }
    
    public DateTime EffectiveDate { get; set; }
    public DateTime? EndDate { get; set; }
    
    public string Notes { get; set; }
    public bool IsActive { get; set; }
    
    public decimal? BalancedPaidLeaveDays { get; set; }
    
    public decimal? BalancedUnpaidLeaveDays { get; set; }
    
}
