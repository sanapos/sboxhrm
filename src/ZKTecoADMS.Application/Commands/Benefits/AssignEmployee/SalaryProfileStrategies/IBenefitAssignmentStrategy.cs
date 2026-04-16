using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Interfaces;

/// <summary>
/// Strategy interface for handling salary profile assignments based on rate type
/// </summary>
public interface IBenefitAssignmentStrategy
{
    /// <summary>
    /// The rate type this strategy handles
    /// </summary>
    SalaryRateType RateType { get; }
    
    /// <summary>
    /// Validates the salary profile assignment
    /// </summary>
    Task<(bool IsValid, string? ErrorMessage)> ValidateAssignmentAsync(
        Benefit salaryProfile, 
        Employee employee,
        CancellationToken cancellationToken = default);

    Task<EmployeeBenefit?> ConfigEmployeeBenefitAsync(Benefit salaryProfile, Employee employee);
}
