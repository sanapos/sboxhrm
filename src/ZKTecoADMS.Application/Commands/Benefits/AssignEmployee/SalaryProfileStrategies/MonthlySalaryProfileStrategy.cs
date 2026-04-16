using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.SalaryProfiles.AssignSalaryProfile.SalaryProfileStrategies;

/// <summary>
/// Strategy for handling monthly salary profile assignments
/// </summary>
public class MonthlySalaryProfileStrategy(
) : IBenefitAssignmentStrategy
{
    public SalaryRateType RateType => SalaryRateType.Monthly;

    public Task<(bool IsValid, string? ErrorMessage)> ValidateAssignmentAsync(
        Benefit salaryProfile,
        Employee employee,
        CancellationToken cancellationToken = default)
    {
        // Validate monthly rate is positive
        if (salaryProfile.Rate <= 0)
        {
            return Task.FromResult<(bool, string?)>((false, "Monthly salary must be greater than zero"));
        }

        // Validate standard hours per day if provided
        if (salaryProfile.StandardHoursPerDay.HasValue && 
            (salaryProfile.StandardHoursPerDay.Value <= 0 || salaryProfile.StandardHoursPerDay.Value > 24))
        {
            return Task.FromResult<(bool, string?)>((false, "Standard hours per day must be between 1 and 24"));
        }

        // Validate leave days are reasonable
        if (salaryProfile.PaidLeaveDays.HasValue && salaryProfile.PaidLeaveDays.Value < 0)
        {
            return Task.FromResult<(bool, string?)>((false, "Paid leave days cannot be negative"));
        }

        if (salaryProfile.UnpaidLeaveDays.HasValue && salaryProfile.UnpaidLeaveDays.Value < 0)
        {
            return Task.FromResult<(bool, string?)>((false, "Unpaid leave days cannot be negative"));
        }

        // Validate health insurance rate if enabled
        if (salaryProfile.HasHealthInsurance == true)
        {
            if (!salaryProfile.HealthInsuranceRate.HasValue)
            {
                return Task.FromResult<(bool, string?)>((false, "Health insurance rate is required when health insurance is enabled"));
            }

            if (salaryProfile.HealthInsuranceRate.Value < 0 || salaryProfile.HealthInsuranceRate.Value > 100)
            {
                return Task.FromResult<(bool, string?)>((false, "Health insurance rate must be between 0 and 100 percent"));
            }
        }

        // Validate OT rates are reasonable
        if (salaryProfile.OTRateWeekday.HasValue && salaryProfile.OTRateWeekday.Value < 1)
        {
            return Task.FromResult<(bool, string?)>((false, "OT rate for weekdays must be at least 1.0"));
        }

        if (salaryProfile.OTRateWeekend.HasValue && salaryProfile.OTRateWeekend.Value < 1)
        {
            return Task.FromResult<(bool, string?)>((false, "OT rate for weekends must be at least 1.0"));
        }

        if (salaryProfile.OTRateHoliday.HasValue && salaryProfile.OTRateHoliday.Value < 1)
        {
            return Task.FromResult<(bool, string?)>((false, "OT rate for holidays must be at least 1.0"));
        }

        return Task.FromResult<(bool, string?)>((true, null));
    }


    public async Task<EmployeeBenefit?> ConfigEmployeeBenefitAsync(Benefit salaryProfile, Employee employee)
    {
        return new EmployeeBenefit
        {
            EmployeeId = employee.Id,
            BenefitId = salaryProfile.Id,
            BalancedPaidLeaveDays = salaryProfile.PaidLeaveDays ?? 0,
            BalancedUnpaidLeaveDays = salaryProfile.UnpaidLeaveDays ?? 0,
            IsActive = true
        };
    }
}
