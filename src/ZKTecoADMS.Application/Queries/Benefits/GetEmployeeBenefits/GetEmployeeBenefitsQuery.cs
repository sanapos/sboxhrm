
using ZKTecoADMS.Application.DTOs.Benefits;

namespace ZKTecoADMS.Application.Queries.Benefits.GetEmployeeBenefits;

public class GetEmployeeBenefitsQuery : IQuery<AppResponse<IEnumerable<EmployeeBenefitDto>>>
{
    public Guid ManagerId { get; set; }
}