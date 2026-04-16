using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Benefits;

namespace ZKTecoADMS.Application.Queries.Benefits.GetEmployeeBenefits;

public class GetEmployeeProfilesHandler(
    IRepository<EmployeeBenefit> employeeBenefitRepository,
    IRepository<Employee> employeeRepository
    ) : IQueryHandler<GetEmployeeBenefitsQuery, AppResponse<IEnumerable<EmployeeBenefitDto>>>
{

    public async Task<AppResponse<IEnumerable<EmployeeBenefitDto>>> Handle(GetEmployeeBenefitsQuery request, CancellationToken cancellationToken)
    {
        var employees = await employeeRepository.GetAllAsync(
            filter: e => e.ManagerId == request.ManagerId,
            cancellationToken: cancellationToken);
        var employeeIds = employees.Select(e => e.Id).ToList();
        
        var employeeBenefits = await employeeBenefitRepository.GetAllWithIncludeAsync(
            filter: e => employeeIds.Contains(e.EmployeeId) && e.EndDate == null,
            includes: query => query.Include(q => q.Employee).Include(q => q.Benefit),
            cancellationToken: cancellationToken
        );

        var employeeBenefitDtos = employees.Select(e => {
            var benefit = employeeBenefits
                .FirstOrDefault(eb => eb.EmployeeId == e.Id);

            if (benefit == null) {
                benefit = new EmployeeBenefit
                {
                    Employee = e,
                    EmployeeId = e.Id,
                    IsActive = false,
                    Id = Guid.NewGuid()
                };
            }

            return benefit.Adapt<EmployeeBenefitDto>();
        });

        return AppResponse<IEnumerable<EmployeeBenefitDto>>.Success(employeeBenefitDtos);
    }
}