using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.DTOs.Benefits;

namespace ZKTecoADMS.Application.Queries.Benefits.GetEmployeeBenefit;

public class GetEmployeeSalaryProfileHandler(
    IRepository<EmployeeBenefit> repository
    ) : IQueryHandler<GetEmployeeBenefitQuery, AppResponse<EmployeeBenefitDto>>
{
    public async Task<AppResponse<EmployeeBenefitDto>> Handle(GetEmployeeBenefitQuery request, CancellationToken cancellationToken)
    {
        var versions = await repository.GetAllAsync(
            eb => eb.EmployeeId == request.EmployeeId,
            includeProperties: ["Benefit"],
            cancellationToken: cancellationToken);
        var today = BenefitTimeline.VnToday();
        var employeeBenefit = BenefitTimeline.PickCurrent(versions, today);

        if (employeeBenefit == null)
        {
            return AppResponse<EmployeeBenefitDto>.Success(null!);
        }

        var dto = employeeBenefit.Adapt<EmployeeBenefitDto>();
        var upcoming = BenefitTimeline.PickUpcoming(versions, today);
        if (upcoming != null && upcoming.Id != employeeBenefit.Id) dto.Upcoming = upcoming.Adapt<EmployeeBenefitDto>();
        return AppResponse<EmployeeBenefitDto>.Success(dto);
    }
}
