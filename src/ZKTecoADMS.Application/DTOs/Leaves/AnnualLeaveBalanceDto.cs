namespace ZKTecoADMS.Application.DTOs.Leaves;

public class AnnualLeaveBalanceDto
{
    public Guid EmployeeId { get; set; }
    public decimal RemainingDays { get; set; }
    public decimal? EntitlementDays { get; set; }
    public Guid? EmployeeBenefitId { get; set; }
    public string? BenefitName { get; set; }
}
