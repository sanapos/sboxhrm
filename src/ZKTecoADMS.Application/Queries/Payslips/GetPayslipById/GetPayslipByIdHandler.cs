using ZKTecoADMS.Application.CQRS;
using ZKTecoADMS.Application.DTOs.Payslips;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Repositories;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Queries.Payslips.GetPayslipById;

public class GetPayslipByIdHandler(
    IPayslipRepository payslipRepository
) : IQueryHandler<GetPayslipByIdQuery, AppResponse<PayslipDto>>
{
    public async Task<AppResponse<PayslipDto>> Handle(GetPayslipByIdQuery request, CancellationToken cancellationToken)
    {
        var payslip = await payslipRepository.GetByIdAsync(request.StoreId, request.Id, cancellationToken);
        
        if (payslip == null)
        {
            return AppResponse<PayslipDto>.Fail("Payslip not found");
        }

        var dto = MapToDto(payslip);
        return AppResponse<PayslipDto>.Success(dto);
    }

    private PayslipDto MapToDto(Payslip payslip)
    {
        return new PayslipDto
        {
            Id = payslip.Id,
            EmployeeUserId = payslip.EmployeeUserId,
            EmployeeName = payslip.EmployeeUser?.UserName ?? string.Empty,
            SalaryProfileId = payslip.SalaryProfileId,
            SalaryProfileName = payslip.SalaryProfile?.Name ?? string.Empty,
            Year = payslip.Year,
            Month = payslip.Month,
            PeriodStart = payslip.PeriodStart,
            PeriodEnd = payslip.PeriodEnd,
            RegularWorkUnits = payslip.RegularWorkUnits,
            OvertimeUnits = payslip.OvertimeUnits,
            HolidayUnits = payslip.HolidayUnits,
            NightShiftUnits = payslip.NightShiftUnits,
            BaseSalary = payslip.BaseSalary,
            OvertimePay = payslip.OvertimePay,
            HolidayPay = payslip.HolidayPay,
            NightShiftPay = payslip.NightShiftPay,
            Bonus = payslip.Bonus,
            Deductions = payslip.Deductions,
            Allowances = payslip.Allowances,
            SocialInsurance = payslip.SocialInsurance,
            HealthInsurance = payslip.HealthInsurance,
            UnemploymentInsurance = payslip.UnemploymentInsurance,
            Tax = payslip.Tax,
            GrossSalary = payslip.GrossSalary,
            NetSalary = payslip.NetSalary,
            Currency = payslip.Currency,
            Status = payslip.Status,
            StatusName = payslip.Status.ToString(),
            GeneratedDate = payslip.GeneratedDate,
            GeneratedByUserName = payslip.GeneratedByUser?.UserName,
            ApprovedDate = payslip.ApprovedDate,
            ApprovedByUserName = payslip.ApprovedByUser?.UserName,
            PaidDate = payslip.PaidDate,
            Notes = payslip.Notes,
            CreatedAt = payslip.CreatedAt
        };
    }
}
