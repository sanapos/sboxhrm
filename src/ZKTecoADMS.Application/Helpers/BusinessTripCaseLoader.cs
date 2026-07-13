using Microsoft.AspNetCore.Identity;
using ZKTecoADMS.Application.DTOs.BusinessTrip;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Helpers;

internal static class BusinessTripEmployeeResolver
{
    public static async Task<(Guid? EmployeeUserId, Guid? EmployeeId, string? Error)> ResolveAsync(
        UserManager<ApplicationUser> userManager,
        IRepository<Employee> employeeRepository,
        Guid? employeeUserId,
        Guid? employeeId,
        Guid fallbackUserId,
        CancellationToken ct)
    {
        if (employeeUserId.HasValue)
        {
            var user = await userManager.FindByIdAsync(employeeUserId.Value.ToString());
            if (user != null)
            {
                var emp = await employeeRepository.GetSingleAsync(
                    e => e.ApplicationUserId == employeeUserId, cancellationToken: ct);
                return (employeeUserId, emp?.Id ?? employeeId, null);
            }

            var byEmpId = await employeeRepository.GetByIdAsync(employeeUserId.Value, cancellationToken: ct);
            if (byEmpId != null)
                return (byEmpId.ApplicationUserId, byEmpId.Id, null);
            return (null, null, "Không tìm thấy nhân viên");
        }

        if (employeeId.HasValue)
        {
            var emp = await employeeRepository.GetByIdAsync(employeeId.Value, cancellationToken: ct);
            if (emp == null) return (null, null, "Không tìm thấy hồ sơ nhân viên");
            return (emp.ApplicationUserId, emp.Id, null);
        }

        var selfEmp = await employeeRepository.GetSingleAsync(
            e => e.ApplicationUserId == fallbackUserId, cancellationToken: ct);
        return (fallbackUserId, selfEmp?.Id, null);
    }
}

internal static class BusinessTripAccess
{
    public static bool CanAccessCase(BusinessTripCase tripCase, Guid currentUserId, bool isPrivileged)
        => isPrivileged || tripCase.EmployeeUserId == currentUserId;

    public static string? DenyIfCannotAccess(BusinessTripCase tripCase, Guid currentUserId, bool isPrivileged)
        => CanAccessCase(tripCase, currentUserId, isPrivileged)
            ? null
            : "Bạn không có quyền truy cập hồ sơ công tác này";
}

internal static class BusinessTripCaseLoader
{
    internal static readonly string[] CaseIncludesPublic =
    [
        nameof(BusinessTripCase.Employee),
        nameof(BusinessTripCase.EmployeeUser),
        nameof(BusinessTripCase.AdvanceClaim),
        $"{nameof(BusinessTripCase.AdvanceClaim)}.{nameof(BusinessTripAdvanceClaim.ApprovalRecords)}",
        nameof(BusinessTripCase.SettlementClaim),
        $"{nameof(BusinessTripCase.SettlementClaim)}.{nameof(BusinessTripSettlementClaim.Lines)}",
        $"{nameof(BusinessTripCase.SettlementClaim)}.{nameof(BusinessTripSettlementClaim.Lines)}.{nameof(BusinessTripExpenseLine.Category)}",
        $"{nameof(BusinessTripCase.SettlementClaim)}.{nameof(BusinessTripSettlementClaim.Lines)}.{nameof(BusinessTripExpenseLine.Attachments)}",
        $"{nameof(BusinessTripCase.SettlementClaim)}.{nameof(BusinessTripSettlementClaim.ApprovalRecords)}"
    ];

    internal static readonly string[] ListIncludes =
    [
        nameof(BusinessTripCase.Employee),
        nameof(BusinessTripCase.EmployeeUser)
    ];

    private static readonly string[] CaseIncludes = CaseIncludesPublic;

    public static async Task<BusinessTripCase?> LoadAsync(
        IRepository<BusinessTripCase> repo, Guid id, Guid storeId, CancellationToken ct)
        => await repo.GetSingleAsync(c => c.Id == id && c.StoreId == storeId, CaseIncludes, cancellationToken: ct);

    /// <summary>
    /// Strip non-dependent navigations before <c>UpdateAsync</c> so EF does not mark the whole graph Modified.
    /// Do NOT null AdvanceClaim / SettlementClaim — one-to-one + Cascade makes Update() delete those rows.
    /// </summary>
    public static void DetachNavigations(BusinessTripCase tripCase)
    {
        tripCase.Employee = null;
        tripCase.EmployeeUser = null;
    }

    /// <summary>
    /// Avoid re-attaching Case (cycle). Keep Lines/Approvals as-is unless caller cleared them
    /// after hard-deleting children (SaveSettlement). Never null 1:1 Case from settlement via Update
    /// in a way that orphans incorrectly — Case nav null is safe (dependent side).
    /// </summary>
    public static void DetachSettlementNavigations(BusinessTripSettlementClaim settlement)
    {
        settlement.Case = null;
    }

    /// <summary>
    /// After hard-deleting old lines/approvals, clear collections so Update() does not
    /// re-attach deleted entities (DbUpdateConcurrencyException).
    /// </summary>
    public static void ClearSettlementChildren(BusinessTripSettlementClaim settlement)
    {
        settlement.Case = null;
        settlement.Lines = [];
        settlement.ApprovalRecords = [];
    }

    public static async Task<BusinessTripCaseDto> ToDtoAsync(
        IRepository<BusinessTripCase> repo, Guid id, Guid storeId, CancellationToken ct)
    {
        var entity = await LoadAsync(repo, id, storeId, ct)
            ?? throw new InvalidOperationException("Case not found");
        return BusinessTripMapper.ToDto(entity);
    }
}

internal static class BusinessTripCodeGenerator
{
    public static async Task<string> NextCaseCodeAsync(
        IRepository<BusinessTripCase> repo, Guid storeId, CancellationToken ct)
    {
        var dateStr = DateTime.UtcNow.ToString("yyyyMMdd");
        var prefix = $"CT-{dateStr}-";
        var count = await repo.CountAsync(c => c.StoreId == storeId && c.CaseCode.StartsWith(prefix), ct) + 1;
        return $"{prefix}{count:D4}";
    }
}
