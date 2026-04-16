
using ZKTecoADMS.Application.DTOs.Benefits;

namespace ZKTecoADMS.Application.Queries.Benefits.GetEmployeeBenefit;

public record GetEmployeeBenefitQuery(Guid EmployeeId) : IQuery<AppResponse<EmployeeBenefitDto>>;
