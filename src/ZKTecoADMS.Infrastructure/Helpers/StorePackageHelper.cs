using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Authorization;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Helpers;

/// <summary>
/// Resolve gói dịch vụ của cửa hàng và enforce giới hạn người dùng / thiết bị.
/// </summary>
public static class StorePackageHelper
{
    private static readonly JsonSerializerOptions JsonOpts = new() { PropertyNameCaseInsensitive = true };

    public static List<string> DeserializeModules(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return [];
        try
        {
            return JsonSerializer.Deserialize<List<string>>(json, JsonOpts) ?? [];
        }
        catch
        {
            return [];
        }
    }

    public static async Task<List<string>> ResolveAllowedModulesAsync(
        ZKTecoDbContext db,
        Guid storeId,
        CancellationToken cancellationToken = default)
    {
        var store = await db.Stores
            .AsNoTracking()
            .Include(s => s.ServicePackage)
            .FirstOrDefaultAsync(s => s.Id == storeId, cancellationToken);

        if (store == null)
            return FeatureModuleCatalog.SelfServiceModuleCodes.ToList();

        if (store.ServicePackage != null)
        {
            var modules = DeserializeModules(store.ServicePackage.AllowedModules);
            return modules.Count > 0
                ? modules
                : FeatureModuleCatalog.SelfServiceModuleCodes.ToList();
        }

        var trial = await db.ServicePackages
            .AsNoTracking()
            .Where(p => p.IsActive && p.Name == "Dùng thử")
            .OrderByDescending(p => p.CreatedAt)
            .FirstOrDefaultAsync(cancellationToken);

        if (trial != null)
        {
            var trialModules = DeserializeModules(trial.AllowedModules);
            if (trialModules.Count > 0) return trialModules;
        }

        return FeatureModuleCatalog.SelfServiceModuleCodes.ToList();
    }

    public static async Task<bool> IsModuleAllowedAsync(
        ZKTecoDbContext db,
        Guid storeId,
        string moduleCode,
        CancellationToken cancellationToken = default)
    {
        if (FeatureModuleCatalog.IsSelfService(moduleCode)) return true;

        var allowed = await ResolveAllowedModulesAsync(db, storeId, cancellationToken);
        return allowed.Contains(moduleCode, StringComparer.OrdinalIgnoreCase);
    }

    public static async Task<(bool Ok, string? Error)> CanAddUserAsync(
        ZKTecoDbContext db,
        Guid storeId,
        CancellationToken cancellationToken = default)
    {
        var store = await db.Stores.AsNoTracking()
            .Include(s => s.ServicePackage)
            .FirstOrDefaultAsync(s => s.Id == storeId, cancellationToken);
        if (store == null) return (false, "Không tìm thấy cửa hàng.");

        // Prefer the higher of store vs package so a package upgrade is honored even if
        // Store.MaxUsers was not re-synced yet (legacy data after editing ServicePackage).
        var maxUsers = store.MaxUsers;
        if (store.ServicePackage != null && store.ServicePackage.MaxUsers > maxUsers)
            maxUsers = store.ServicePackage.MaxUsers;
        if (maxUsers <= 0) return (true, null);

        // Only active accounts occupy package seats (deactivated free a slot).
        var current = await db.Users.CountAsync(
            u => u.StoreId == storeId && u.IsActive,
            cancellationToken);

        if (current >= maxUsers)
        {
            return (false,
                $"Cửa hàng đã đạt giới hạn {maxUsers} tài khoản người dùng theo gói dịch vụ. Vui lòng nâng cấp gói hoặc liên hệ quản trị.");
        }

        return (true, null);
    }

    public static async Task<(bool Ok, string? Error)> CanAddDeviceAsync(
        ZKTecoDbContext db,
        Guid storeId,
        CancellationToken cancellationToken = default)
    {
        var store = await db.Stores.AsNoTracking()
            .FirstOrDefaultAsync(s => s.Id == storeId, cancellationToken);
        if (store == null) return (false, "Không tìm thấy cửa hàng.");

        var maxDevices = store.MaxDevices;
        if (maxDevices <= 0) return (true, null);

        var current = await db.Devices.CountAsync(
            d => d.StoreId == storeId && d.IsActive && d.IsClaimed,
            cancellationToken);

        if (current >= maxDevices)
        {
            return (false,
                $"Cửa hàng đã đạt giới hạn {maxDevices} thiết bị chấm công theo gói dịch vụ. Vui lòng nâng cấp gói hoặc liên hệ quản trị.");
        }

        return (true, null);
    }
}
