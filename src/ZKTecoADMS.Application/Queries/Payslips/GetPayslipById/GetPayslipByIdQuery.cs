using ZKTecoADMS.Application.CQRS;
using ZKTecoADMS.Application.DTOs.Payslips;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Application.Queries.Payslips.GetPayslipById;

public record GetPayslipByIdQuery(
    Guid StoreId,
    Guid Id
) : IQuery<AppResponse<PayslipDto>>;
