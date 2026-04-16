using ZKTecoADMS.Application.DTOs.Benefits;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Benefits.Update;

public class UpdateBenefitHandler(
    IRepository<Benefit> repository,
    ISystemNotificationService notificationService
    ) : ICommandHandler<UpdateBenefitCommand, AppResponse<BenefitDto>>
{
    public async Task<AppResponse<BenefitDto>> Handle(UpdateBenefitCommand request, CancellationToken cancellationToken)
    {
        // Filter by StoreId for multi-tenant data isolation
        var salaryProfile = await repository.GetSingleAsync(
            b => b.Id == request.Id && b.StoreId == request.StoreId,
            cancellationToken: cancellationToken);
        if (salaryProfile == null)
        {
            return AppResponse<BenefitDto>.Error("Salary profile not found");
        }

        // Check if name is unique within the store (excluding current profile)
        var isUnique = await repository.ExistsAsync(b => b.StoreId == request.StoreId && b.Name == request.Name && b.Id != request.Id, cancellationToken);
        if (isUnique)
        {
            return AppResponse<BenefitDto>.Error($"A salary profile with the name '{request.Name}' already exists");
        }

        salaryProfile.Name = request.Name;
        salaryProfile.Description = request.Description;
        salaryProfile.RateType = request.RateType;
        salaryProfile.Rate = request.Rate;
        salaryProfile.Currency = request.Currency;
        salaryProfile.OvertimeMultiplier = request.OvertimeMultiplier;
        salaryProfile.HolidayMultiplier = request.HolidayMultiplier;
        salaryProfile.NightShiftMultiplier = request.NightShiftMultiplier;
        salaryProfile.CheckIn = request.CheckIn;
        salaryProfile.CheckOut = request.CheckOut;

        // Base Salary Configuration
        salaryProfile.StandardHoursPerDay = request.StandardHoursPerDay;
        
        // Leave & Attendance Rules
        salaryProfile.WeeklyOffDays = request.WeeklyOffDays;
        salaryProfile.PaidLeaveDays = request.PaidLeaveDays;
        salaryProfile.UnpaidLeaveDays = request.UnpaidLeaveDays;
        // Allowances
        salaryProfile.MealAllowance = request.MealAllowance;
        salaryProfile.TransportAllowance = request.TransportAllowance;
        salaryProfile.HousingAllowance = request.HousingAllowance;
        salaryProfile.ResponsibilityAllowance = request.ResponsibilityAllowance;
        salaryProfile.AttendanceBonus = request.AttendanceBonus;
        salaryProfile.PhoneSkillShiftAllowance = request.PhoneSkillShiftAllowance;
        // Overtime Configuration
        salaryProfile.OTRateWeekday = request.OTRateWeekday;
        salaryProfile.OTRateWeekend = request.OTRateWeekend;
        salaryProfile.OTRateHoliday = request.OTRateHoliday;
        salaryProfile.NightShiftRate = request.NightShiftRate;
        // Health Insurance
        salaryProfile.HasHealthInsurance = request.HasHealthInsurance;
        salaryProfile.HealthInsuranceRate = request.HealthInsuranceRate;
        // New salary settings fields
        salaryProfile.CompletionSalary = request.CompletionSalary;
        salaryProfile.HolidayOvertimeType = request.HolidayOvertimeType;
        salaryProfile.HolidayOvertimeDailyRate = request.HolidayOvertimeDailyRate;
        salaryProfile.HourlyOvertimeType = request.HourlyOvertimeType;
        salaryProfile.HourlyOvertimeFixedRate = request.HourlyOvertimeFixedRate;
        salaryProfile.SocialInsuranceType = request.SocialInsuranceType;
        salaryProfile.InsuranceSalary = request.InsuranceSalary;
        salaryProfile.DailyFixedRate = request.DailyFixedRate;
        salaryProfile.ShiftSalaryType = request.ShiftSalaryType;
        salaryProfile.FixedShiftRate = request.FixedShiftRate;
        salaryProfile.ShiftsPerDay = request.ShiftsPerDay;
        salaryProfile.AttendanceMode = request.AttendanceMode;
        salaryProfile.PaidLeaveType = request.PaidLeaveType;
        // Deductions

        await repository.UpdateAsync(salaryProfile, cancellationToken);

        var dto = salaryProfile.Adapt<BenefitDto>();

        try
        {
            await notificationService.CreateAndSendAsync(
                targetUserId: null,
                type: NotificationType.Info,
                title: "Cập nhật bảng lương",
                message: $"Bảng lương \"{request.Name}\" đã được cập nhật",
                relatedEntityId: salaryProfile.Id,
                relatedEntityType: "Benefit",
                categoryCode: "salary",
                storeId: request.StoreId);
        }
        catch { }

        return AppResponse<BenefitDto>.Success(dto);
    }
}
