namespace ZKTecoADMS.Application.DTOs.Benefits;

public class AssignSalaryProfileRequest
{
    public Guid EmployeeId { get; set; }
    public Guid BenefitId { get; set; }
    public DateTime EffectiveDate { get; set; }
    public string? Notes { get; set; }
}
