using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.SalaryProfiles.AssignSalaryProfile.SalaryProfileStrategies;

/// <summary>
/// Strategy for handling hourly salary profile assignments
/// </summary>
public class HourlySalaryProfileStrategy(
) : IBenefitAssignmentStrategy
{
    public SalaryRateType RateType => SalaryRateType.Hourly;

    public Task<(bool IsValid, string? ErrorMessage)> ValidateAssignmentAsync(
        Benefit salaryProfile,
        Employee employee,
        CancellationToken cancellationToken = default)
    {
        // Validate hourly rate is positive
        if (salaryProfile.Rate <= 0)
        {
            return Task.FromResult<(bool, string?)>((false, "Hourly rate must be greater than zero"));
        }

        // Validate multipliers are reasonable
        if (salaryProfile.OvertimeMultiplier.HasValue && salaryProfile.OvertimeMultiplier.Value < 1)
        {
            return Task.FromResult<(bool, string?)>((false, "Overtime multiplier must be at least 1.0"));
        }

        if (salaryProfile.HolidayMultiplier.HasValue && salaryProfile.HolidayMultiplier.Value < 1)
        {
            return Task.FromResult<(bool, string?)>((false, "Holiday multiplier must be at least 1.0"));
        }

        if (salaryProfile.NightShiftMultiplier.HasValue && salaryProfile.NightShiftMultiplier.Value < 1)
        {
            return Task.FromResult<(bool, string?)>((false, "Night shift multiplier must be at least 1.0"));
        }

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
