namespace ZKTecoADMS.Application.DTOs.Payslips;

public class GeneratePayslipRequest
{
    public Guid EmployeeUserId { get; set; }
    public int Year { get; set; }
    public int Month { get; set; }
    public decimal? Bonus { get; set; }
    public decimal? Deductions { get; set; }
    public string? Notes { get; set; }
}
