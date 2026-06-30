namespace ZKTecoADMS.Application.Interfaces;

public record EmployeeDeleteEvaluation(bool CanDelete, string? BlockedReason);

public interface IEmployeeDeleteGuard
{
    Task<EmployeeDeleteEvaluation> EvaluateAsync(Guid employeeId, CancellationToken cancellationToken = default);

    Task<IReadOnlyDictionary<Guid, EmployeeDeleteEvaluation>> EvaluateBatchAsync(
        IReadOnlyList<Guid> employeeIds,
        CancellationToken cancellationToken = default);
}
