using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.SalaryProfiles.AssignSalaryProfile.SalaryProfileStrategies;

public class DailySalaryProfileStrategy() : IBenefitAssignmentStrategy
{
    public SalaryRateType RateType => SalaryRateType.Daily;

    public Task<(bool IsValid, string? ErrorMessage)> ValidateAssignmentAsync(
        Benefit salaryProfile, Employee employee, CancellationToken cancellationToken = default)
    {
        if (salaryProfile.Rate <= 0)
            return Task.FromResult<(bool, string?)>((false, "Daily rate must be greater than zero"));
        if (salaryProfile.OvertimeMultiplier.HasValue && salaryProfile.OvertimeMultiplier.Value < 1)
            return Task.FromResult<(bool, string?)>((false, "Overtime multiplier must be at least 1.0"));
        if (salaryProfile.HolidayMultiplier.HasValue && salaryProfile.HolidayMultiplier.Value < 1)
            return Task.FromResult<(bool, string?)>((false, "Holiday multiplier must be at least 1.0"));
        if (salaryProfile.NightShiftMultiplier.HasValue && salaryProfile.NightShiftMultiplier.Value < 1)
            return Task.FromResult<(bool, string?)>((false, "Night shift multiplier must be at least 1.0"));
        if (salaryProfile.StandardHoursPerDay.HasValue && 
            (salaryProfile.StandardHoursPerDay.Value <= 0 || salaryProfile.StandardHoursPerDay.Value > 24))
            return Task.FromResult<(bool, string?)>((false, "Standard hours per day must be between 1 and 24"));
        return Task.FromResult<(bool, string?)>((true, null));
    }

    public async Task<EmployeeBenefit?> ConfigEmployeeBenefitAsync(Benefit salaryProfile, Employee employee)
    {
        return new EmployeeBenefit
        {
            EmployeeId = employee.Id,
            BenefitId = salaryProfile.Id,
            IsActive = true
        };
    }
}
