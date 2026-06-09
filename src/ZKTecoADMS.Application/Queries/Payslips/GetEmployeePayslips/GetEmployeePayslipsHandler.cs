using ZKTecoADMS.Application.DTOs.Payslips;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Queries.Payslips.GetEmployeePayslips;

public class GetEmployeePayslipsHandler(
    IPayslipRepository payslipRepository,
    IRepository<Employee> employeeRepository,
    IRepository<CashTransaction> cashTransactionRepository
) : IQueryHandler<GetEmployeePayslipsQuery, AppResponse<List<PayslipDto>>>
{
    public async Task<AppResponse<List<PayslipDto>>> Handle(
        GetEmployeePayslipsQuery request,
        CancellationToken cancellationToken)
    {
        var payslips = await payslipRepository.GetByEmployeeUserIdAsync(
            request.StoreId, request.EmployeeUserId, cancellationToken);

        var employee = await employeeRepository.GetSingleAsync(
            filter: e => e.ApplicationUserId == request.EmployeeUserId &&
                         e.StoreId == request.StoreId,
            cancellationToken: cancellationToken);

        var cashIds = payslips
            .Where(p => p.CashTransactionId.HasValue)
            .Select(p => p.CashTransactionId!.Value)
            .Distinct()
            .ToList();
        var cashTxs = cashIds.Count == 0
            ? []
            : await cashTransactionRepository.GetAllAsync(
                filter: c => cashIds.Contains(c.Id),
                cancellationToken: cancellationToken);
        var cashById = cashTxs.ToDictionary(c => c.Id);

        var dtos = payslips
            .Select(p => PayslipDtoMapper.Map(
                p,
                employee,
                p.CashTransactionId.HasValue
                    ? cashById.GetValueOrDefault(p.CashTransactionId.Value)
                    : null))
            .ToList();

        return AppResponse<List<PayslipDto>>.Success(dtos);
    }
}
