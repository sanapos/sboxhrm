using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Interfaces.Auth;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Helpers;

namespace ZKTecoADMS.Api.Controllers;

// ─── DTOs ─────────────────────────────────────────────────────────────

public class SaPackageCommercialDto
{
    public string ProductLine { get; set; } = "both";
    public decimal? MonthlyPrice { get; set; }
    public decimal? YearlyPrice { get; set; }
    public int TrialDays { get; set; }
    public int SortOrder { get; set; }
    public bool IsFeatured { get; set; }
    public string? Badge { get; set; }
    public string? Highlights { get; set; }
}

public class SaPackageImpactRequest
{
    public Guid PackageId { get; set; }
    public List<string> Modules { get; set; } = [];
    public int MaxUsers { get; set; }
    public int MaxBranches { get; set; }
    public int MaxDevices { get; set; }
}

public class SaStoreModulesDto
{
    public List<string> Extra { get; set; } = [];
    public List<string> Blocked { get; set; } = [];
    public string? AdminNote { get; set; }
}

public class SaStoreBulkRequest
{
    public List<Guid> Ids { get; set; } = [];
    /// <summary>extend / assign-package / lock / unlock</summary>
    public string Action { get; set; } = "";
    public int Days { get; set; }
    public Guid? PackageId { get; set; }
    public string? Reason { get; set; }
}

public class SaImpersonateRequest
{
    public string Reason { get; set; } = "";
}

/// <summary>
/// Quản trị Super Admin v2: danh mục chức năng + mẫu gói, thông tin kinh doanh của gói, xem trước ảnh hưởng khi sửa gói,
/// danh sách cửa hàng có bộ lọc + thao tác hàng loạt + chức năng riêng theo cửa hàng, lịch sử key,
/// công cụ hỗ trợ tài khoản (đặt lại mật khẩu, mở khóa, phiên đăng nhập, đăng nhập thay có ghi nhật ký).
/// </summary>
[ApiController]
[Authorize(Roles = nameof(Roles.SuperAdmin))]
[Route("api/system-admin/v2")]
public class SystemAdminV2Controller(
    ZKTecoDbContext db,
    UserManager<ApplicationUser> userManager,
    IAccessTokenService accessTokenService,
    ISystemNotificationService notifications,
    ILogger<SystemAdminV2Controller> logger) : AuthenticatedControllerBase
{
    private static List<string> Modules(string? json) => StorePackageHelper.DeserializeModules(json);

    private async Task AuditAsync(string action, string entityType, string? entityId, string? entityName, string? details, Guid? storeId = null)
    {
        try
        {
            db.AuditLogs.Add(new AuditLog
            {
                Id = Guid.NewGuid(),
                Action = action,
                EntityType = entityType,
                EntityId = entityId,
                EntityName = entityName,
                Details = details,
                UserId = CurrentUserId,
                UserEmail = User.Identity?.Name,
                UserRole = "SuperAdmin",
                StoreId = storeId,
                IpAddress = HttpContext.Connection.RemoteIpAddress?.ToString(),
                UserAgent = Request.Headers.UserAgent.ToString(),
                Timestamp = DateTime.UtcNow,
            });
            await db.SaveChangesAsync();
        }
        catch (Exception ex) { logger.LogWarning(ex, "Audit write failed"); }
    }

    // ─── Danh mục chức năng ───────────────────────────────────────────

    [HttpGet("catalog")]
    public ActionResult<AppResponse<object>> Catalog()
    {
        var modules = FeatureModuleCatalog.PackageSelectable.Select(m => new
        {
            code = m.Code,
            name = m.DisplayName,
            description = m.Description,
            category = m.Category,
            productLine = FeatureModuleCatalog.ProductLineOf(m.Category),
            requires = FeatureModuleCatalog.Requires.TryGetValue(m.Code, out var r) ? r : [],
        });
        return Ok(AppResponse<object>.Success(new
        {
            categories = FeatureModuleCatalog.CategoryOrder.Select(c => new { name = c, productLine = FeatureModuleCatalog.ProductLineOf(c) }),
            modules,
            presets = FeatureModuleCatalog.Presets.Select(p => new { key = p.Key, name = p.Name, description = p.Description, productLine = p.ProductLine, modules = p.Modules }),
            fcmCategories = FeatureModuleCatalog.FcmCategories.Select(f => new { code = f.Code, name = f.Name }),
            selfService = FeatureModuleCatalog.SelfServiceModuleCodes,
        }));
    }

    // ─── Gói dịch vụ ──────────────────────────────────────────────────

    [HttpGet("packages")]
    public async Task<ActionResult<AppResponse<object>>> Packages()
    {
        var now = DateTime.UtcNow;
        var pkgs = await db.ServicePackages.AsNoTracking().OrderBy(p => p.SortOrder).ThenBy(p => p.Name).ToListAsync();
        var storeStats = await db.Stores.AsNoTracking().Where(s => s.ServicePackageId != null)
            .GroupBy(s => s.ServicePackageId)
            .Select(g => new
            {
                id = g.Key,
                total = g.Count(),
                active = g.Count(s => s.IsActive && !s.IsLocked && (s.ExpiryDate == null || s.ExpiryDate > now)),
                expiring = g.Count(s => s.IsActive && s.ExpiryDate > now && s.ExpiryDate <= now.AddDays(7)),
            })
            .ToListAsync();
        var keyStats = await db.LicenseKeys.AsNoTracking().Where(k => k.ServicePackageId != null && k.IsActive)
            .GroupBy(k => k.ServicePackageId)
            .Select(g => new { id = g.Key, unused = g.Count(k => !k.IsUsed), used = g.Count(k => k.IsUsed) })
            .ToListAsync();
        var list = pkgs.Select(p =>
        {
            var mods = Modules(p.AllowedModules);
            var st = storeStats.FirstOrDefault(s => s.id == p.Id);
            var ks = keyStats.FirstOrDefault(k => k.id == p.Id);
            var ret = StorePackageHelper.ParseRetention(p.DataRetentionJson);
            return new
            {
                retentionRunHour = ret.RunHour, attendanceRetentionMonths = ret.AttendanceMonths, saleOrderRetentionMonths = ret.SaleOrderMonths,
                id = p.Id, p.Name, p.Description, p.IsActive, p.IsPublic, p.DefaultDurationDays, p.MaxUsers, p.MaxDevices,
                p.MaxAccessDevices, p.MaxBranches, p.AllowWeb, p.AllowMobile, p.AllowFcm,
                fcmCategories = Modules(p.AllowedFcmCategories),
                modules = mods,
                p.ProductLine, p.MonthlyPrice, p.YearlyPrice, p.TrialDays, p.SortOrder, p.IsFeatured, p.Badge, p.Highlights,
                missing = FeatureModuleCatalog.MissingDependencies(mods).Select(x => new { code = x.Code, missing = x.Missing }),
                unknown = mods.Where(m => !FeatureModuleCatalog.AllCodes.Contains(m)),
                stores = st?.total ?? 0, activeStores = st?.active ?? 0, expiringStores = st?.expiring ?? 0,
                unusedKeys = ks?.unused ?? 0, usedKeys = ks?.used ?? 0,
                p.CreatedAt, p.UpdatedAt,
            };
        }).ToList();
        return Ok(AppResponse<object>.Success(list));
    }

    [HttpPut("packages/{id:guid}/commercial")]
    public async Task<ActionResult<AppResponse<bool>>> SaveCommercial(Guid id, [FromBody] SaPackageCommercialDto dto)
    {
        var p = await db.ServicePackages.AsTracking().FirstOrDefaultAsync(x => x.Id == id);
        if (p == null) return Ok(AppResponse<bool>.Fail("Không tìm thấy gói"));
        if (dto.MonthlyPrice is < 0 || dto.YearlyPrice is < 0) return Ok(AppResponse<bool>.Fail("Giá không hợp lệ"));
        p.ProductLine = dto.ProductLine is "pos" or "hrm" ? dto.ProductLine : "both";
        p.MonthlyPrice = dto.MonthlyPrice;
        p.YearlyPrice = dto.YearlyPrice;
        p.TrialDays = Math.Clamp(dto.TrialDays, 0, 90);
        p.SortOrder = dto.SortOrder;
        p.IsFeatured = dto.IsFeatured;
        p.Badge = string.IsNullOrWhiteSpace(dto.Badge) ? null : dto.Badge.Trim()[..Math.Min(40, dto.Badge.Trim().Length)];
        p.Highlights = string.IsNullOrWhiteSpace(dto.Highlights) ? null : dto.Highlights.Trim();
        p.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();
        await AuditAsync(AuditActions.Update, "ServicePackage", id.ToString(), p.Name, "Cập nhật giá / thông tin bán");
        return Ok(AppResponse<bool>.Success(true));
    }

    /// <summary>Xem trước: sửa gói thì cửa hàng nào mất chức năng gì, vượt giới hạn nào.</summary>
    [HttpPost("packages/impact")]
    public async Task<ActionResult<AppResponse<object>>> PackageImpact([FromBody] SaPackageImpactRequest req)
    {
        var p = await db.ServicePackages.AsNoTracking().FirstOrDefaultAsync(x => x.Id == req.PackageId);
        if (p == null) return Ok(AppResponse<object>.Fail("Không tìm thấy gói"));
        var oldMods = Modules(p.AllowedModules);
        var newSet = new HashSet<string>(req.Modules, StringComparer.OrdinalIgnoreCase);
        var removed = oldMods.Where(m => !newSet.Contains(m)).ToList();
        var added = req.Modules.Where(m => !oldMods.Contains(m, StringComparer.OrdinalIgnoreCase)).ToList();
        var stores = await db.Stores.AsNoTracking().Where(s => s.ServicePackageId == p.Id)
            .Select(s => new
            {
                s.Id, s.Name, s.Code, s.ExtraModules,
                users = s.Users.Count(u => u.IsActive),
                devices = s.Devices.Count,
                branches = db.Branches.Count(b => b.StoreId == s.Id),
            })
            .ToListAsync();
        var name = FeatureModuleCatalog.All.ToDictionary(m => m.Code, m => m.DisplayName, StringComparer.OrdinalIgnoreCase);
        var rows = stores.Select(s =>
        {
            var extra = Modules(s.ExtraModules);
            var lost = removed.Where(r => !extra.Contains(r, StringComparer.OrdinalIgnoreCase)).ToList();
            var over = new List<string>();
            if (req.MaxUsers > 0 && s.users > req.MaxUsers) over.Add($"{s.users}/{req.MaxUsers} tài khoản");
            if (req.MaxDevices > 0 && s.devices > req.MaxDevices) over.Add($"{s.devices}/{req.MaxDevices} máy chấm công");
            if (req.MaxBranches > 0 && s.branches > req.MaxBranches) over.Add($"{s.branches}/{req.MaxBranches} chi nhánh");
            return new { id = s.Id, s.Name, s.Code, lost = lost.Select(l => name.GetValueOrDefault(l, l)), over };
        }).Where(r => r.lost.Any() || r.over.Count > 0).ToList();
        return Ok(AppResponse<object>.Success(new
        {
            totalStores = stores.Count,
            affectedStores = rows.Count,
            removed = removed.Select(r => name.GetValueOrDefault(r, r)),
            added = added.Select(a => name.GetValueOrDefault(a, a)),
            missing = FeatureModuleCatalog.MissingDependencies(req.Modules).Select(x => new
            {
                code = x.Code, name = name.GetValueOrDefault(x.Code, x.Code), missing = x.Missing, missingName = name.GetValueOrDefault(x.Missing, x.Missing),
            }),
            stores = rows.Take(200),
        }));
    }

    // ─── Cửa hàng ─────────────────────────────────────────────────────

    private static string StoreStatus(Store s, DateTime now)
    {
        if (!s.IsActive) return "inactive";
        if (s.IsLocked) return "locked";
        if (s.ExpiryDate != null && s.ExpiryDate <= now) return "expired";
        if (string.IsNullOrEmpty(s.LicenseKey) && s.TrialStartDate != null) return "trial";
        if (s.ExpiryDate != null && s.ExpiryDate <= now.AddDays(7)) return "expiring";
        return "active";
    }

    [HttpGet("stores")]
    public async Task<ActionResult<AppResponse<object>>> Stores(
        [FromQuery] string? status, [FromQuery] Guid? packageId, [FromQuery] Guid? agentId, [FromQuery] string? search,
        [FromQuery] int page = 1, [FromQuery] int pageSize = 50)
    {
        var now = DateTime.UtcNow;
        var q = db.Stores.AsNoTracking().AsQueryable();
        if (packageId.HasValue) q = q.Where(s => s.ServicePackageId == packageId);
        if (agentId.HasValue) q = q.Where(s => s.AgentId == agentId);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var t = search.Trim().ToLower();
            q = q.Where(s => s.Name.ToLower().Contains(t) || s.Code.ToLower().Contains(t)
                || (s.Phone != null && s.Phone.Contains(t))
                || (s.Owner != null && ((s.Owner.Email ?? "").ToLower().Contains(t) || (s.Owner.PhoneNumber ?? "").Contains(t))));
        }
        var rows = await q
            .OrderByDescending(s => s.CreatedAt)
            .Select(s => new
            {
                store = s,
                ownerName = s.Owner == null ? null : (s.Owner.LastName + " " + s.Owner.FirstName),
                ownerEmail = s.Owner == null ? null : s.Owner.Email,
                ownerPhone = s.Owner == null ? null : s.Owner.PhoneNumber,
                packageName = s.ServicePackage == null ? null : s.ServicePackage.Name,
                productLine = s.ServicePackage == null ? null : s.ServicePackage.ProductLine,
                agentName = s.Agent == null ? null : s.Agent.Name,
                users = s.Users.Count(u => u.IsActive),
            })
            .ToListAsync();
        var mapped = rows.Select(r =>
        {
            var s = r.store;
            var st = StoreStatus(s, now);
            return new
            {
                id = s.Id, s.Name, s.Code, s.Phone, s.Province, s.CreatedAt, s.ExpiryDate,
                daysLeft = s.ExpiryDate == null ? (int?)null : (int)Math.Ceiling((s.ExpiryDate.Value - now).TotalDays),
                status = st, s.IsLocked, s.LockReason, s.RenewalCount, s.LicenseKey,
                packageId = s.ServicePackageId, r.packageName, r.productLine, agentId = s.AgentId, r.agentName,
                r.ownerName, r.ownerEmail, r.ownerPhone, r.users, s.MaxUsers,
                extraCount = Modules(s.ExtraModules).Count, blockedCount = Modules(s.BlockedModules).Count, s.AdminNote,
            };
        }).ToList();
        var counts = mapped.GroupBy(m => m.status).ToDictionary(g => g.Key, g => g.Count());
        counts["all"] = mapped.Count;
        if (!string.IsNullOrWhiteSpace(status) && status != "all") mapped = mapped.Where(m => m.status == status).ToList();
        pageSize = Math.Clamp(pageSize, 10, 200);
        page = Math.Max(1, page);
        return Ok(AppResponse<object>.Success(new
        {
            items = mapped.Skip((page - 1) * pageSize).Take(pageSize),
            total = mapped.Count,
            page,
            pageSize,
            counts,
        }));
    }

    [HttpGet("stores/{id:guid}/modules")]
    public async Task<ActionResult<AppResponse<object>>> StoreModules(Guid id)
    {
        var s = await db.Stores.AsNoTracking().Include(x => x.ServicePackage).FirstOrDefaultAsync(x => x.Id == id);
        if (s == null) return Ok(AppResponse<object>.Fail("Không tìm thấy cửa hàng"));
        var pkg = Modules(s.ServicePackage?.AllowedModules);
        var effective = StorePackageHelper.ApplyStoreOverrides(s, pkg);
        return Ok(AppResponse<object>.Success(new
        {
            packageName = s.ServicePackage?.Name,
            package = pkg,
            extra = Modules(s.ExtraModules),
            blocked = Modules(s.BlockedModules),
            effective,
            missing = FeatureModuleCatalog.MissingDependencies(effective).Select(x => new { code = x.Code, missing = x.Missing }),
            s.AdminNote,
        }));
    }

    [HttpPut("stores/{id:guid}/modules")]
    public async Task<ActionResult<AppResponse<bool>>> SaveStoreModules(Guid id, [FromBody] SaStoreModulesDto dto)
    {
        var s = await db.Stores.AsTracking().FirstOrDefaultAsync(x => x.Id == id);
        if (s == null) return Ok(AppResponse<bool>.Fail("Không tìm thấy cửa hàng"));
        await StorePermissionSyncHelper.EnsureBaselineAsync(db, [id]);
        var valid = FeatureModuleCatalog.AllCodes;
        var extra = dto.Extra.Where(valid.Contains).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        var blocked = dto.Blocked.Where(valid.Contains).Distinct(StringComparer.OrdinalIgnoreCase)
            .Where(b => !extra.Contains(b, StringComparer.OrdinalIgnoreCase)).ToList();
        // Chức năng cấp thêm kéo theo chức năng cần có (vd Hợp đồng → Báo giá) nếu gói chưa có.
        var pkgMods = Modules(await db.ServicePackages.AsNoTracking()
            .Where(p => p.Id == s.ServicePackageId).Select(p => p.AllowedModules).FirstOrDefaultAsync());
        var effective = pkgMods.Concat(extra)
            .Where(m => !blocked.Contains(m, StringComparer.OrdinalIgnoreCase))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var dep in FeatureModuleCatalog.WithDependencies(extra).Where(d => !effective.Contains(d)))
        {
            extra.Add(dep);
            blocked.RemoveAll(b => b.Equals(dep, StringComparison.OrdinalIgnoreCase));
        }
        s.ExtraModules = extra.Count == 0 ? null : JsonSerializer.Serialize(extra);
        s.BlockedModules = blocked.Count == 0 ? null : JsonSerializer.Serialize(blocked);
        s.AdminNote = string.IsNullOrWhiteSpace(dto.AdminNote) ? null : dto.AdminNote.Trim();
        s.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();
        // Chức năng cấp thêm → cấp quyền vai trò theo mẫu.
        await StorePermissionSyncHelper.SyncAsync(db, id);
        await AuditAsync(AuditActions.Update, AuditEntityTypes.Store, id.ToString(), s.Name,
            $"Chức năng riêng: thêm [{string.Join(", ", extra)}], chặn [{string.Join(", ", blocked)}]", id);
        return Ok(AppResponse<bool>.Success(true));
    }

    [HttpPost("stores/bulk")]
    public async Task<ActionResult<AppResponse<object>>> BulkStores([FromBody] SaStoreBulkRequest req)
    {
        var ids = req.Ids.Distinct().Take(500).ToList();
        if (ids.Count == 0) return Ok(AppResponse<object>.Fail("Chưa chọn cửa hàng"));
        var stores = await db.Stores.AsTracking().Where(s => ids.Contains(s.Id)).ToListAsync();
        ServicePackage? pkg = null;
        switch (req.Action)
        {
            case "extend":
                if (req.Days is < 1 or > 3660) return Ok(AppResponse<object>.Fail("Số ngày gia hạn không hợp lệ"));
                foreach (var s in stores)
                {
                    s.ExpiryDate = StoreLicenseHelper.ComputeExtendedExpiryDate(s, req.Days);
                    s.UpdatedAt = DateTime.UtcNow;
                }
                break;
            case "assign-package":
                pkg = req.PackageId.HasValue ? await db.ServicePackages.FirstOrDefaultAsync(p => p.Id == req.PackageId) : null;
                if (pkg == null) return Ok(AppResponse<object>.Fail("Chọn gói dịch vụ"));
                await StorePermissionSyncHelper.EnsureBaselineAsync(db, ids);
                foreach (var s in stores)
                {
                    s.ServicePackageId = pkg.Id;
                    StorePackageHelper.ApplyToStore(s, pkg);
                    s.UpdatedAt = DateTime.UtcNow;
                }
                break;
            case "lock":
                if (string.IsNullOrWhiteSpace(req.Reason)) return Ok(AppResponse<object>.Fail("Nhập lý do khóa"));
                foreach (var s in stores)
                {
                    s.IsLocked = true;
                    s.LockReason = req.Reason.Trim();
                    s.LockedAt = DateTime.UtcNow;
                    s.UpdatedAt = DateTime.UtcNow;
                }
                break;
            case "unlock":
                foreach (var s in stores)
                {
                    s.IsLocked = false;
                    s.LockReason = null;
                    s.LockedAt = null;
                    s.UpdatedAt = DateTime.UtcNow;
                }
                break;
            default:
                return Ok(AppResponse<object>.Fail("Thao tác không hỗ trợ"));
        }
        await db.SaveChangesAsync();
        if (pkg != null)
            foreach (var s in stores)
                await StorePermissionSyncHelper.SyncAsync(db, s.Id);
        var action = req.Action switch
        {
            "extend" => AuditActions.SubscriptionExtended,
            "lock" => AuditActions.StoreLocked,
            "unlock" => AuditActions.StoreUnlocked,
            _ => AuditActions.Update,
        };
        foreach (var s in stores)
            await AuditAsync(action, AuditEntityTypes.Store, s.Id.ToString(), s.Name,
                req.Action switch
                {
                    "extend" => $"Gia hạn hàng loạt +{req.Days} ngày → {s.ExpiryDate:dd/MM/yyyy}",
                    "assign-package" => $"Đổi gói hàng loạt → {pkg?.Name}",
                    "lock" => $"Khóa hàng loạt: {req.Reason}",
                    _ => "Mở khóa hàng loạt",
                }, s.Id);
        return Ok(AppResponse<object>.Success(new { updated = stores.Count }));
    }

    [HttpGet("stores/{id:guid}/license-history")]
    public async Task<ActionResult<AppResponse<object>>> LicenseHistory(Guid id)
    {
        var keys = await db.LicenseKeys.AsNoTracking().Where(k => k.StoreId == id)
            .OrderByDescending(k => k.ActivatedAt)
            .Select(k => new
            {
                k.Key, k.DurationDays, k.ActivatedAt, licenseType = k.LicenseType.ToString(),
                packageName = k.ServicePackage == null ? null : k.ServicePackage.Name,
                agentName = k.Agent == null ? null : k.Agent.Name,
            })
            .ToListAsync();
        var sid = id.ToString();
        var events = await db.AuditLogs.AsNoTracking()
            .Where(a => (a.StoreId == id || a.EntityId == sid) && (a.Action == AuditActions.LicenseActivated
                || a.Action == AuditActions.SubscriptionExtended || a.Action == AuditActions.StoreLocked
                || a.Action == AuditActions.StoreUnlocked))
            .OrderByDescending(a => a.Timestamp).Take(50)
            .Select(a => new { a.Action, a.Details, a.Timestamp, a.UserEmail })
            .ToListAsync();
        var store = await db.Stores.AsNoTracking().Where(s => s.Id == id)
            .Select(s => new { s.RenewalCount, s.ExpiryDate, s.LicenseKey }).FirstOrDefaultAsync();
        return Ok(AppResponse<object>.Success(new { keys, events, store, maxRenewals = 3 }));
    }

    // ─── Key kích hoạt ────────────────────────────────────────────────

    /// <summary>Danh sách key: unused (chưa dùng, còn hiệu lực) / used / revoked; lọc theo gói, đại lý, tìm key / cửa hàng.</summary>
    [HttpGet("licenses")]
    public async Task<ActionResult<AppResponse<object>>> Licenses(
        [FromQuery] string? status, [FromQuery] Guid? packageId, [FromQuery] Guid? agentId, [FromQuery] string? search,
        [FromQuery] int page = 1, [FromQuery] int pageSize = 50)
    {
        var q = db.LicenseKeys.AsNoTracking().AsQueryable();
        if (packageId.HasValue) q = q.Where(k => k.ServicePackageId == packageId);
        if (agentId.HasValue) q = q.Where(k => k.AgentId == agentId);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var t = search.Trim().ToLower();
            q = q.Where(k => k.Key.ToLower().Contains(t) || (k.Store != null && (k.Store.Name.ToLower().Contains(t) || k.Store.Code.ToLower().Contains(t)))
                || (k.Notes != null && k.Notes.ToLower().Contains(t)));
        }
        var counts = new Dictionary<string, int>
        {
            ["unused"] = await q.CountAsync(k => k.IsActive && !k.IsUsed),
            ["used"] = await q.CountAsync(k => k.IsUsed),
            ["revoked"] = await q.CountAsync(k => !k.IsActive && !k.IsUsed),
        };
        counts["all"] = counts["unused"] + counts["used"] + counts["revoked"];
        q = status switch
        {
            "unused" => q.Where(k => k.IsActive && !k.IsUsed),
            "used" => q.Where(k => k.IsUsed),
            "revoked" => q.Where(k => !k.IsActive && !k.IsUsed),
            _ => q,
        };
        var total = await q.CountAsync();
        pageSize = Math.Clamp(pageSize, 10, 200);
        page = Math.Max(1, page);
        var items = await q.OrderByDescending(k => k.ActivatedAt ?? k.CreatedAt)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(k => new
            {
                id = k.Id, k.Key, k.DurationDays, k.IsUsed, k.IsActive, k.ActivatedAt, k.CreatedAt, k.Notes,
                licenseType = k.LicenseType.ToString(),
                packageId = k.ServicePackageId, packageName = k.ServicePackage == null ? null : k.ServicePackage.Name,
                agentId = k.AgentId, agentName = k.Agent == null ? null : k.Agent.Name,
                storeId = k.StoreId, storeName = k.Store == null ? null : k.Store.Name, storeCode = k.Store == null ? null : k.Store.Code,
            })
            .ToListAsync();
        return Ok(AppResponse<object>.Success(new { items, total, page, pageSize, counts }));
    }

    // ─── Đại lý ───────────────────────────────────────────────────────

    [HttpGet("agents")]
    public async Task<ActionResult<AppResponse<object>>> Agents()
    {
        var now = DateTime.UtcNow;
        var since = now.AddDays(-30);
        var agents = await db.Agents.AsNoTracking().OrderBy(a => a.Name)
            .Select(a => new
            {
                id = a.Id, a.Name, a.Code, a.Phone, a.Email, a.Address, a.IsActive, a.MaxStores, a.RenewalDayBalance,
                a.IsRegistrationCompleted, a.LicenseExpiryDate, a.CreatedAt,
                stores = a.Stores.Count,
                activeStores = a.Stores.Count(s => s.IsActive && !s.IsLocked && (s.ExpiryDate == null || s.ExpiryDate > now)),
                expiringStores = a.Stores.Count(s => s.IsActive && s.ExpiryDate > now && s.ExpiryDate <= now.AddDays(7)),
                expiredStores = a.Stores.Count(s => s.ExpiryDate != null && s.ExpiryDate <= now),
                unusedKeys = a.LicenseKeys.Count(k => k.IsActive && !k.IsUsed),
                usedKeys = a.LicenseKeys.Count(k => k.IsUsed),
                activations30 = a.LicenseKeys.Count(k => k.IsUsed && k.ActivatedAt >= since),
                newStores30 = a.Stores.Count(s => s.CreatedAt >= since),
            })
            .ToListAsync();
        return Ok(AppResponse<object>.Success(agents));
    }

    // ─── Tình trạng hệ thống ──────────────────────────────────────────

    /// <summary>Tổng hợp nhanh: database, sao lưu, dung lượng, bảo trì, an ninh 24h, khách sắp hết hạn, tồn key + danh sách cảnh báo.</summary>
    [HttpGet("system-status")]
    public async Task<ActionResult<AppResponse<object>>> SystemStatus()
    {
        var now = DateTime.UtcNow;
        var warnings = new List<object>();
        void Warn(string level, string text, string? tab = null) => warnings.Add(new { level, text, tab });

        var sw = System.Diagnostics.Stopwatch.StartNew();
        var dbOk = true;
        try { await db.Database.ExecuteSqlRawAsync("SELECT 1"); } catch { dbOk = false; }
        sw.Stop();
        if (!dbOk) Warn("danger", "Không kết nối được database", "database");
        else if (sw.ElapsedMilliseconds > 500) Warn("warning", $"Database phản hồi chậm ({sw.ElapsedMilliseconds} ms)", "database");

        DateTime? lastBackup = null;
        var backupCount = 0;
        double backupMb = 0;
        try
        {
            var dir = Path.Combine(Directory.GetCurrentDirectory(), "backups");
            if (Directory.Exists(dir))
            {
                var files = Directory.GetFiles(dir).Select(f => new FileInfo(f)).ToList();
                backupCount = files.Count;
                backupMb = Math.Round(files.Sum(f => f.Length) / 1024.0 / 1024.0, 1);
                lastBackup = files.Count == 0 ? null : files.Max(f => f.CreationTimeUtc);
            }
        }
        catch { /* bỏ qua */ }
        if (lastBackup == null) Warn("warning", "Chưa có bản sao lưu database nào", "database");
        else if (lastBackup < now.AddDays(-2)) Warn("warning", $"Bản sao lưu gần nhất đã {(int)(now - lastBackup.Value).TotalDays} ngày", "database");

        double? diskFreeGb = null, diskTotalGb = null;
        try
        {
            var root = Path.GetPathRoot(Directory.GetCurrentDirectory());
            if (!string.IsNullOrEmpty(root))
            {
                var d = new DriveInfo(root);
                diskFreeGb = Math.Round(d.AvailableFreeSpace / 1024.0 / 1024 / 1024, 1);
                diskTotalGb = Math.Round(d.TotalSize / 1024.0 / 1024 / 1024, 1);
                if (diskTotalGb > 0 && diskFreeGb / diskTotalGb < 0.1) Warn("danger", $"Ổ đĩa máy chủ còn {diskFreeGb} GB", "server");
            }
        }
        catch { /* bỏ qua */ }

        var maint = await db.MaintenanceWindows.AsNoTracking()
            .Where(m => m.IsActive && m.EndAt > now)
            .OrderBy(m => m.StartAt)
            .Select(m => new { m.Title, m.StartAt, m.EndAt, running = m.StartAt <= now, m.BlockAccess })
            .ToListAsync();
        if (maint.Any(m => m.running)) Warn("info", "Đang trong thời gian bảo trì", "maintenance");

        var since = now.AddHours(-24);
        var failedLogins = await db.AuditLogs.AsNoTracking().CountAsync(a => a.Timestamp >= since && a.Action == AuditActions.LoginFailed);
        var impersonations = await db.AuditLogs.AsNoTracking().CountAsync(a => a.Timestamp >= since && a.Action == "Impersonate");
        var deletes = await db.AuditLogs.AsNoTracking().CountAsync(a => a.Timestamp >= since && a.Action == AuditActions.Delete);
        if (failedLogins > 50) Warn("warning", $"{failedLogins} lần đăng nhập sai trong 24 giờ", "audit");

        var expiring = await db.Stores.AsNoTracking().CountAsync(st => st.IsActive && st.ExpiryDate > now && st.ExpiryDate <= now.AddDays(7));
        var expiredToday = await db.Stores.AsNoTracking().CountAsync(st => st.IsActive && st.ExpiryDate > now.AddDays(-1) && st.ExpiryDate <= now);
        if (expiring > 0) Warn("info", $"{expiring} cửa hàng hết hạn trong 7 ngày tới", "stores");

        var unusedKeys = await db.LicenseKeys.AsNoTracking().CountAsync(k => k.IsActive && !k.IsUsed && k.AgentId == null);
        if (unusedKeys < 5) Warn("info", $"Kho key chưa giao chỉ còn {unusedKeys}", "licenses");

        var version = typeof(SystemAdminV2Controller).Assembly.GetName().Version?.ToString();
        var started = System.Diagnostics.Process.GetCurrentProcess().StartTime.ToUniversalTime();

        return Ok(AppResponse<object>.Success(new
        {
            database = new { ok = dbOk, latencyMs = sw.ElapsedMilliseconds },
            backups = new { count = backupCount, totalMb = backupMb, last = lastBackup },
            disk = new { freeGb = diskFreeGb, totalGb = diskTotalGb },
            maintenance = maint,
            security = new { failedLogins, impersonations, deletes },
            stores = new { expiring, expiredToday },
            keys = new { unusedUnassigned = unusedKeys },
            server = new { version, startedAt = started, uptimeHours = Math.Round((now - started).TotalHours, 1), machine = Environment.MachineName },
            warnings,
        }));
    }

    // ─── Tài khoản ────────────────────────────────────────────────────

    private async Task<ApplicationUser?> LoadUserAsync(Guid id) =>
        await userManager.Users.Include(u => u.Store).Include(u => u.Employee).Include(u => u.Manager)
            .FirstOrDefaultAsync(u => u.Id == id);

    private static bool IsProtected(ApplicationUser u) =>
        string.Equals(u.Role, "SuperAdmin", StringComparison.OrdinalIgnoreCase);

    [HttpGet("users/{id:guid}/security")]
    public async Task<ActionResult<AppResponse<object>>> UserSecurity(Guid id)
    {
        var u = await LoadUserAsync(id);
        if (u == null) return Ok(AppResponse<object>.Fail("Không tìm thấy tài khoản"));
        var devices = await db.UserDeviceTokens.AsNoTracking().Where(t => t.UserId == id)
            .Select(t => new { t.Platform, t.DeviceName, t.CreatedAt }).ToListAsync();
        var hasSession = await db.UserRefreshTokens.AsNoTracking().AnyAsync(t => t.ApplicationUserId == id);
        var logins = await db.AuditLogs.AsNoTracking()
            .Where(a => a.UserId == id && (a.Action == AuditActions.Login || a.Action == AuditActions.LoginFailed))
            .OrderByDescending(a => a.Timestamp).Take(10)
            .Select(a => new { a.Action, a.Timestamp, a.IpAddress, a.UserAgent }).ToListAsync();
        return Ok(AppResponse<object>.Success(new
        {
            id = u.Id, u.Email, u.UserName, u.PhoneNumber, name = u.FullName, u.Role, u.IsActive, u.LastLoginAt,
            storeName = u.Store?.Name, storeCode = u.Store?.Code,
            lockedUntil = u.LockoutEnd > DateTimeOffset.UtcNow ? u.LockoutEnd : null,
            failedAttempts = u.AccessFailedCount,
            hasSession, devices, logins,
        }));
    }

    [HttpPost("users/{id:guid}/reset-password")]
    public async Task<ActionResult<AppResponse<object>>> ResetPassword(Guid id)
    {
        var u = await userManager.FindByIdAsync(id.ToString());
        if (u == null) return Ok(AppResponse<object>.Fail("Không tìm thấy tài khoản"));
        if (IsProtected(u)) return Ok(AppResponse<object>.Fail("Không đặt lại mật khẩu Super Admin tại đây"));
        const string alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789";
        var pwd = new string(Enumerable.Range(0, 10).Select(_ => alphabet[RandomNumberGenerator.GetInt32(alphabet.Length)]).ToArray()) + "@1";
        var token = await userManager.GeneratePasswordResetTokenAsync(u);
        var res = await userManager.ResetPasswordAsync(u, token, pwd);
        if (!res.Succeeded) return Ok(AppResponse<object>.Fail(string.Join("; ", res.Errors.Select(e => e.Description))));
        await userManager.SetLockoutEndDateAsync(u, null);
        await userManager.ResetAccessFailedCountAsync(u);
        await db.UserRefreshTokens.Where(t => t.ApplicationUserId == id).ExecuteDeleteAsync();
        await AuditAsync(AuditActions.CredentialsUpdated, AuditEntityTypes.User, id.ToString(), u.Email, "Super Admin đặt lại mật khẩu", u.StoreId);
        try
        {
            await notifications.CreateAndSendAsync(u.Id, NotificationType.Warning, "Mật khẩu đã được đặt lại",
                "Quản trị hệ thống vừa đặt lại mật khẩu tài khoản của bạn. Vui lòng đổi mật khẩu sau khi đăng nhập.",
                categoryCode: "system", storeId: u.StoreId);
        }
        catch { /* thông báo không chặn */ }
        return Ok(AppResponse<object>.Success(new { password = pwd }));
    }

    [HttpPost("users/{id:guid}/unlock")]
    public async Task<ActionResult<AppResponse<bool>>> Unlock(Guid id)
    {
        var u = await userManager.FindByIdAsync(id.ToString());
        if (u == null) return Ok(AppResponse<bool>.Fail("Không tìm thấy tài khoản"));
        await userManager.SetLockoutEndDateAsync(u, null);
        await userManager.ResetAccessFailedCountAsync(u);
        await AuditAsync(AuditActions.Update, AuditEntityTypes.User, id.ToString(), u.Email, "Mở khóa đăng nhập", u.StoreId);
        return Ok(AppResponse<bool>.Success(true));
    }

    [HttpPost("users/{id:guid}/revoke-sessions")]
    public async Task<ActionResult<AppResponse<bool>>> RevokeSessions(Guid id)
    {
        var u = await userManager.FindByIdAsync(id.ToString());
        if (u == null) return Ok(AppResponse<bool>.Fail("Không tìm thấy tài khoản"));
        await db.UserRefreshTokens.Where(t => t.ApplicationUserId == id).ExecuteDeleteAsync();
        await db.UserDeviceTokens.Where(t => t.UserId == id).ExecuteDeleteAsync();
        await userManager.UpdateSecurityStampAsync(u);
        await AuditAsync(AuditActions.Update, AuditEntityTypes.User, id.ToString(), u.Email, "Đăng xuất mọi thiết bị", u.StoreId);
        return Ok(AppResponse<bool>.Success(true));
    }

    /// <summary>
    /// Đăng nhập thay để hỗ trợ khách: cấp access token của người dùng (không cấp refresh token,
    /// hết hạn theo access token), bắt buộc ghi lý do, ghi nhật ký và báo cho chủ cửa hàng.
    /// </summary>
    [HttpPost("users/{id:guid}/impersonate")]
    public async Task<ActionResult<AppResponse<object>>> Impersonate(Guid id, [FromBody] SaImpersonateRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.Reason) || req.Reason.Trim().Length < 5)
            return Ok(AppResponse<object>.Fail("Nhập lý do hỗ trợ (ít nhất 5 ký tự)"));
        var u = await LoadUserAsync(id);
        if (u == null) return Ok(AppResponse<object>.Fail("Không tìm thấy tài khoản"));
        if (IsProtected(u) || string.Equals(u.Role, "Agent", StringComparison.OrdinalIgnoreCase))
            return Ok(AppResponse<object>.Fail("Không đăng nhập thay tài khoản quản trị hệ thống / đại lý"));
        if (!u.IsActive) return Ok(AppResponse<object>.Fail("Tài khoản đang bị vô hiệu hóa"));
        var token = await accessTokenService.GetTokenAsync(u);
        await AuditAsync("Impersonate", AuditEntityTypes.User, id.ToString(), u.Email, $"Đăng nhập thay: {req.Reason.Trim()}", u.StoreId);
        try
        {
            var ownerId = u.Store?.OwnerId;
            if (ownerId.HasValue)
                await notifications.CreateAndSendAsync(ownerId.Value, NotificationType.Info, "Bộ phận hỗ trợ đang truy cập",
                    $"Quản trị SBOX đang đăng nhập thay tài khoản {u.FullName} để hỗ trợ: {req.Reason.Trim()}",
                    categoryCode: "system", storeId: u.StoreId);
        }
        catch { /* thông báo không chặn */ }
        logger.LogWarning("SuperAdmin {Admin} impersonating {User} ({Store}): {Reason}", CurrentUserId, u.Id, u.Store?.Code, req.Reason);
        return Ok(AppResponse<object>.Success(new
        {
            accessToken = token,
            userName = u.FullName,
            email = u.Email,
            storeCode = u.Store?.Code,
            storeName = u.Store?.Name,
        }));
    }
}
