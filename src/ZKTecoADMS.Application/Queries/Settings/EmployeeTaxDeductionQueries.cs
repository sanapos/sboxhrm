using ZKTecoADMS.Application.DTOs.Settings;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Queries.Settings;

// Get all EmployeeTaxDeductions for a store
public record GetEmployeeTaxDeductionsQuery(Guid StoreId, Guid UserId) : IQuery<AppResponse<List<EmployeeTaxDeductionDto>>>;

public class GetEmployeeTaxDeductionsHandler(
    IRepository<EmployeeTaxDeduction> repository,
    IRepository<Employee> employeeRepository
) : IQueryHandler<GetEmployeeTaxDeductionsQuery, AppResponse<List<EmployeeTaxDeductionDto>>>
{
    public async Task<AppResponse<List<EmployeeTaxDeductionDto>>> Handle(GetEmployeeTaxDeductionsQuery request, CancellationToken cancellationToken)
    {
        try
        {
            // Get only active employees belonging to this store and managed by current user
            var employees = await employeeRepository.GetAllAsync(
                filter: e => e.StoreId == request.StoreId && e.WorkStatus == EmployeeWorkStatus.Active && e.ManagerId == request.UserId,
                cancellationToken: cancellationToken);

            // Get existing deduction records for this store
            var deductions = await repository.GetAllAsync(
                filter: e => e.StoreId == request.StoreId,
                cancellationToken: cancellationToken);

            var deductionMap = deductions.ToDictionary(d => d.EmployeeId);

            var result = employees.Select(emp =>
            {
                if (deductionMap.TryGetValue(emp.Id, out var ded))
                {
                    var dto = ded.Adapt<EmployeeTaxDeductionDto>();
                    dto.EmployeeName = $"{emp.LastName} {emp.FirstName}".Trim();
                    dto.EmployeeCode = emp.EmployeeCode;
                    return dto;
                }
                return new EmployeeTaxDeductionDto
                {
                    EmployeeId = emp.Id,
                    EmployeeName = $"{emp.LastName} {emp.FirstName}".Trim(),
                    EmployeeCode = emp.EmployeeCode,
                    NumberOfDependents = 0,
                    MandatoryInsurance = 0,
                    OtherExemptions = 0,
                };
            })
            .OrderBy(e => e.EmployeeCode)
            .ToList();

            return AppResponse<List<EmployeeTaxDeductionDto>>.Success(result);
        }
        catch (Exception ex)
        {
            return AppResponse<List<EmployeeTaxDeductionDto>>.Error(ex.Message);
        }
    }
}
