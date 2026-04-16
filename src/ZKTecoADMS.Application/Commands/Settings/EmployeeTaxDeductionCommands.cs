using ZKTecoADMS.Application.DTOs.Settings;

namespace ZKTecoADMS.Application.Commands.Settings;

// Create or Update EmployeeTaxDeduction Command
public record CreateOrUpdateEmployeeTaxDeductionCommand(
    Guid StoreId,
    Guid EmployeeId,
    int NumberOfDependents,
    decimal MandatoryInsurance,
    decimal OtherExemptions) : ICommand<AppResponse<EmployeeTaxDeductionDto>>;

public class CreateOrUpdateEmployeeTaxDeductionHandler(
    IRepository<EmployeeTaxDeduction> repository,
    IRepository<Employee> employeeRepository
) : ICommandHandler<CreateOrUpdateEmployeeTaxDeductionCommand, AppResponse<EmployeeTaxDeductionDto>>
{
    public async Task<AppResponse<EmployeeTaxDeductionDto>> Handle(CreateOrUpdateEmployeeTaxDeductionCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var employee = await employeeRepository.GetSingleAsync(
                e => e.Id == request.EmployeeId && e.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            if (employee == null)
                return AppResponse<EmployeeTaxDeductionDto>.Error("Không tìm thấy nhân viên");

            var existing = await repository.GetSingleAsync(
                e => e.EmployeeId == request.EmployeeId && e.StoreId == request.StoreId,
                cancellationToken: cancellationToken);

            if (existing != null)
            {
                existing.NumberOfDependents = request.NumberOfDependents;
                existing.MandatoryInsurance = request.MandatoryInsurance;
                existing.OtherExemptions = request.OtherExemptions;
                await repository.UpdateAsync(existing, cancellationToken);
            }
            else
            {
                existing = new EmployeeTaxDeduction
                {
                    EmployeeId = request.EmployeeId,
                    NumberOfDependents = request.NumberOfDependents,
                    MandatoryInsurance = request.MandatoryInsurance,
                    OtherExemptions = request.OtherExemptions,
                    StoreId = request.StoreId
                };
                existing = await repository.AddAsync(existing, cancellationToken);
            }

            var dto = existing.Adapt<EmployeeTaxDeductionDto>();
            dto.EmployeeName = $"{employee.LastName} {employee.FirstName}".Trim();
            dto.EmployeeCode = employee.EmployeeCode;
            return AppResponse<EmployeeTaxDeductionDto>.Success(dto);
        }
        catch (Exception ex)
        {
            return AppResponse<EmployeeTaxDeductionDto>.Error(ex.Message);
        }
    }
}
