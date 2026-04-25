using ZKTecoADMS.Application.CQRS;
using ZKTecoADMS.Application.DTOs.Payslips;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Application.Queries.Payslips.GetStorePayslips;

public record GetStorePayslipsQuery(
    Guid StoreId,
    int Year,
    int? Month
) : IQuery<AppResponse<List<PayslipDto>>>;
