using ZKTecoADMS.Application.DTOs.Benefits;

namespace ZKTecoADMS.Application.Commands.Benefits.AssignEmployee;

public record AssignBenefitCommand(
    Guid EmployeeId,
    Guid BenefitId,
    DateTime EffectiveDate,
    string? Notes,
    string? ChangedBy = null
) : ICommand<AppResponse<EmployeeBenefitDto>>;
