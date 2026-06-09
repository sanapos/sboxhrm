using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Payslips;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;
using ZKTecoADMS.Application.Helpers;

namespace ZKTecoADMS.Application.Commands.Payslips.FinalizePayroll;

public record FinalizePayrollCommand(
    Guid StoreId,
    Guid UserId,
    FinalizePayrollRequest Request
) : ICommand<AppResponse<FinalizePayrollResultDto>>;

public class FinalizePayrollHandler(
    IPayslipRepository payslipRepository,
    IRepository<Benefit> benefitRepository,
    IRepository<Employee> employeeRepository,
    IRepository<CashTransaction> cashTransactionRepository,
    IRepository<TransactionCategory> categoryRepository
) : ICommandHandler<FinalizePayrollCommand, AppResponse<FinalizePayrollResultDto>>
{
    public async Task<AppResponse<FinalizePayrollResultDto>> Handle(
        FinalizePayrollCommand command,
        CancellationToken cancellationToken)
    {
        var req = command.Request;
        if (req.Items.Count == 0)
            return AppResponse<FinalizePayrollResultDto>.Error("Danh sách nhân viên chốt lương trống");

        if (req.Month is < 1 or > 12)
            return AppResponse<FinalizePayrollResultDto>.Error("Tháng kỳ lương không hợp lệ");

        var result = new FinalizePayrollResultDto();
        var now = DateTime.UtcNow;

        foreach (var item in req.Items)
        {
            try
            {
                var employee = await ResolveEmployeeAsync(
                    command.StoreId, item, cancellationToken);
                if (employee == null)
                {
                    result.Skipped++;
                    result.Errors.Add(
                        $"Bỏ qua NV (employeeId={item.EmployeeId}): không tìm thấy hồ sơ nhân viên");
                    continue;
                }

                if (item.SalaryProfileId == Guid.Empty)
                {
                    result.Skipped++;
                    result.Errors.Add($"NV {employee.EmployeeCode}: thiếu bảng lương");
                    continue;
                }

                var benefit = await benefitRepository.GetByIdAsync(
                    item.SalaryProfileId, cancellationToken: cancellationToken);
                if (benefit == null)
                {
                    result.Skipped++;
                    result.Errors.Add($"NV {employee.EmployeeCode}: bảng lương không tồn tại");
                    continue;
                }

                var existing = await payslipRepository.GetByEmployeeAndPeriodAsync(
                    command.StoreId, employee.Id, req.Year, req.Month, cancellationToken);

                if (existing != null && !req.OverwriteExisting)
                {
                    result.Skipped++;
                    continue;
                }

                var notes = string.IsNullOrWhiteSpace(item.Notes)
                    ? $"Chốt từ Tổng hợp lương ({req.PeriodStart:dd/MM/yyyy} - {req.PeriodEnd:dd/MM/yyyy})"
                    : item.Notes;

                Payslip payslip;
                if (existing != null)
                {
                    existing.StoreId = command.StoreId;
                    existing.EmployeeId = employee.Id;
                    existing.EmployeeUserId = employee.ApplicationUserId;
                    ApplyValues(existing, item, req, notes, command.UserId, now);
                    await payslipRepository.UpdateAsync(existing, cancellationToken);
                    payslip = existing;
                    result.Updated++;
                }
                else
                {
                    payslip = new Payslip
                    {
                        Id = Guid.NewGuid(),
                        StoreId = command.StoreId,
                        EmployeeId = employee.Id,
                        EmployeeUserId = employee.ApplicationUserId,
                        SalaryProfileId = item.SalaryProfileId,
                        Year = req.Year,
                        Month = req.Month,
                        PeriodStart = req.PeriodStart,
                        PeriodEnd = req.PeriodEnd,
                        Currency = "VND",
                        Status = PayslipStatus.Approved,
                        GeneratedDate = now,
                        GeneratedByUserId = command.UserId,
                        ApprovedDate = now,
                        ApprovedByUserId = command.UserId,
                    };
                    ApplyValues(payslip, item, req, notes, command.UserId, now);
                    await payslipRepository.CreateAsync(payslip, cancellationToken);
                    result.Created++;
                }

                await PayslipCashTransactionHelper.EnsureExpenseVoucherAsync(
                    payslip,
                    employee,
                    command.StoreId,
                    command.UserId,
                    payslipRepository,
                    cashTransactionRepository,
                    categoryRepository,
                    cancellationToken);
            }
            catch (DbUpdateException ex)
            {
                result.Skipped++;
                var detail = ex.InnerException?.Message ?? ex.Message;
                result.Errors.Add($"Lỗi lưu phiếu (có thể đã tồn tại cùng kỳ): {detail}");
            }
            catch (Exception ex)
            {
                result.Skipped++;
                result.Errors.Add($"Lỗi xử lý NV: {ex.Message}");
            }
        }

        if (result.Created == 0 && result.Updated == 0 && result.Skipped > 0)
        {
            return AppResponse<FinalizePayrollResultDto>.Error(
                $"Không chốt được phiếu nào ({result.Skipped} bỏ qua). " +
                string.Join("; ", result.Errors.Take(3)));
        }

        return AppResponse<FinalizePayrollResultDto>.Success(result);
    }

    private async Task<Employee?> ResolveEmployeeAsync(
        Guid storeId,
        FinalizePayrollItemDto item,
        CancellationToken cancellationToken)
    {
        if (item.EmployeeId is { } employeeId && employeeId != Guid.Empty)
        {
            return await employeeRepository.GetSingleAsync(
                filter: e => e.Id == employeeId &&
                             (e.StoreId == storeId || e.StoreId == null),
                cancellationToken: cancellationToken);
        }

        if (item.EmployeeUserId is { } uid && uid != Guid.Empty)
        {
            return await employeeRepository.GetSingleAsync(
                filter: e => e.ApplicationUserId == uid &&
                             (e.StoreId == storeId || e.StoreId == null),
                cancellationToken: cancellationToken);
        }

        return null;
    }

    private static void ApplyValues(
        Payslip payslip,
        FinalizePayrollItemDto item,
        FinalizePayrollRequest req,
        string notes,
        Guid userId,
        DateTime now)
    {
        payslip.PeriodStart = req.PeriodStart;
        payslip.PeriodEnd = req.PeriodEnd;
        payslip.RegularWorkUnits = item.RegularWorkUnits;
        payslip.OvertimeUnits = item.OvertimeUnits;
        payslip.BaseSalary = item.BaseSalary;
        payslip.OvertimePay = item.OvertimePay;
        payslip.Bonus = item.Bonus;
        payslip.Deductions = item.Deductions;
        payslip.Allowances = item.Allowances;
        payslip.SocialInsurance = item.SocialInsurance;
        payslip.HealthInsurance = item.HealthInsurance;
        payslip.UnemploymentInsurance = item.UnemploymentInsurance;
        payslip.Tax = item.Tax;
        payslip.GrossSalary = item.GrossSalary;
        payslip.NetSalary = item.NetSalary;
        payslip.Notes = notes;
        payslip.Currency = "VND";
        if (payslip.Status != PayslipStatus.Paid)
        {
            payslip.Status = PayslipStatus.Approved;
            payslip.PaidDate = null;
        }
        payslip.GeneratedDate = now;
        payslip.GeneratedByUserId = userId;
        payslip.ApprovedDate = now;
        payslip.ApprovedByUserId = userId;
    }
}
