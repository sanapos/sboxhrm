
using ZKTecoADMS.Application.DTOs.Benefits;

namespace ZKTecoADMS.Application.Queries.Benefits.GetBenefits;

public record GetBenefitsQuery(Guid StoreId, int? SalaryRateType = null) : IQuery<AppResponse<List<BenefitDto>>>;
