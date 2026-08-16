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

    public static List<string> NormalizeFcmCategories(IEnumerable<string>? categories)
    {
        if (categories == null) return [];
        var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var raw in categories)
        {
            var n = Application.Constants.NotificationCategoryCodes.Normalize(raw)
                    ?? (raw ?? "").Trim().ToLowerInvariant();
            if (n.Length > 0) set.Add(n);
        }
        return set.ToList();
    }

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
        var maxUsers = store.ServicePackage?.MaxUsers ?? store.MaxUsers;
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
        var storeWithPkg = await db.Stores.AsNoTracking()
            .Include(s => s.ServicePackage)
            .FirstOrDefaultAsync(s => s.Id == storeId, cancellationToken);
        if (storeWithPkg == null) return (false, "Không tìm thấy cửa hàng.");

        var maxDevices = storeWithPkg.ServicePackage?.MaxDevices ?? storeWithPkg.MaxDevices;
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

    public static void ApplyToStore(Store store, ServicePackage package)
    {
        store.MaxUsers = package.MaxUsers;
        store.MaxDevices = package.MaxDevices;
        store.MaxAccessDevices = package.MaxAccessDevices;
        store.AllowWeb = package.AllowWeb;
        store.AllowMobile = package.AllowMobile;
        store.MaxBranches = package.MaxBranches;
        store.AllowFcm = package.AllowFcm;
        store.AllowedFcmCategories = string.IsNullOrWhiteSpace(package.AllowedFcmCategories)
            ? "[]"
            : package.AllowedFcmCategories;
    }

    public static async Task<(bool Ok, string? Error)> CanAddBranchAsync(
        ZKTecoDbContext db,
        Guid storeId,
        CancellationToken cancellationToken = default)
    {
        var store = await db.Stores.AsNoTracking()
            .Include(s => s.ServicePackage)
            .FirstOrDefaultAsync(s => s.Id == storeId, cancellationToken);
        if (store == null) return (false, "Không tìm thấy cửa hàng.");

        var max = store.ServicePackage?.MaxBranches ?? store.MaxBranches;
        if (max <= 0) return (true, null);

        var current = await db.Branches.CountAsync(
            b => b.StoreId == storeId && b.Deleted == null,
            cancellationToken);
        if (current >= max)
        {
            return (false,
                $"Cửa hàng đã đạt giới hạn {max} chi nhánh theo gói dịch vụ. Vui lòng nâng cấp gói hoặc liên hệ quản trị.");
        }

        return (true, null);
    }

    public static bool IsWebPlatform(string? platform)
    {
        var p = (platform ?? "").Trim().ToLowerInvariant();
        return p is "web" or "browser" or "desktop";
    }

    public static bool IsMobilePlatform(string? platform)
    {
        var p = (platform ?? "").Trim().ToLowerInvariant();
        return p is "android" or "ios" or "pos" or "mobile" or "flutter";
    }

    public static async Task<(bool Ok, string? Error)> EnsureAccessAllowedAsync(
        ZKTecoDbContext db,
        Guid storeId,
        Guid userId,
        string? platform,
        string? deviceKey,
        string? deviceName,
        CancellationToken cancellationToken = default)
    {
        var store = await db.Stores.AsNoTracking()
            .Include(s => s.ServicePackage)
            .FirstOrDefaultAsync(s => s.Id == storeId, cancellationToken);
        if (store == null) return (false, "Không tìm thấy cửa hàng.");

        var allowWeb = store.ServicePackage?.AllowWeb ?? store.AllowWeb;
        var allowMobile = store.ServicePackage?.AllowMobile ?? store.AllowMobile;
        var maxAccess = store.ServicePackage?.MaxAccessDevices ?? store.MaxAccessDevices;

        var p = (platform ?? "").Trim().ToLowerInvariant();
        if (string.IsNullOrEmpty(p))
            return (true, null);

        if (IsWebPlatform(p) && !allowWeb)
            return (false, "Gói dịch vụ không cho phép đăng nhập bằng trình duyệt web.");
        if (IsMobilePlatform(p) && !allowMobile)
            return (false, "Gói dịch vụ không cho phép đăng nhập bằng ứng dụng mobile / POS.");

        var key = (deviceKey ?? "").Trim();
        if (key.Length == 0)
            return (true, null);
        if (key.Length > 80) key = key[..80];

        var existing = await db.StoreAccessDevices
            .IgnoreQueryFilters()
            .AsTracking()
            .FirstOrDefaultAsync(d => d.StoreId == storeId && d.DeviceKey == key,
                cancellationToken);
        if (existing != null)
        {
            existing.UserId = userId;
            existing.Platform = p;
            if (!string.IsNullOrWhiteSpace(deviceName)) existing.DeviceName = deviceName.Trim();
            existing.LastSeenAt = DateTime.UtcNow;
            existing.IsActive = true;
            existing.Deleted = null;
            existing.DeletedBy = null;
            await db.SaveChangesAsync(cancellationToken);
            return (true, null);
        }

        var current = await db.StoreAccessDevices.CountAsync(
            d => d.StoreId == storeId && d.Deleted == null && d.IsActive,
            cancellationToken);
        if (maxAccess > 0 && current >= maxAccess)
        {
            return (false,
                $"Cửa hàng đã đạt giới hạn {maxAccess} thiết bị truy cập theo gói dịch vụ. Vui lòng gỡ thiết bị cũ hoặc nâng cấp gói.");
        }

        db.StoreAccessDevices.Add(new StoreAccessDevice
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            UserId = userId,
            DeviceKey = key,
            Platform = p,
            DeviceName = string.IsNullOrWhiteSpace(deviceName) ? null : deviceName.Trim(),
            LastSeenAt = DateTime.UtcNow,
            IsActive = true,
            CreatedBy = userId.ToString(),
        });
        await db.SaveChangesAsync(cancellationToken);
        return (true, null);
    }

    public static async Task<bool> CanSendFcmAsync(
        ZKTecoDbContext db,
        Guid storeId,
        string? categoryCode,
        CancellationToken cancellationToken = default)
    {
        var store = await db.Stores.AsNoTracking()
            .Include(s => s.ServicePackage)
            .FirstOrDefaultAsync(s => s.Id == storeId, cancellationToken);
        if (store == null) return false;

        var allow = store.ServicePackage?.AllowFcm ?? store.AllowFcm;
        if (!allow) return false;

        var json = store.ServicePackage?.AllowedFcmCategories ?? store.AllowedFcmCategories;
        var allowed = DeserializeModules(json);
        if (allowed.Count == 0) return true;

        var code = Application.Constants.NotificationCategoryCodes.Normalize(categoryCode)
                   ?? (categoryCode ?? "").Trim().ToLowerInvariant();
        return allowed.Contains(code, StringComparer.OrdinalIgnoreCase);
    }
}
