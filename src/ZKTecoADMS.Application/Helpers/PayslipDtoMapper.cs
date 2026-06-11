using ZKTecoADMS.Application.DTOs.Payslips;

using ZKTecoADMS.Domain.Entities;

using ZKTecoADMS.Domain.Enums;



namespace ZKTecoADMS.Application.Helpers;



public static class PayslipDtoMapper

{

    public static PayslipDto Map(

        Payslip payslip,

        Employee? employee = null,

        CashTransaction? cashTransaction = null,

        bool hasAttendanceSnapshot = false)

    {

        employee ??= payslip.Employee;

        cashTransaction ??= payslip.CashTransaction;



        var employeeName = employee != null

            ? $"{employee.LastName} {employee.FirstName}".Trim()

            : payslip.EmployeeUser?.FullName ?? payslip.EmployeeUser?.UserName ?? string.Empty;



        var isPaid = payslip.Status == PayslipStatus.Paid

                     || (cashTransaction?.IsPaid ?? false);



        return new PayslipDto

        {

            Id = payslip.Id,

            EmployeeId = payslip.EmployeeId,

            EmployeeUserId = payslip.EmployeeUserId,

            EmployeeName = employeeName,

            EmployeeCode = employee?.EmployeeCode ?? string.Empty,

            Department = employee?.Department ?? string.Empty,

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

            PaidDate = payslip.PaidDate ?? cashTransaction?.PaidDate,

            CashTransactionId = payslip.CashTransactionId ?? cashTransaction?.Id,

            CashTransactionCode = cashTransaction?.TransactionCode,

            IsPaid = isPaid,

            PaymentStatus = isPaid ? "Đã thanh toán" : "Chưa thanh toán",

            Notes = payslip.Notes,

            CreatedAt = payslip.CreatedAt,

            HasAttendanceSnapshot = hasAttendanceSnapshot

        };

    }

}


