using ZKTecoADMS.Application.DTOs.Payslips;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Queries.Payslips.GetPayslipAttendanceSnapshot;

public class GetPayslipAttendanceSnapshotHandler(
    IPayslipRepository payslipRepository,
    IRepository<PayslipAttendanceSnapshot> snapshotRepository
) : IQueryHandler<GetPayslipAttendanceSnapshotQuery, AppResponse<PayslipAttendanceSnapshotDto>>
{
    public async Task<AppResponse<PayslipAttendanceSnapshotDto>> Handle(
        GetPayslipAttendanceSnapshotQuery request,
        CancellationToken cancellationToken)
    {
        var payslip = await payslipRepository.GetByIdAsync(
            request.StoreId, request.PayslipId, cancellationToken);
        if (payslip == null)
            return AppResponse<PayslipAttendanceSnapshotDto>.Fail("Không tìm thấy phiếu lương");

        var snapshot = await snapshotRepository.GetSingleAsync(
            filter: s => s.PayslipId == request.PayslipId,
            cancellationToken: cancellationToken);
        if (snapshot == null)
            return AppResponse<PayslipAttendanceSnapshotDto>.Fail("Chưa có bản chấm công đính kèm phiếu lương này");

        return AppResponse<PayslipAttendanceSnapshotDto>.Success(new PayslipAttendanceSnapshotDto
        {
            PayslipId = snapshot.PayslipId,
            PeriodStart = snapshot.PeriodStart,
            PeriodEnd = snapshot.PeriodEnd,
            CapturedAt = snapshot.CapturedAt,
            Data = PayslipAttendanceSnapshotHelper.ParseSnapshotJson(snapshot.SnapshotJson)
        });
    }
}
