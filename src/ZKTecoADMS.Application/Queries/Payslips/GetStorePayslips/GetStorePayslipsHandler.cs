using ZKTecoADMS.Application.DTOs.Payslips;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Queries.Payslips.GetStorePayslips;

public class GetStorePayslipsHandler(
    IPayslipRepository payslipRepository,
    IRepository<Employee> employeeRepository,
    IRepository<CashTransaction> cashTransactionRepository
) : IQueryHandler<GetStorePayslipsQuery, AppResponse<List<PayslipDto>>>
{
    public async Task<AppResponse<List<PayslipDto>>> Handle(
        GetStorePayslipsQuery request,
        CancellationToken cancellationToken)
    {
        var payslips = await payslipRepository.SearchAsync(
            request.StoreId,
            request.Year,
            request.Month,
            request.EmployeeUserId,
            request.Department,
            request.PeriodStartFrom,
            request.PeriodEndTo,
            cancellationToken);

        var empIds = payslips.Select(p => p.EmployeeId).Distinct().ToList();
        var employees = await employeeRepository.GetAllAsync(
            filter: e => empIds.Contains(e.Id),
            cancellationToken: cancellationToken);
        var empById = employees.ToDictionary(e => e.Id);

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
                empById.GetValueOrDefault(p.EmployeeId),
                p.CashTransactionId.HasValue
                    ? cashById.GetValueOrDefault(p.CashTransactionId.Value)
                    : null))
            .ToList();
        return AppResponse<List<PayslipDto>>.Success(dtos);
    }
}
