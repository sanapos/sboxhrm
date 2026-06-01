using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Helpers;

public static class ScheduleApprovalChainHelper
{
    public static async Task<int> GetApprovalLevelsAsync(
        IRepository<AppSettings> appSettingsRepository,
        Guid storeId,
        CancellationToken cancellationToken = default)
    {
        try
        {
            var setting = await appSettingsRepository.GetSingleAsync(
                s => s.Key == "schedule_approval_levels" && s.StoreId == storeId,
                cancellationToken: cancellationToken);
            if (setting?.Value != null && int.TryParse(setting.Value, out var levels) && levels is >= 1 and <= 5)
                return levels;
        }
        catch { }

        return 1;
    }

    public static async Task<List<ScheduleApprovalRecord>> BuildApprovalChainAsync(
        Guid employeeApplicationUserId,
        Guid storeId,
        int totalLevels,
        IRepository<Employee> employeeRepository,
        UserManager<ApplicationUser> userManager,
        CancellationToken cancellationToken = default)
    {
        var records = new List<ScheduleApprovalRecord>();

        var employee = await employeeRepository.GetSingleAsync(
            e => e.ApplicationUserId == employeeApplicationUserId && e.StoreId == storeId,
            cancellationToken: cancellationToken);

        var managerChain = new List<(Guid UserId, string Name)>();
        if (employee?.DirectManagerEmployeeId != null)
        {
            var mgr = await employeeRepository.GetSingleAsync(
                e => e.Id == employee.DirectManagerEmployeeId.Value,
                cancellationToken: cancellationToken);
            if (mgr?.ApplicationUserId != null)
            {
                var mgrUser = await userManager.FindByIdAsync(mgr.ApplicationUserId.Value.ToString());
                if (mgrUser != null)
                    managerChain.Add((mgrUser.Id, mgrUser.FullName ?? mgrUser.Email ?? "Manager"));

                if (mgr.DirectManagerEmployeeId != null)
                {
                    var gp = await employeeRepository.GetSingleAsync(
                        e => e.Id == mgr.DirectManagerEmployeeId.Value,
                        cancellationToken: cancellationToken);
                    if (gp?.ApplicationUserId != null)
                    {
                        var gpUser = await userManager.FindByIdAsync(gp.ApplicationUserId.Value.ToString());
                        if (gpUser != null)
                            managerChain.Add((gpUser.Id, gpUser.FullName ?? gpUser.Email ?? "Director"));
                    }
                }
            }
        }

        var admins = await userManager.Users
            .Where(u => u.IsActive && u.Role == "Admin" && u.StoreId == storeId && u.Id != employeeApplicationUserId)
            .ToListAsync(cancellationToken);
        var adminFirst = admins.FirstOrDefault();

        var levelNames = new[] { "Quản lý trực tiếp", "Quản lý cấp cao", "Admin", "Cấp 4", "Cấp 5" };

        for (var level = 1; level <= totalLevels; level++)
        {
            Guid? assignedUserId = null;
            string? assignedUserName = null;

            if (level - 1 < managerChain.Count)
            {
                assignedUserId = managerChain[level - 1].UserId;
                assignedUserName = managerChain[level - 1].Name;
            }
            else if (adminFirst != null)
            {
                assignedUserId = adminFirst.Id;
                assignedUserName = adminFirst.FullName ?? adminFirst.Email;
            }

            records.Add(new ScheduleApprovalRecord
            {
                StepOrder = level,
                StepName = level <= levelNames.Length ? levelNames[level - 1] : $"Cấp {level}",
                AssignedUserId = assignedUserId,
                AssignedUserName = assignedUserName,
                Status = ApprovalStatus.Pending
            });
        }

        return records;
    }
}
