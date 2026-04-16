namespace ZKTecoADMS.Application.DTOs.Settings;

public class EmployeeTaxDeductionDto
{
    public Guid Id { get; set; }
    public Guid EmployeeId { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public string EmployeeCode { get; set; } = string.Empty;
    public int NumberOfDependents { get; set; }
    public decimal MandatoryInsurance { get; set; }
    public decimal OtherExemptions { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
}

public class CreateOrUpdateEmployeeTaxDeductionDto
{
    public Guid EmployeeId { get; set; }
    public int NumberOfDependents { get; set; }
    public decimal MandatoryInsurance { get; set; }
    public decimal OtherExemptions { get; set; }
}
