using Microsoft.AspNetCore.Identity;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Helpers;

/// <summary>
/// Keeps AspNetUserRoles in sync with ApplicationUser.Role and ensures system roles exist.
/// </summary>
public static class IdentityRoleSyncHelper
{
    public static async Task EnsureRoleExistsAsync(
        RoleManager<IdentityRole<Guid>> roleManager,
        string roleName)
    {
        if (!await roleManager.RoleExistsAsync(roleName))
        {
            await roleManager.CreateAsync(new IdentityRole<Guid>(roleName));
        }
    }

    public static async Task<(bool Ok, string? Error)> EnsureUserHasRoleAsync(
        UserManager<ApplicationUser> userManager,
        RoleManager<IdentityRole<Guid>> roleManager,
        ApplicationUser user,
        string roleName)
    {
        await EnsureRoleExistsAsync(roleManager, roleName);

        var currentRoles = await userManager.GetRolesAsync(user);
        if (currentRoles.Contains(roleName))
        {
            return (true, null);
        }

        var result = await userManager.AddToRoleAsync(user, roleName);
        if (!result.Succeeded)
        {
            return (false, string.Join(", ", result.Errors.Select(e => e.Description)));
        }

        return (true, null);
    }

    /// <summary>
    /// If user.Role is SuperAdmin/Agent but Identity has no admin role, assign it.
    /// </summary>
    public static async Task TryHealAdminPortalRoleAsync(
        UserManager<ApplicationUser> userManager,
        RoleManager<IdentityRole<Guid>> roleManager,
        ApplicationUser user)
    {
        var roles = await userManager.GetRolesAsync(user);
        if (roles.Contains(nameof(Roles.SuperAdmin)) || roles.Contains(nameof(Roles.Agent)))
        {
            return;
        }

        if (user.Role == nameof(Roles.SuperAdmin) || user.Role == nameof(Roles.Agent))
        {
            await EnsureUserHasRoleAsync(userManager, roleManager, user, user.Role);
        }
    }

    public static async Task<(bool Ok, string? Error)> ReplaceUserRoleAsync(
        UserManager<ApplicationUser> userManager,
        RoleManager<IdentityRole<Guid>> roleManager,
        ApplicationUser user,
        string newRole)
    {
        await EnsureRoleExistsAsync(roleManager, newRole);

        var currentRoles = await userManager.GetRolesAsync(user);
        if (currentRoles.Any())
        {
            var removeResult = await userManager.RemoveFromRolesAsync(user, currentRoles);
            if (!removeResult.Succeeded)
            {
                return (false, string.Join(", ", removeResult.Errors.Select(e => e.Description)));
            }
        }

        user.Role = newRole;
        var updateResult = await userManager.UpdateAsync(user);
        if (!updateResult.Succeeded)
        {
            return (false, string.Join(", ", updateResult.Errors.Select(e => e.Description)));
        }

        return await EnsureUserHasRoleAsync(userManager, roleManager, user, newRole);
    }
}
