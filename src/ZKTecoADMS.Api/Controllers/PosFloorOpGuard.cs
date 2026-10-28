using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Chặn đua cho thao tác bàn (tách bill, chuyển / tách / gộp bàn, trả bàn, số khách, báo bếp từ sơ đồ).
/// Trước đây các thao tác này đọc đơn rồi ghi đè, không xét khóa / trạng thái lúc ghi: máy khác đang
/// thanh toán / lưu nháp cùng lúc → đơn đã trả bị gộp sang bàn khác, dòng vừa chuyển đi bị xóa, 2 máy
/// cùng chuyển vào 1 bàn trống.
/// </summary>
public static class PosFloorOpGuard
{
    /// <summary>Máy giữ bàn còn heartbeat trong khoảng này = đang mở bàn thật (cùng ngưỡng «Lấy quyền»).</summary>
    public static readonly TimeSpan ActiveHoldWindow = TimeSpan.FromSeconds(45);

    public const string ChangedMessage = "Bàn vừa thay đổi trên máy khác — tải lại sơ đồ rồi thử lại";

    /// <summary>
    /// Lỗi khi đơn không còn là đơn tạm, hoặc máy khác đang mở bàn (heartbeat gần đây).
    /// Khóa cũ của máy đã thoát / chết (quá 45 giây không gia hạn) không chặn — thao tác bump LockVersion,
    /// máy đó lưu lại sẽ nhận 409 và tải lại. App cũ không gửi deviceId: chỉ chặn khi tài khoản khác giữ.
    /// </summary>
    public static string? Check(
        PosSaleOrder order,
        PosDraftLockHelper.LockActor actor,
        int? expectedLockVersion,
        DateTime? utcNow = null)
    {
        if (order.Status != PosSaleOrderStatus.Draft)
        {
            var no = string.IsNullOrWhiteSpace(order.OrderNo) ? "Đơn" : $"Đơn {order.OrderNo}";
            return $"{no} đã thanh toán hoặc đã đóng — tải lại sơ đồ";
        }

        var now = utcNow ?? DateTime.UtcNow;
        if (PosDraftLockHelper.IsLockActive(order, now) && !PosDraftLockHelper.IsHeldBy(order, actor, now))
        {
            var legacySameUser = string.IsNullOrWhiteSpace(actor.DeviceId)
                && order.LockedByUserId == actor.UserId;
            var lockedAt = order.LockedAt ?? order.UpdatedAt ?? now;
            if (!legacySameUser && now - lockedAt < ActiveHoldWindow)
            {
                var who = string.IsNullOrWhiteSpace(order.LockedByDisplayName)
                    ? "máy khác"
                    : order.LockedByDisplayName!;
                var device = string.IsNullOrWhiteSpace(order.LockedByDeviceName)
                    ? ""
                    : $" · {order.LockedByDeviceName}";
                return $"Bàn đang mở trên {who}{device} — nhờ máy đó thoát về sơ đồ rồi thử lại";
            }
        }

        if (expectedLockVersion.HasValue && expectedLockVersion.Value != order.LockVersion)
            return ChangedMessage;
        return null;
    }

    public static bool IsPostgres(DbContext db) =>
        db.Database.ProviderName?.Contains("Npgsql", StringComparison.OrdinalIgnoreCase) == true;

    /// <summary>
    /// SELECT … FOR UPDATE các đơn (thứ tự id cố định — tránh deadlock). Gọi TRƯỚC khi nạp đơn để đọc
    /// bản mới nhất: thanh toán / lưu nháp đang ghi đơn đó phải xong trước, hoặc chờ thao tác này xong.
    /// </summary>
    public static async Task LockOrderRowsAsync(DbContext db, IEnumerable<Guid?> ids)
    {
        if (!IsPostgres(db) || db.Database.CurrentTransaction == null) return;
        var arr = ids
            .Where(x => x.HasValue && x.Value != Guid.Empty)
            .Select(x => x!.Value)
            .Distinct()
            .ToArray();
        if (arr.Length == 0) return;
        await db.Database.ExecuteSqlInterpolatedAsync(
            $"SELECT 1 FROM \"PosSaleOrders\" WHERE \"Id\" = ANY({arr}) ORDER BY \"Id\" FOR UPDATE");
    }

    /// <summary>Thao tác bàn trong cùng cửa hàng chạy lần lượt (2 máy cùng chuyển vào 1 bàn trống…).</summary>
    public static async Task LockStoreFloorAsync(DbContext db, Guid storeId)
    {
        if (!IsPostgres(db) || db.Database.CurrentTransaction == null) return;
        var key = "posfloor:" + storeId;
        await db.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock(hashtextextended({key}, 0))");
    }

    public static bool IsRace(Exception ex)
    {
        for (var e = ex; e != null; e = e.InnerException)
        {
            if (e is Npgsql.PostgresException { SqlState: "40001" or "40P01" })
                return true;
            if (e is DbUpdateConcurrencyException)
                return true;
        }
        return false;
    }
}
