using ZKTecoADMS.Application.DTOs.Benefits;

namespace ZKTecoADMS.Application.Queries.Benefits.GetEmployeeBenefit;

public class GetEmployeeSalaryProfileHandler(
    IRepository<EmployeeBenefit> repository
    ) : IQueryHandler<GetEmployeeBenefitQuery, AppResponse<EmployeeBenefitDto>>
{
    public async Task<AppResponse<EmployeeBenefitDto>> Handle(GetEmployeeBenefitQuery request, CancellationToken cancellationToken)
    {
        var employeeBenefit = await repository.GetSingleAsync(
            eb => eb.EmployeeId == request.EmployeeId && eb.EndDate == null,
            includeProperties: ["Benefit"],
            cancellationToken: cancellationToken);
        
        if (employeeBenefit == null)
        {
            return AppResponse<EmployeeBenefitDto>.Success(null!);
        }

        return AppResponse<EmployeeBenefitDto>.Success(employeeBenefit.Adapt<EmployeeBenefitDto>());
    }
}
