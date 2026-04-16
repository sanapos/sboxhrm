using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.SalaryProfiles.AssignSalaryProfile.SalaryProfileStrategies;

public class ShiftSalaryProfileStrategy() : IBenefitAssignmentStrategy
{
    public SalaryRateType RateType => SalaryRateType.Shift;

    public Task<(bool IsValid, string? ErrorMessage)> ValidateAssignmentAsync(
        Benefit salaryProfile, Employee employee, CancellationToken cancellationToken = default)
    {
        // For shift salary type 0 (fixed per shift), validate rate
        if (salaryProfile.ShiftSalaryType == 0 || salaryProfile.ShiftSalaryType == null)
        {
            if (salaryProfile.Rate <= 0 && (salaryProfile.FixedShiftRate == null || salaryProfile.FixedShiftRate <= 0))
                return Task.FromResult<(bool, string?)>((false, "Shift rate must be greater than zero"));
        }

        if (salaryProfile.ShiftsPerDay.HasValue && 
            (salaryProfile.ShiftsPerDay.Value <= 0 || salaryProfile.ShiftsPerDay.Value > 10))
            return Task.FromResult<(bool, string?)>((false, "Shifts per day must be between 1 and 10"));

        return Task.FromResult<(bool, string?)>((true, null));
    }

    public Task<EmployeeBenefit?> ConfigEmployeeBenefitAsync(Benefit salaryProfile, Employee employee)
    {
        return Task.FromResult<EmployeeBenefit?>(new EmployeeBenefit
        {
            EmployeeId = employee.Id,
            BenefitId = salaryProfile.Id,
            IsActive = true
        });
    }
}
