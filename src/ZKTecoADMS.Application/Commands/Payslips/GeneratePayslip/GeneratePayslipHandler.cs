using ZKTecoADMS.Application.CQRS;
using ZKTecoADMS.Application.DTOs.Payslips;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;
using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.Identity;

namespace ZKTecoADMS.Application.Commands.Payslips.GeneratePayslip;

public class GeneratePayslipHandler(
    IPayslipRepository payslipRepository,
    IEmployeeSalaryProfileRepository employeeSalaryProfileRepository,
    IRepository<Shift> shiftRepository,
    IRepository<InsuranceSetting> insuranceSettingRepository,
    UserManager<ApplicationUser> userManager,
    ISystemNotificationService notificationService
) : ICommandHandler<GeneratePayslipCommand, AppResponse<PayslipDto>>
{
    public async Task<AppResponse<PayslipDto>> Handle(GeneratePayslipCommand request, CancellationToken cancellationToken)
    {
        // Validate: cho phép tạo payslip cho tháng hiện tại hoặc tháng trước
        var now = DateTime.UtcNow;
        var requestedDate = new DateTime(request.Year, request.Month, 1);
        var currentMonthStart = new DateTime(now.Year, now.Month, 1);
        var previousMonthStart = currentMonthStart.AddMonths(-1);
        
        if (requestedDate < previousMonthStart || requestedDate > currentMonthStart)
        {
            return AppResponse<PayslipDto>.Fail("Chỉ có thể tạo phiếu lương cho tháng hiện tại hoặc tháng trước");
        }

        // Check if user exists and get employee
        var user = await userManager.Users
            .Include(u => u.Employee)
            .FirstOrDefaultAsync(u => u.Id == request.EmployeeUserId, cancellationToken);
            
        if (user == null)
        {
            return AppResponse<PayslipDto>.Fail("Không tìm thấy người dùng");
        }

        var employee = user.Employee;

        if (employee == null)
        {
            return AppResponse<PayslipDto>.Fail("Không tìm thấy nhân viên");
        }

        // Check if employee has an active salary profile
        var activeSalaryProfile = await employeeSalaryProfileRepository.GetActiveByEmployeeIdAsync(
            employee.Id, 
            cancellationToken
        );
        
        if (activeSalaryProfile == null || !activeSalaryProfile.IsActive)
        {
            return AppResponse<PayslipDto>.Fail("Nhân viên chưa có hồ sơ lương đang hoạt động");
        }

        // Load the salary profile with Benefit details
        var salaryProfileDetails = await employeeSalaryProfileRepository.GetByIdAsync(
            activeSalaryProfile.Id,
            includeProperties: [nameof(EmployeeBenefit.Benefit)],
            cancellationToken: cancellationToken
        );

        var benefit = salaryProfileDetails?.Benefit;
        if (benefit == null)
        {
            return AppResponse<PayslipDto>.Fail("Không tìm thấy thông tin profile lương");
        }

        // Check if payslip already exists for this period — delete to regenerate
        var existingPayslip = await payslipRepository.GetByEmployeeUserAndPeriodAsync(
            request.StoreId, request.EmployeeUserId, request.Year, request.Month, cancellationToken);
        if (existingPayslip != null)
        {
            await payslipRepository.DeleteAsync(request.StoreId, existingPayslip.Id, cancellationToken);
        }

        // Calculate period dates
        var periodStart = new DateTime(request.Year, request.Month, 1);
        var periodEnd = new DateTime(request.Year, request.Month, 
            DateTime.DaysInMonth(request.Year, request.Month), 23, 59, 59);
        // Nếu tháng hiện tại, chỉ tính đến ngày hôm nay
        if (request.Year == now.Year && request.Month == now.Month)
        {
            periodEnd = new DateTime(now.Year, now.Month, now.Day, 23, 59, 59);
        }

        // Get approved shifts for the period
        var shifts = await shiftRepository.GetAllAsync(
            filter: s => 
                s.EmployeeUserId == request.EmployeeUserId &&
                s.StoreId == request.StoreId &&
                s.Status == ShiftStatus.Approved &&
                s.CheckInAttendanceId != null &&
                s.CheckOutAttendanceId != null &&
                s.Leave == null &&
                s.StartTime >= periodStart &&
                s.EndTime <= periodEnd,
            cancellationToken: cancellationToken
        );

        var shiftsList = shifts?.ToList() ?? new List<Shift>();

        // ═══════════════════════════════════════════════════
        // TÍNH TOÁN LƯƠNG
        // ═══════════════════════════════════════════════════

        // 1. Tính work units (giờ/ngày/ca)
        var (regularUnits, holidayUnits, nightShiftUnits) = CalculateWorkUnits(shiftsList, benefit.RateType);

        // 2. Tính lương cơ bản
        var baseSalary = CalculateBaseSalary(regularUnits, benefit.Rate, benefit.RateType, request.Year, request.Month);

        // 3. Tính phụ cấp
        decimal totalAllowances = 0;
        totalAllowances += benefit.MealAllowance ?? 0;
        totalAllowances += benefit.TransportAllowance ?? 0;
        totalAllowances += benefit.HousingAllowance ?? 0;
        totalAllowances += benefit.ResponsibilityAllowance ?? 0;
        totalAllowances += benefit.AttendanceBonus ?? 0;
        totalAllowances += benefit.PhoneSkillShiftAllowance ?? 0;

        // 4. Tính lương nghỉ lễ
        var holidayPay = CalculateHolidayPay(holidayUnits, benefit.Rate, benefit.HolidayMultiplier ?? 2.0m);

        // 5. Tính lương ca đêm
        var nightShiftPay = CalculateNightShiftPay(nightShiftUnits, benefit.Rate, benefit.NightShiftMultiplier ?? 1.3m);

        // 6. Tổng thu nhập gộp (Gross)
        var grossSalary = baseSalary 
            + totalAllowances 
            + (holidayPay ?? 0) 
            + (nightShiftPay ?? 0) 
            + (request.Bonus ?? 0);

        // ═══════════════════════════════════════════════════
        // TÍNH BẢO HIỂM & THUẾ
        // ═══════════════════════════════════════════════════

        decimal bhxhEmployee = 0, bhytEmployee = 0, bhtnEmployee = 0;
        decimal insuranceSalaryBase = benefit.InsuranceSalary ?? baseSalary;

        // Lấy thiết lập bảo hiểm
        var insuranceSettings = await insuranceSettingRepository.GetAllAsync(
            filter: ins => ins.StoreId == request.StoreId && ins.EffectiveYear <= request.Year,
            cancellationToken: cancellationToken
        );
        var insuranceSetting = insuranceSettings?
            .OrderByDescending(i => i.EffectiveYear)
            .FirstOrDefault();

        if (insuranceSetting != null)
        {
            // Áp dụng trần BHXH
            var cappedInsuranceSalary = Math.Min(insuranceSalaryBase, insuranceSetting.MaxInsuranceSalary);

            // BHXH: 8% (NLĐ)
            bhxhEmployee = cappedInsuranceSalary * insuranceSetting.BhxhEmployeeRate / 100;
            // BHYT: 1.5% (NLĐ)
            bhytEmployee = cappedInsuranceSalary * insuranceSetting.BhytEmployeeRate / 100;
            // BHTN: 1% (NLĐ)
            bhtnEmployee = cappedInsuranceSalary * insuranceSetting.BhtnEmployeeRate / 100;
        }

        var totalInsurance = bhxhEmployee + bhytEmployee + bhtnEmployee;

        // Thuế TNCN (Personal Income Tax) - theo biểu thuế lũy tiến
        // Thu nhập chịu thuế = Gross - BHXH NLĐ - Giảm trừ gia cảnh
        decimal personalDeduction = 11_000_000; // Giảm trừ bản thân
        var taxableIncome = grossSalary - totalInsurance - personalDeduction;
        var pit = CalculateProgressiveTax(taxableIncome);

        // 7. Tổng khấu trừ
        var totalDeductions = totalInsurance + pit + (request.Deductions ?? 0);

        // 8. Lương thực nhận (Net)
        var netSalary = grossSalary - totalDeductions;

        // ═══════════════════════════════════════════════════
        // TẠO PAYSLIP ENTITY & LƯU DB
        // ═══════════════════════════════════════════════════

        var payslip = new Payslip
        {
            EmployeeUserId = request.EmployeeUserId,
            SalaryProfileId = benefit.Id,
            Year = request.Year,
            Month = request.Month,
            PeriodStart = periodStart,
            PeriodEnd = periodEnd,
            RegularWorkUnits = regularUnits,
            OvertimeUnits = null, // TODO: tính OT riêng khi có module OT
            HolidayUnits = holidayUnits > 0 ? holidayUnits : null,
            NightShiftUnits = nightShiftUnits > 0 ? nightShiftUnits : null,
            BaseSalary = baseSalary,
            OvertimePay = null,
            HolidayPay = holidayPay,
            NightShiftPay = nightShiftPay,
            Bonus = request.Bonus ?? 0,
            Allowances = totalAllowances,
            SocialInsurance = bhxhEmployee,
            HealthInsurance = bhytEmployee,
            UnemploymentInsurance = bhtnEmployee,
            Tax = pit,
            Deductions = totalDeductions,
            GrossSalary = grossSalary,
            NetSalary = netSalary,
            Currency = benefit.Currency ?? "VND",
            Status = PayslipStatus.Draft,
            GeneratedDate = DateTime.UtcNow,
            GeneratedByUserId = request.EmployeeUserId,
            Notes = request.Notes,
            StoreId = request.StoreId,
        };

        var createdPayslip = await payslipRepository.CreateAsync(payslip, cancellationToken);

        try
        {
            await notificationService.CreateAndSendAsync(
                request.EmployeeUserId, NotificationType.Info,
                "Phiếu lương mới",
                $"Phiếu lương tháng {request.Month}/{request.Year} đã được tạo. Lương thực nhận: {netSalary:N0} {payslip.Currency}",
                relatedEntityId: createdPayslip.Id,
                relatedEntityType: "Payslip",
                categoryCode: "payroll", storeId: request.StoreId);
        }
        catch { /* Notification failure should not affect main operation */ }

        return AppResponse<PayslipDto>.Success(MapToDto(createdPayslip));
    }

    /// <summary>
    /// Tính thuế TNCN theo biểu thuế lũy tiến từng phần (Việt Nam)
    /// </summary>
    private static decimal CalculateProgressiveTax(decimal taxableIncome)
    {
        if (taxableIncome <= 0) return 0;

        // Biểu thuế lũy tiến từng phần
        var brackets = new (decimal limit, decimal rate)[]
        {
            (5_000_000, 0.05m),
            (10_000_000, 0.10m),
            (18_000_000, 0.15m),
            (32_000_000, 0.20m),
            (52_000_000, 0.25m),
            (80_000_000, 0.30m),
            (decimal.MaxValue, 0.35m),
        };

        decimal tax = 0;
        decimal remaining = taxableIncome;

        foreach (var (limit, rate) in brackets)
        {
            if (remaining <= 0) break;
            var taxable = Math.Min(remaining, limit);
            tax += taxable * rate;
            remaining -= taxable;
        }

        return Math.Round(tax, 0);
    }

    private (decimal regular, decimal holiday, decimal nightShift) CalculateWorkUnits(
        List<Shift> shifts,
        SalaryRateType rateType)
    {
        decimal regular = 0;
        decimal holiday = 0;
        decimal nightShift = 0;

        foreach (var shift in shifts)
        {
            // Use shift start and end times
            var shiftStart = shift.StartTime;
            var shiftEnd = shift.EndTime;
            var duration = shiftEnd - shiftStart - TimeSpan.FromMinutes(shift.BreakTimeMinutes);

            // Calculate hours in shift
            var hoursInShift = (decimal)duration.TotalHours;

            // For hourly rate, count all hours
            if (rateType == SalaryRateType.Hourly)
            {
                regular += hoursInShift;

                // Check for night shift (example: 10 PM to 6 AM)
                if (shiftStart.Hour >= 22 || shiftStart.Hour < 6)
                {
                    nightShift += hoursInShift;
                }

                // Check for holiday shift (you can add holiday logic here based on shift.IsHoliday or date)
                // For now, we'll leave holiday calculation for future implementation
            }
            // For daily rate, count as days
            // For monthly, shifts are just tracked but salary is fixed
            else if (rateType == SalaryRateType.Monthly)
            {
                // Count shifts for record keeping
                regular += 1;
            }
        }

        return (regular, holiday, nightShift);
    }

    private decimal CalculateBaseSalary(decimal units, decimal rate, SalaryRateType rateType, int year, int month)
    {
        return rateType switch
        {
            SalaryRateType.Hourly => units * rate,
            SalaryRateType.Monthly => rate, // Full monthly salary
            _ => 0
        };
    }

    private decimal? CalculateHolidayPay(decimal? holidayUnits, decimal rate, decimal multiplier)
    {
        if (holidayUnits == null || holidayUnits == 0)
            return null;

        return holidayUnits.Value * rate * multiplier;
    }

    private decimal? CalculateNightShiftPay(decimal? nightShiftUnits, decimal rate, decimal multiplier)
    {
        if (nightShiftUnits == null || nightShiftUnits == 0)
            return null;

        return nightShiftUnits.Value * rate * multiplier;
    }

    private PayslipDto MapToDto(Payslip payslip)
    {
        return new PayslipDto
        {
            Id = payslip.Id,
            EmployeeUserId = payslip.EmployeeUserId,
            EmployeeName = payslip.EmployeeUser?.LastName + " " + payslip.EmployeeUser?.FirstName ?? string.Empty,
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
