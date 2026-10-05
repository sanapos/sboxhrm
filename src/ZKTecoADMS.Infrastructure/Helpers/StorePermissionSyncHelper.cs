using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Authorization;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Helpers;

/// <summary>
/// Gói / cửa hàng được thêm chức năng → cấp quyền cho các vai trò theo mẫu vai trò (như lúc tạo cửa hàng).
/// Trước đây quyền vai trò chỉ tạo một lần lúc tạo cửa hàng (lọc theo gói lúc đó), nên tick thêm chức năng
/// vào gói thì thu ngân / quản lý… vẫn không thấy menu.
/// </summary>
public static class StorePermissionSyncHelper
{
    /// <summary>Quyền con không chọn theo gói — đi cùng chức năng cha.</summary>
    static readonly (string Parent, string[] Subs)[] SubModules =
    [
        ("PosSell", ["PosSellPriceEdit", "PosSellDiscount", "PosSellCancelPaid"]),
        ("PosProducts", ["PosViewCost"]),
    ];

    /// <summary>
    /// So chức năng hiện có của cửa hàng với lần đồng bộ trước; chức năng mới thêm được cấp quyền theo mẫu vai trò.
    /// Dòng quyền chủ cửa hàng đã chỉnh (có quyền) không bị ghi đè. Trả về số dòng quyền đã cấp.
    /// </summary>
    public static async Task<int> SyncAsync(ZKTecoDbContext db, Guid storeId, CancellationToken ct = default)
    {
        var store = await db.Stores.AsTracking().FirstOrDefaultAsync(s => s.Id == storeId, ct);
        if (store == null) return 0;

        var allowedList = await StorePackageHelper.ResolveAllowedModulesAsync(db, storeId, ct);
        var allowed = allowedList.ToHashSet(StringComparer.OrdinalIgnoreCase);
        var snapshot = Snapshot(allowed);
        if (store.PermissionSyncedModules == snapshot) return 0;

        // Lần đầu (chưa có mốc): chỉ bổ sung dòng còn thiếu — dòng đang có có thể do chủ cửa hàng bỏ tick.
        var previous = store.PermissionSyncedModules == null
            ? null
            : StorePackageHelper.DeserializeModules(store.PermissionSyncedModules)
                .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var added = AddedModules(previous, allowed);

        var granted = added.Count == 0 ? 0 : await GrantAsync(db, storeId, allowed, added, previous != null, ct);
        store.PermissionSyncedModules = snapshot;
        await db.SaveChangesAsync(ct);
        return granted;
    }

    static string Snapshot(IEnumerable<string> modules) => JsonSerializer.Serialize(
        modules.Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(m => m, StringComparer.OrdinalIgnoreCase).ToList());

    /// <summary>Chức năng mới (kèm quyền con của chức năng cha mới).</summary>
    public static HashSet<string> AddedModules(ISet<string>? previous, ISet<string> allowed)
    {
        var added = new HashSet<string>(
            allowed.Where(m => previous == null || !previous.Contains(m)), StringComparer.OrdinalIgnoreCase);
        foreach (var (parent, subs) in SubModules)
            if (added.Contains(parent))
                foreach (var s in subs) added.Add(s);
        added.RemoveWhere(FeatureModuleCatalog.IsSelfService);
        return added;
    }

    static async Task<int> GrantAsync(
        ZKTecoDbContext db, Guid storeId, HashSet<string> allowed, HashSet<string> added,
        bool overwriteEmptyRows, CancellationToken ct)
    {
        var permIds = await db.Permissions.AsNoTracking()
            .Where(p => added.Contains(p.Module))
            .ToDictionaryAsync(p => p.Id, p => p.Module, ct);
        if (permIds.Count == 0) return 0;

        var defaults = PermissionPresetCatalog.Defaults(PermissionPresetCatalog.Detect(allowed));
        var rows = await db.RolePermissions.AsTracking()
            .Where(r => r.StoreId == storeId)
            .ToListAsync(ct);
        // Vai trò cửa hàng đang dùng; Admin luôn toàn quyền (không cần dòng quyền).
        var roles = rows.Select(r => r.RoleName)
            .Where(r => !r.Equals("Admin", StringComparison.OrdinalIgnoreCase))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
        var now = DateTime.UtcNow;
        var granted = 0;

        foreach (var role in roles)
        {
            if (!defaults.TryGetValue(role, out var presetId)) continue;
            var preset = PermissionPresetCatalog.Build(presetId);
            var displayName = rows.First(r => r.RoleName.Equals(role, StringComparison.OrdinalIgnoreCase)).RoleDisplayName;
            foreach (var (permId, module) in permIds)
            {
                var f = PermissionPresetCatalog.FlagsFor(preset, module, allowed);
                if (!f.V && !f.C && !f.E && !f.D && !f.X && !f.A) continue;

                var row = rows.FirstOrDefault(r => r.PermissionId == permId &&
                                                    r.RoleName.Equals(role, StringComparison.OrdinalIgnoreCase));
                if (row == null)
                {
                    row = new RolePermission
                    {
                        Id = Guid.NewGuid(),
                        StoreId = storeId,
                        RoleName = role,
                        RoleDisplayName = displayName,
                        PermissionId = permId,
                        IsActive = true,
                        CreatedAt = now,
                        CreatedBy = "PackageSync",
                    };
                    db.RolePermissions.Add(row);
                    rows.Add(row);
                }
                else if (!overwriteEmptyRows || row.CanView || row.CanCreate || row.CanEdit ||
                         row.CanDelete || row.CanExport || row.CanApprove)
                {
                    // Đã có quyền (chủ cửa hàng chỉnh) — giữ nguyên.
                    continue;
                }

                row.IsActive = true;
                (row.CanView, row.CanCreate, row.CanEdit, row.CanDelete, row.CanExport, row.CanApprove) =
                    (f.V, f.C, f.E, f.D, f.X, f.A);
                row.UpdatedAt = now;
                row.UpdatedBy = "PackageSync";
                granted++;
            }
        }
        return granted;
    }

    /// <summary>
    /// Ghi mốc chức năng hiện tại cho cửa hàng chưa có mốc (không cấp quyền) — để lần sửa gói sau
    /// biết đúng chức năng nào là mới. Gọi lúc khởi động và trước khi sửa gói / chức năng riêng.
    /// </summary>
    public static async Task<int> EnsureBaselineAsync(ZKTecoDbContext db, IEnumerable<Guid>? storeIds = null, CancellationToken ct = default)
    {
        var q = db.Stores.AsTracking().Where(s => s.PermissionSyncedModules == null);
        if (storeIds != null)
        {
            var ids = storeIds.ToList();
            q = q.Where(s => ids.Contains(s.Id));
        }
        var stores = await q.ToListAsync(ct);
        foreach (var s in stores)
        {
            var allowed = await StorePackageHelper.ResolveAllowedModulesAsync(db, s.Id, ct);
            s.PermissionSyncedModules = Snapshot(allowed);
        }
        if (stores.Count > 0) await db.SaveChangesAsync(ct);
        return stores.Count;
    }

    /// <summary>Đồng bộ mọi cửa hàng dùng gói (sau khi Super Admin sửa chức năng của gói).</summary>
    public static async Task<int> SyncPackageStoresAsync(ZKTecoDbContext db, Guid packageId, CancellationToken ct = default)
    {
        var storeIds = await db.Stores.AsNoTracking()
            .Where(s => s.ServicePackageId == packageId)
            .Select(s => s.Id)
            .ToListAsync(ct);
        var total = 0;
        foreach (var id in storeIds)
            total += await SyncAsync(db, id, ct);
        return total;
    }
}
