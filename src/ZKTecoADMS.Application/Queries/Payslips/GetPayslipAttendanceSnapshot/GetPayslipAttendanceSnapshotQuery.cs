using ZKTecoADMS.Application.DTOs.Payslips;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Application.Queries.Payslips.GetPayslipAttendanceSnapshot;

public record GetPayslipAttendanceSnapshotQuery(
    Guid StoreId,
    Guid PayslipId
) : IQuery<AppResponse<PayslipAttendanceSnapshotDto>>;
