using ZKTecoADMS.Application.DTOs.Payslips;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Queries.Payslips.GetPayslipById;

public class GetPayslipByIdHandler(
    IPayslipRepository payslipRepository,
    IRepository<Employee> employeeRepository,
    IRepository<CashTransaction> cashTransactionRepository,
    IRepository<PayslipAttendanceSnapshot> snapshotRepository
) : IQueryHandler<GetPayslipByIdQuery, AppResponse<PayslipDto>>
{
    public async Task<AppResponse<PayslipDto>> Handle(
        GetPayslipByIdQuery request,
        CancellationToken cancellationToken)
    {
        var payslip = await payslipRepository.GetByIdAsync(request.StoreId, request.Id, cancellationToken);

        if (payslip == null)
            return AppResponse<PayslipDto>.Fail("Không tìm thấy phiếu lương");

        var employee = await employeeRepository.GetSingleAsync(
            filter: e => e.Id == payslip.EmployeeId,
            cancellationToken: cancellationToken);

        CashTransaction? cash = null;
        if (payslip.CashTransactionId.HasValue)
        {
            cash = await cashTransactionRepository.GetByIdAsync(
                payslip.CashTransactionId.Value, cancellationToken: cancellationToken);
        }

        var hasSnapshot = await snapshotRepository.ExistsAsync(
            s => s.PayslipId == payslip.Id, cancellationToken);

        return AppResponse<PayslipDto>.Success(
            PayslipDtoMapper.Map(payslip, employee, cash, hasSnapshot));
    }
}
