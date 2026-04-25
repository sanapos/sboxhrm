using ZKTecoADMS.Application.DTOs.Payslips;

namespace ZKTecoADMS.Application.Queries.Payslips.GetStorePayslips;

public class GetStorePayslipsHandler(
    IPayslipRepository payslipRepository
) : IQueryHandler<GetStorePayslipsQuery, AppResponse<List<PayslipDto>>>
{
    public async Task<AppResponse<List<PayslipDto>>> Handle(GetStorePayslipsQuery request, CancellationToken cancellationToken)
    {
        var payslips = await payslipRepository.GetByStoreAndPeriodAsync(request.StoreId, request.Year, request.Month, cancellationToken);
        var dtos = payslips.Select(MapToDto).ToList();
        return AppResponse<List<PayslipDto>>.Success(dtos);
    }

    private static PayslipDto MapToDto(Payslip payslip)
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
