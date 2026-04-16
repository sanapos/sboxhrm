using ZKTecoADMS.Application.CQRS;
using ZKTecoADMS.Application.DTOs.Payslips;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Application.Commands.Payslips.GeneratePayslip;

public record GeneratePayslipCommand(
    Guid StoreId,
    Guid EmployeeUserId,
    int Year,
    int Month,
    decimal? Bonus,
    decimal? Deductions,
    string? Notes
) : ICommand<AppResponse<PayslipDto>>;
