using Microsoft.AspNetCore.Identity;
using ZKTecoADMS.Application.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Helpers;

/// <summary>
/// Quyền chỉnh công trực tiếp (tự động duyệt khi tạo yêu cầu).
/// </summary>
public static class AttendanceCorrectionPrivilegeHelper
{
    private static readonly HashSet<string> AutoApproveRoles = new(StringComparer.OrdinalIgnoreCase)
    {
        "Admin", "Director", "SuperAdmin", "Agent"
    };

    public static bool IsElevatedRole(string? role) =>
        !string.IsNullOrWhiteSpace(role) && AutoApproveRoles.Contains(role);

    /// <summary>Role lưu trên user hoặc role Identity (JWT) — tránh lệch khi chỉ có một trong hai.</summary>
    public static async Task<string> GetEffectiveRoleAsync(
        UserManager<ApplicationUser> userManager,
        ApplicationUser user,
        CancellationToken cancellationToken = default)
    {
        if (!string.IsNullOrWhiteSpace(user.Role))
            return user.Role;

        var identityRoles = await userManager.GetRolesAsync(user);
        return identityRoles.FirstOrDefault(r => !string.IsNullOrWhiteSpace(r)) ?? string.Empty;
    }

    public static async Task<bool> IsElevatedUserAsync(
        UserManager<ApplicationUser> userManager,
        ApplicationUser user,
        CancellationToken cancellationToken = default)
    {
        if (IsElevatedRole(user.Role))
            return true;

        var identityRoles = await userManager.GetRolesAsync(user);
        return identityRoles.Any(IsElevatedRole);
    }

    public static async Task<bool> CanAutoApproveCorrectionsAsync(
        UserManager<ApplicationUser> userManager,
        IModulePermissionService permissionService,
        Guid userId,
        Guid storeId,
        CancellationToken cancellationToken = default)
    {
        var user = await userManager.FindByIdAsync(userId.ToString());
        if (user == null)
            return false;

        if (await IsElevatedUserAsync(userManager, user, cancellationToken))
            return true;

        var role = await GetEffectiveRoleAsync(userManager, user, cancellationToken);
        if (ModulePermissionDefaults.IsSuperRole(role))
            return true;

        if (await permissionService.HasPermissionAsync(
                userId, role, storeId, "AttendanceCorrection",
                ModulePermissionAction.Approve, cancellationToken))
            return true;

        if (await permissionService.HasPermissionAsync(
                userId, role, storeId, "AttendanceApproval",
                ModulePermissionAction.Approve, cancellationToken))
            return true;

        // Quản trị có quyền sửa/xóa chấm công trực tiếp → được tự duyệt phiếu
        if (await permissionService.HasPermissionAsync(
                userId, role, storeId, "Attendance",
                ModulePermissionAction.Delete, cancellationToken)
            && await permissionService.HasPermissionAsync(
                userId, role, storeId, "Attendance",
                ModulePermissionAction.Edit, cancellationToken))
            return true;

        return false;
    }

    public static async Task<bool> CanApproveCorrectionStepAsync(
        UserManager<ApplicationUser> userManager,
        IModulePermissionService permissionService,
        Guid approverUserId,
        Guid storeId,
        CancellationToken cancellationToken = default)
    {
        var approver = await userManager.FindByIdAsync(approverUserId.ToString());
        if (approver == null)
            return false;

        if (await IsElevatedUserAsync(userManager, approver, cancellationToken))
            return true;

        var role = await GetEffectiveRoleAsync(userManager, approver, cancellationToken);
        if (ModulePermissionDefaults.IsSuperRole(role))
            return true;

        if (await permissionService.HasPermissionAsync(
                approverUserId, role, storeId, "AttendanceCorrection",
                ModulePermissionAction.Approve, cancellationToken))
            return true;

        if (await permissionService.HasPermissionAsync(
                approverUserId, role, storeId, "AttendanceApproval",
                ModulePermissionAction.Approve, cancellationToken))
            return true;

        return false;
    }

    public static async Task<bool> CanBypassManualCorrectionSettingAsync(
        UserManager<ApplicationUser> userManager,
        IModulePermissionService permissionService,
        Guid userId,
        Guid storeId,
        CancellationToken cancellationToken = default) =>
        await CanAutoApproveCorrectionsAsync(
            userManager, permissionService, userId, storeId, cancellationToken);
}
