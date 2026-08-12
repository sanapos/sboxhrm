using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Khóa độc quyền Draft giữa nhiều máy.
/// HĐ trống cũng có thể bị «chiếm chỗ» (seat) khi thu ngân chọn tab — tránh 2 máy dùng chung.
/// Xóa hết hàng / unlock / hết TTL → nhả chỗ.
/// </summary>
public static class PosDraftLockHelper
{
    /// <summary>TTL khi đơn đã có hàng.</summary>
    public static readonly TimeSpan DefaultTtl = TimeSpan.FromMinutes(10);

    /// <summary>TTL ngắn cho chỗ ngồi HĐ trống (đi khỏi tab / quên → tự nhả).</summary>
    public static readonly TimeSpan EmptySeatTtl = TimeSpan.FromMinutes(2);

    public sealed record LockActor(
        Guid UserId,
        Guid? EmployeeId,
        string DisplayName,
        string? DeviceId,
        string? DeviceName);

    public sealed record LockSnapshot(
        int LockVersion,
        bool IsLocked,
        bool IsLockedByMe,
        Guid? LockedByUserId,
        Guid? LockedByEmployeeId,
        string? LockedByDisplayName,
        string? LockedByDeviceId,
        string? LockedByDeviceName,
        DateTime? LockedAt,
        DateTime? LockExpiresAt);

    public static bool IsLockActive(PosSaleOrder order, DateTime? utcNow = null)
    {
        var now = utcNow ?? DateTime.UtcNow;
        return order.Status == PosSaleOrderStatus.Draft
            && order.LockedByUserId.HasValue
            && order.LockExpiresAt.HasValue
            && order.LockExpiresAt.Value > now;
    }

    /// <summary>Khóa độc quyền khi còn hiệu lực (TTL chưa hết).</summary>
    public static bool IsEffectivelyLocked(PosSaleOrder order, int lineCount, DateTime? utcNow = null)
        => IsLockActive(order, utcNow);

    public static int CountActiveLines(PosSaleOrder order)
        => order.Lines?.Count(l => l.Deleted == null) ?? 0;

    public static TimeSpan TtlForLineCount(int lineCount)
        => lineCount > 0 ? DefaultTtl : EmptySeatTtl;

    public static bool IsHeldBy(PosSaleOrder order, LockActor actor, DateTime? utcNow = null)
    {
        if (!IsLockActive(order, utcNow) || order.LockedByUserId != actor.UserId)
            return false;
        var orderDevice = (order.LockedByDeviceId ?? "").Trim();
        var actorDevice = (actor.DeviceId ?? "").Trim();
        // Khóa cũ chưa gắn máy → client có deviceId phải claim, không coi là holder.
        if (orderDevice.Length == 0)
            return actorDevice.Length == 0;
        // Đơn đã gắn máy: bắt buộc khớp device (tránh 2 máy cùng account đè nhau).
        if (actorDevice.Length == 0)
            return false;
        return string.Equals(orderDevice, actorDevice, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>Gắn deviceId vào khóa cũ (thiếu máy) — lần heartbeat/lưu đầu tiên «ghim» máy.</summary>
    public static void StampDeviceIfMissing(PosSaleOrder order, LockActor actor)
    {
        if (!string.IsNullOrWhiteSpace(order.LockedByDeviceId))
            return;
        if (string.IsNullOrWhiteSpace(actor.DeviceId))
            return;
        order.LockedByDeviceId = Truncate(actor.DeviceId, 80);
        order.LockedByDeviceName = Truncate(actor.DeviceName, 120);
    }

    /// <summary>Probe khóa từ snapshot DB (AsNoTracking) — phát hiện bị cướp giữa chừng request.</summary>
    public static string? EnsureHeldByLiveSnapshot(
        Guid? lockedByUserId,
        string? lockedByDeviceId,
        string? lockedByDisplayName,
        string? lockedByDeviceName,
        DateTime? lockExpiresAt,
        PosSaleOrderStatus status,
        LockActor actor,
        int liveLockVersion,
        int? expectedLockVersion,
        DateTime? utcNow = null)
    {
        var probe = new PosSaleOrder
        {
            Status = status,
            LockedByUserId = lockedByUserId,
            LockedByDeviceId = lockedByDeviceId,
            LockedByDisplayName = lockedByDisplayName,
            LockedByDeviceName = lockedByDeviceName,
            LockExpiresAt = lockExpiresAt,
            LockVersion = liveLockVersion,
        };
        return EnsureCanMutate(probe, actor, expectedLockVersion, utcNow);
    }

    public static LockSnapshot Snapshot(PosSaleOrder order, LockActor? actor, int? lineCount = null)
    {
        var lines = lineCount ?? (order.Lines != null ? CountActiveLines(order) : 0);
        var locked = IsEffectivelyLocked(order, lines);
        var byMe = locked && actor != null && IsHeldBy(order, actor);
        return new(
            order.LockVersion,
            locked,
            byMe,
            locked ? order.LockedByUserId : null,
            locked ? order.LockedByEmployeeId : null,
            locked ? order.LockedByDisplayName : null,
            locked ? order.LockedByDeviceId : null,
            locked ? order.LockedByDeviceName : null,
            locked ? order.LockedAt : null,
            locked ? order.LockExpiresAt : null);
    }

    /// <summary>
    /// Gán / gia hạn lock. Empty seat: bumpVersion=false mặc định (caller quyết).
    /// </summary>
    public static string? TryAcquire(
        PosSaleOrder order,
        LockActor actor,
        bool force,
        bool bumpVersion,
        TimeSpan? ttl = null,
        DateTime? utcNow = null,
        int? lineCount = null)
    {
        if (order.Status != PosSaleOrderStatus.Draft)
            return "Chỉ khóa được đơn tạm";

        var now = utcNow ?? DateTime.UtcNow;
        var lines = lineCount ?? (order.Lines != null ? CountActiveLines(order) : 0);
        var heldByOther = IsLockActive(order, now) && !IsHeldBy(order, actor, now);
        if (heldByOther && !force)
        {
            var who = string.IsNullOrWhiteSpace(order.LockedByDisplayName)
                ? "người khác"
                : order.LockedByDisplayName!;
            var device = string.IsNullOrWhiteSpace(order.LockedByDeviceName)
                ? ""
                : $" · {order.LockedByDeviceName}";
            return $"Đơn đang được mở bởi {who}{device}";
        }

        var stealing = heldByOther && force;
        order.LockedByUserId = actor.UserId;
        order.LockedByEmployeeId = actor.EmployeeId;
        order.LockedByDisplayName = Truncate(actor.DisplayName, 200);
        if (!string.IsNullOrWhiteSpace(actor.DeviceId) || stealing || !IsLockActive(order, now))
        {
            order.LockedByDeviceId = Truncate(actor.DeviceId, 80);
            order.LockedByDeviceName = Truncate(actor.DeviceName, 120);
        }
        order.LockedAt = now;
        order.LockExpiresAt = now.Add(ttl ?? TtlForLineCount(lines));
        if (bumpVersion || stealing)
            order.LockVersion = Math.Max(0, order.LockVersion) + 1;
        order.UpdatedAt = now;
        return null;
    }

    public static string? TryRenew(PosSaleOrder order, LockActor actor, TimeSpan? ttl = null, DateTime? utcNow = null, int? lineCount = null)
    {
        if (order.Status != PosSaleOrderStatus.Draft)
            return "Chỉ gia hạn được đơn tạm";
        var now = utcNow ?? DateTime.UtcNow;
        if (!IsHeldBy(order, actor, now))
            return "Bạn không đang giữ đơn này";
        StampDeviceIfMissing(order, actor);
        // Sau khi ghim máy: nếu device lệch (máy khác cùng user) → không renew.
        if (!IsHeldBy(order, actor, now))
            return "Bạn không đang giữ đơn này";
        var lines = lineCount ?? (order.Lines != null ? CountActiveLines(order) : 0);
        order.LockedAt = now;
        order.LockExpiresAt = now.Add(ttl ?? TtlForLineCount(lines));
        order.UpdatedAt = now;
        return null;
    }

    /// <summary>Bump LockVersion sau thao tác nền (báo bếp…) để client đồng bộ expectedLockVersion.</summary>
    public static void BumpVersionOnly(PosSaleOrder order, DateTime? utcNow = null)
    {
        order.LockVersion = Math.Max(0, order.LockVersion) + 1;
        order.UpdatedAt = utcNow ?? DateTime.UtcNow;
    }

    public static void Release(PosSaleOrder order, DateTime? utcNow = null)
    {
        order.LockedByUserId = null;
        order.LockedByEmployeeId = null;
        order.LockedByDisplayName = null;
        order.LockedByDeviceId = null;
        order.LockedByDeviceName = null;
        order.LockedAt = null;
        order.LockExpiresAt = null;
        // Bump version để PUT autosave đang bay (expectedLockVersion cũ) bị conflict — không gắn lại khóa.
        order.LockVersion = Math.Max(0, order.LockVersion) + 1;
        order.UpdatedAt = utcNow ?? DateTime.UtcNow;
    }

    /// <summary>
    /// Chỉ holder (cùng user+device) được sửa Draft khi khóa còn hiệu lực.
    /// expectedLockVersion lệch → báo xung đột để client hydrate lại.
    /// </summary>
    public static string? EnsureCanMutate(
        PosSaleOrder order,
        LockActor actor,
        int? expectedLockVersion,
        DateTime? utcNow = null)
    {
        if (order.Status != PosSaleOrderStatus.Draft)
            return "Chỉ sửa được đơn tạm";

        var now = utcNow ?? DateTime.UtcNow;
        if (IsLockActive(order, now) && !IsHeldBy(order, actor, now))
        {
            var who = string.IsNullOrWhiteSpace(order.LockedByDisplayName)
                ? "người khác"
                : order.LockedByDisplayName!;
            var device = string.IsNullOrWhiteSpace(order.LockedByDeviceName)
                ? ""
                : $" · {order.LockedByDeviceName}";
            return $"Đơn đang được mở bởi {who}{device}";
        }

        // Client gửi expected → luôn so khớp (kể cả 0) để tránh 2 máy LWW khi TTL hết.
        if (expectedLockVersion.HasValue
            && expectedLockVersion.Value != order.LockVersion)
        {
            return "Đơn đã thay đổi trên máy khác — tải lại rồi thử lại";
        }

        return null;
    }

    /// <summary>
    /// Sau lưu Draft: bump version + gia hạn/gán khóa.
    /// Không ghi đè khóa máy khác đang giữ. Gán mới chỉ khi chưa có khóa hiệu lực
    /// (tạo đơn / TTL hết). ReconcileLockFieldsBeforeSaveAsync chặn gắn lại sau unlock.
    /// </summary>
    public static void BumpAfterSuccessfulSave(
        PosSaleOrder order, LockActor actor, int lineCount, DateTime? utcNow = null)
    {
        var now = utcNow ?? DateTime.UtcNow;
        order.LockVersion = Math.Max(0, order.LockVersion) + 1;
        order.UpdatedAt = now;
        // Máy khác đang giữ — chỉ bump version nội dung, không đụng LockedBy*.
        if (IsLockActive(order, now) && !IsHeldBy(order, actor, now))
            return;
        order.LockedByUserId = actor.UserId;
        order.LockedByEmployeeId = actor.EmployeeId;
        order.LockedByDisplayName = Truncate(actor.DisplayName, 200);
        // Client cũ không gửi deviceId → không xóa device đang gắn.
        if (!string.IsNullOrWhiteSpace(actor.DeviceId))
        {
            order.LockedByDeviceId = Truncate(actor.DeviceId, 80);
            order.LockedByDeviceName = Truncate(actor.DeviceName, 120);
        }
        order.LockedAt = now;
        order.LockExpiresAt = now.Add(TtlForLineCount(lineCount));
    }

    public static void AssignOnCreate(PosSaleOrder order, LockActor actor, TimeSpan? ttl = null, DateTime? utcNow = null)
    {
        var now = utcNow ?? DateTime.UtcNow;
        order.LockedByUserId = actor.UserId;
        order.LockedByEmployeeId = actor.EmployeeId;
        order.LockedByDisplayName = Truncate(actor.DisplayName, 200);
        order.LockedByDeviceId = Truncate(actor.DeviceId, 80);
        order.LockedByDeviceName = Truncate(actor.DeviceName, 120);
        order.LockedAt = now;
        order.LockExpiresAt = now.Add(ttl ?? DefaultTtl);
        if (order.LockVersion <= 0)
            order.LockVersion = 1;
    }

    static string? Truncate(string? value, int max)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        var t = value.Trim();
        return t.Length <= max ? t : t[..max];
    }
}
