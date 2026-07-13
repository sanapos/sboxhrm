using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Helpers;

/// <summary>Chuỗi duyệt đa cấp cho công tác phí (giống ứng lương).</summary>
public static class BusinessTripApprovalChainHelper
{
    public static async Task<List<(Guid? UserId, string? Name)>> BuildManagerChainAsync(
        IRepository<Employee> employeeRepository,
        UserManager<ApplicationUser> userManager,
        Guid? employeeUserId,
        CancellationToken ct = default)
    {
        var chain = new List<(Guid? UserId, string? Name)>();

        if (!employeeUserId.HasValue)
            return chain;

        var employee = await employeeRepository.GetSingleAsync(
            e => e.ApplicationUserId == employeeUserId.Value, cancellationToken: ct);

        if (employee?.DirectManagerEmployeeId != null)
        {
            var mgr = await employeeRepository.GetSingleAsync(
                e => e.Id == employee.DirectManagerEmployeeId.Value, cancellationToken: ct);
            if (mgr?.ApplicationUserId != null)
            {
                var mUser = await userManager.FindByIdAsync(mgr.ApplicationUserId.Value.ToString());
                if (mUser != null)
                    chain.Add((mUser.Id, mUser.FullName ?? mUser.Email ?? "Manager"));

                if (mgr.DirectManagerEmployeeId != null)
                {
                    var gp = await employeeRepository.GetSingleAsync(
                        e => e.Id == mgr.DirectManagerEmployeeId.Value, cancellationToken: ct);
                    if (gp?.ApplicationUserId != null)
                    {
                        var gpUser = await userManager.FindByIdAsync(gp.ApplicationUserId.Value.ToString());
                        if (gpUser != null)
                            chain.Add((gpUser.Id, gpUser.FullName ?? gpUser.Email ?? "Director"));
                    }
                }
            }
        }

        return chain;
    }

    public static async Task<ApplicationUser?> ResolveAdminFallbackAsync(
        UserManager<ApplicationUser> userManager,
        Guid storeId,
        Guid? excludeUserId,
        CancellationToken ct = default)
    {
        var admins = await userManager.Users
            .Where(u => u.IsActive && u.Role == "Admin" && u.StoreId == storeId && u.Id != excludeUserId)
            .ToListAsync(ct);
        return admins.FirstOrDefault();
    }

    public static async Task<int> ReadApprovalLevelsAsync(
        IRepository<AppSettings> appSettingsRepository,
        Guid storeId,
        string settingsKey,
        string fallbackKey,
        CancellationToken ct = default)
    {
        try
        {
            var setting = await appSettingsRepository.GetSingleAsync(
                s => s.StoreId == storeId && s.Key == settingsKey, cancellationToken: ct);
            if (setting != null && int.TryParse(setting.Value, out var lvl) && lvl >= 1)
                return lvl;

            var fallback = await appSettingsRepository.GetSingleAsync(
                s => s.StoreId == storeId && s.Key == fallbackKey, cancellationToken: ct);
            if (fallback != null && int.TryParse(fallback.Value, out var fb) && fb >= 1)
                return fb;
        }
        catch { /* default */ }

        return 1;
    }

    public static List<(int StepOrder, string StepName, Guid? AssignedUserId, string? AssignedUserName)>
        BuildSteps(int totalLevels, List<(Guid? UserId, string? Name)> managerChain, ApplicationUser? adminFallback)
    {
        var levelNames = new[] { "Quản lý trực tiếp", "Quản lý cấp cao", "Admin", "Cấp 4", "Cấp 5" };
        var steps = new List<(int, string, Guid?, string?)>();

        for (var level = 1; level <= totalLevels; level++)
        {
            Guid? assignedUserId = null;
            string? assignedUserName = null;

            if (level - 1 < managerChain.Count && managerChain[level - 1].UserId.HasValue)
            {
                assignedUserId = managerChain[level - 1].UserId;
                assignedUserName = managerChain[level - 1].Name;
            }
            else if (adminFallback != null)
            {
                assignedUserId = adminFallback.Id;
                assignedUserName = adminFallback.FullName ?? adminFallback.Email;
            }

            steps.Add((
                level,
                level <= levelNames.Length ? levelNames[level - 1] : $"Cấp {level}",
                assignedUserId,
                assignedUserName));
        }

        return steps;
    }
}
