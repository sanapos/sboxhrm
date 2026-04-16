using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Benefits;

namespace ZKTecoADMS.Application.Queries.Benefits.GetBenefits;

public class GetBenefitsHandler(
    IRepository<Benefit> repository
    ): IQueryHandler<GetBenefitsQuery, AppResponse<List<BenefitDto>>>
{
    public async Task<AppResponse<List<BenefitDto>>> Handle(GetBenefitsQuery request, CancellationToken cancellationToken)
    {
        // Always filter by StoreId for multi-tenant data isolation
        var benefits = await repository.GetAllWithIncludeAsync(
            filter: sp => sp.StoreId == request.StoreId &&
                          (!request.SalaryRateType.HasValue 
                          || sp.RateType == (Domain.Enums.SalaryRateType)request.SalaryRateType.Value),
            includes: query => query.Include(i => i.Employees),
            cancellationToken: cancellationToken);
        
        return AppResponse<List<BenefitDto>>.Success(benefits.Adapt<List<BenefitDto>>());
    }
}
