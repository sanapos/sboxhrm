using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Helpers;

/// <summary>
/// Kích hoạt license key cho cửa hàng — một đường duy nhất cho SuperAdmin (lẻ / hàng loạt) và đại lý.
/// <list type="bullet">
/// <item>Tất cả hoặc không: key nào sai / đã dùng / bị thu hồi / sai phạm vi → không kích key nào.</item>
/// <item>Giữ key (IsUsed) + cộng ngày + cập nhật cửa hàng trong cùng một transaction: lỗi giữa chừng
/// không còn làm key bị tính «đã dùng» mà cửa hàng không được cộng ngày.</item>
/// <item>Kích key luôn cộng ngày, không tính vào giới hạn gia hạn dùng thử (RenewalCount).</item>
/// <item>Đại lý chỉ kích được key đã cấp cho chính mình — không dùng kho key chưa cấp của SuperAdmin.</item>
/// </list>
/// </summary>
public static class LicenseKeyActivator
{
    public const string AgentOnlyOwnKeysMessage =
        "Đại lý chỉ kích hoạt được key đã được cấp cho đại lý. Liên hệ quản trị để được cấp key.";

    public sealed record Outcome(
        bool Ok,
        string? Error,
        IReadOnlyList<LicenseKey> Keys,
        int KeyDays,
        int BonusDays)
    {
        public static Outcome Fail(string error) => new(false, error, [], 0, 0);
    }

    public static string NormalizeKey(string? key) => (key ?? string.Empty).Trim().ToUpperInvariant();

    /// <param name="store">Cửa hàng đang được theo dõi (AsTracking) — được cập nhật và lưu tại đây.</param>
    /// <param name="actingAgentId">Đại lý đang thao tác; null = SuperAdmin.</param>
    /// <param name="bonusDaysResolver">Khuyến mãi theo (gói, số key) — chỉ kích hàng loạt dùng.</param>
    public static async Task<Outcome> ActivateAsync(
        ZKTecoDbContext db,
        Store store,
        IEnumerable<string> keys,
        Guid? actingAgentId,
        string updatedBy,
        Func<Guid?, int, Task<int>>? bonusDaysResolver = null,
        CancellationToken ct = default)
    {
        var wanted = keys.Select(NormalizeKey).Where(k => k.Length > 0).Distinct().ToList();
        if (wanted.Count == 0) return Outcome.Fail("Chưa nhập license key nào");

        var licenses = await db.LicenseKeys.AsNoTracking()
            .Include(l => l.ServicePackage)
            .Where(l => wanted.Contains(l.Key.ToUpper()))
            .ToListAsync(ct);

        foreach (var key in wanted)
        {
            var l = licenses.FirstOrDefault(x => NormalizeKey(x.Key) == key);
            if (l == null || !l.IsActive || l.IsUsed)
                return Outcome.Fail($"License key không hợp lệ hoặc đã được sử dụng: {key}");
            if (actingAgentId.HasValue && l.AgentId != actingAgentId)
                return Outcome.Fail($"{AgentOnlyOwnKeysMessage} (Key: {l.Key})");
            if (!LicenseKeyActivationHelper.CanActivateForStore(l, store))
                return Outcome.Fail($"{LicenseKeyActivationHelper.InvalidScopeMessage} (Key: {l.Key})");
            if (l.DurationDays <= 0)
                return Outcome.Fail($"Key {l.Key} có số ngày sử dụng không hợp lệ ({l.DurationDays}). Liên hệ quản trị.");
        }

        var packageIds = licenses.Select(l => l.ServicePackageId).Where(id => id != null).Distinct().ToList();
        if (packageIds.Count > 1)
            return Outcome.Fail(
                "Tất cả key phải cùng một gói dịch vụ. Không thể kích key thuộc nhiều gói khác nhau.");
        var packageId = packageIds.FirstOrDefault();

        var keyDays = licenses.Sum(l => l.DurationDays);
        var bonusDays = bonusDaysResolver == null
            ? 0
            : Math.Max(0, await bonusDaysResolver(packageId ?? store.ServicePackageId, licenses.Count));

        var relational = db.Database.IsRelational();
        await using var tx = relational && db.Database.CurrentTransaction == null
            ? await db.Database.BeginTransactionAsync(ct)
            : null;

        var now = DateTime.UtcNow;
        foreach (var l in licenses)
        {
            if (!await TryClaimAsync(db, l, store.Id, updatedBy, now, ct))
            {
                if (tx != null) await tx.RollbackAsync(ct);
                db.ChangeTracker.Clear();
                return Outcome.Fail($"{LicenseKeyClaim.AlreadyUsedMessage} (Key: {l.Key})");
            }
        }

        // Cộng thêm ngày vào hạn hiện tại (giữ phần còn lại, kể cả trial).
        store.ExpiryDate = StoreLicenseHelper.ComputeExtendedExpiryDate(store, keyDays + bonusDays);
        var last = licenses[^1];
        store.LicenseKey = string.Join(", ", licenses.Select(l => l.Key));
        store.LicenseType = last.LicenseType;
        store.MaxUsers = licenses.Max(l => l.MaxUsers);
        store.MaxDevices = licenses.Max(l => l.MaxDevices);
        if (packageId != null)
        {
            store.ServicePackageId = packageId;
            var pkg = await db.ServicePackages.AsNoTracking().FirstOrDefaultAsync(p => p.Id == packageId, ct);
            if (pkg != null) StorePackageHelper.ApplyToStore(store, pkg);
        }
        store.IsActive = true;
        store.IsLocked = false;
        store.LockReason = null;
        store.LockedAt = null;
        store.UpdatedAt = now;
        store.UpdatedBy = updatedBy;

        // Lịch sử key của cửa hàng (SystemAdminV2 license-history) đọc sự kiện này.
        db.AuditLogs.Add(new AuditLog
        {
            Id = Guid.NewGuid(),
            Action = AuditActions.LicenseActivated,
            EntityType = AuditEntityTypes.Store,
            EntityId = store.Id.ToString(),
            EntityName = store.Name,
            Details = $"Kích {licenses.Count} key ({string.Join(", ", licenses.Select(l => l.Key))}): +{keyDays} ngày"
                      + (bonusDays > 0 ? $" +{bonusDays} ngày KM" : "")
                      + $", hạn đến {store.ExpiryDate:dd/MM/yyyy}"
                      + (actingAgentId.HasValue ? " — đại lý kích" : ""),
            UserId = Guid.TryParse(updatedBy, out var uid) ? uid : null,
            UserRole = actingAgentId.HasValue ? "Agent" : "SuperAdmin",
            StoreId = store.Id,
            StoreName = store.Name,
            Timestamp = now,
        });

        await db.SaveChangesAsync(ct);
        if (tx != null) await tx.CommitAsync(ct);

        foreach (var l in licenses)
        {
            l.IsUsed = true;
            l.StoreId = store.Id;
            l.ActivatedAt = now;
        }
        return new Outcome(true, null, licenses, keyDays, bonusDays);
    }

    /// <summary>Giữ key nguyên tử: chỉ key còn hiệu lực, chưa dùng mới đổi được (chống kích trùng / thu hồi đúng lúc).</summary>
    private static async Task<bool> TryClaimAsync(
        ZKTecoDbContext db, LicenseKey license, Guid storeId, string updatedBy, DateTime now, CancellationToken ct)
    {
        if (!db.Database.IsRelational())
        {
            var tracked = await db.LicenseKeys.AsTracking().FirstAsync(l => l.Id == license.Id, ct);
            if (tracked.IsUsed || !tracked.IsActive) return false;
            tracked.IsUsed = true;
            tracked.StoreId = storeId;
            tracked.ActivatedAt = now;
            tracked.UpdatedAt = now;
            tracked.UpdatedBy = updatedBy;
            return true;
        }

        var n = await db.LicenseKeys
            .Where(l => l.Id == license.Id && !l.IsUsed && l.IsActive)
            .ExecuteUpdateAsync(u => u
                .SetProperty(l => l.IsUsed, true)
                .SetProperty(l => l.StoreId, storeId)
                .SetProperty(l => l.ActivatedAt, now)
                .SetProperty(l => l.UpdatedAt, now)
                .SetProperty(l => l.UpdatedBy, updatedBy), ct);
        return n == 1;
    }
}
