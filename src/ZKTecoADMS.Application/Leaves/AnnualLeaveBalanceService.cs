using ZKTecoADMS.Application.DTOs.Leaves;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Leaves;

public class AnnualLeaveBalanceService(
    IRepository<EmployeeBenefit> employeeBenefitRepository,
    IRepository<Employee> employeeRepository,
    IRepository<EmployeeWorkingInfo> workingInfoRepository
) : IAnnualLeaveBalanceService
{
    public bool ShouldDeductFromAnnualBalance(Leave leave)
    {
        if (leave.CountAsWork || leave.AnnualBalanceApplied)
            return false;

        return leave.Type == LeaveType.AnnualLeave
               || (leave.Type == LeaveType.SickLeave
                   && leave.SickLeaveMode == SickLeaveMode.UseAnnualLeave);
    }

    public decimal CalculateLeaveDays(Leave leave)
    {
        var days = (leave.EndDate.Date - leave.StartDate.Date).Days + 1;
        if (days < 1) days = 1;
        return leave.IsHalfShift ? days * 0.5m : days;
    }

    public async Task<AnnualLeaveBalanceDto?> GetBalanceAsync(
        Guid employeeId,
        CancellationToken cancellationToken = default)
    {
        var eb = await GetActiveEmployeeBenefitAsync(employeeId, cancellationToken);
        if (eb == null) return null;

        return new AnnualLeaveBalanceDto
        {
            EmployeeId = employeeId,
            RemainingDays = eb.BalancedPaidLeaveDays ?? 0,
            EntitlementDays = eb.Benefit?.PaidLeaveDays,
            EmployeeBenefitId = eb.Id,
            BenefitName = eb.Benefit?.Name
        };
    }

    public async Task<AppResponse<decimal>> TryApplyDeductionAsync(
        Leave leave,
        CancellationToken cancellationToken = default)
    {
        if (!ShouldDeductFromAnnualBalance(leave))
            return AppResponse<decimal>.Success(0);

        var days = CalculateLeaveDays(leave);
        if (days <= 0)
            return AppResponse<decimal>.Success(0);

        var employeeId = await ResolveEmployeeIdAsync(leave, cancellationToken);
        if (!employeeId.HasValue)
            return AppResponse<decimal>.Error("Không xác định được nhân viên để trừ phép năm.");

        var eb = await GetActiveEmployeeBenefitAsync(employeeId.Value, cancellationToken);
        if (eb == null)
            return AppResponse<decimal>.Error(
                "Nhân viên chưa có hồ sơ lương đang hiệu lực. Vui lòng gắn thiết lập lương trước khi duyệt phép năm.");

        var balance = eb.BalancedPaidLeaveDays ?? 0;
        if (days > balance)
        {
            return AppResponse<decimal>.Error(
                $"Không đủ phép năm. Còn lại: {balance:0.##} ngày, đơn cần: {days:0.##} ngày.");
        }

        eb.BalancedPaidLeaveDays = balance - days;
        await employeeBenefitRepository.UpdateAsync(eb, cancellationToken);
        await SyncWorkingInfoBalanceAsync(employeeId.Value, leave.EmployeeUserId, eb, cancellationToken);

        leave.AnnualLeaveDaysDeducted = days;
        leave.AnnualBalanceApplied = true;
        leave.EmployeeId ??= employeeId;

        var remaining = eb.BalancedPaidLeaveDays ?? 0;
        return AppResponse<decimal>.Success(remaining);
    }

    public async Task RestoreAsync(Leave leave, CancellationToken cancellationToken = default)
    {
        if (!leave.AnnualBalanceApplied || leave.AnnualLeaveDaysDeducted <= 0)
            return;

        var employeeId = await ResolveEmployeeIdAsync(leave, cancellationToken);
        if (!employeeId.HasValue) return;

        var eb = await GetActiveEmployeeBenefitAsync(employeeId.Value, cancellationToken);
        if (eb != null)
        {
            eb.BalancedPaidLeaveDays = (eb.BalancedPaidLeaveDays ?? 0) + leave.AnnualLeaveDaysDeducted;
            await employeeBenefitRepository.UpdateAsync(eb, cancellationToken);
            await SyncWorkingInfoBalanceAsync(employeeId.Value, leave.EmployeeUserId, eb, cancellationToken);
        }

        leave.AnnualLeaveDaysDeducted = 0;
        leave.AnnualBalanceApplied = false;
    }

    private async Task<EmployeeBenefit?> GetActiveEmployeeBenefitAsync(
        Guid employeeId,
        CancellationToken cancellationToken)
    {
        return await employeeBenefitRepository.GetSingleAsync(
            eb => eb.EmployeeId == employeeId && eb.EndDate == null,
            includeProperties: [nameof(EmployeeBenefit.Benefit)],
            cancellationToken: cancellationToken);
    }

    private async Task<Guid?> ResolveEmployeeIdAsync(Leave leave, CancellationToken cancellationToken)
    {
        if (leave.EmployeeId.HasValue)
            return leave.EmployeeId;

        var emp = await employeeRepository.GetSingleAsync(
            e => e.ApplicationUserId == leave.EmployeeUserId,
            cancellationToken: cancellationToken);
        return emp?.Id;
    }

    private async Task SyncWorkingInfoBalanceAsync(
        Guid employeeId,
        Guid employeeUserId,
        EmployeeBenefit eb,
        CancellationToken cancellationToken)
    {
        var wi = await workingInfoRepository.GetSingleAsync(
            w => w.EmployeeId == employeeId || w.EmployeeUserId == employeeUserId,
            cancellationToken: cancellationToken);
        if (wi == null) return;

        wi.BalancedPaidLeaveDays = eb.BalancedPaidLeaveDays ?? 0;
        wi.BalancedUnpaidLeaveDays = eb.BalancedUnpaidLeaveDays ?? 0;
        await workingInfoRepository.UpdateAsync(wi, cancellationToken);
    }
}
