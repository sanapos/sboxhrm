using System.Globalization;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

internal static class PosNotificationHelper
{
    /// <summary>Tiêu đề cũ của cảnh báo tồn thấp theo đơn — nay dùng chung «Hàng cần nhập thêm».</summary>
    private const string LegacyLowStockTitle = "Tồn kho thấp";

    /// <summary>Tiền kiểu Việt: 250000 → «250.000đ».</summary>
    internal static string Vnd(decimal v) =>
        Math.Round(v, 0).ToString("#,0", CultureInfo.InvariantCulture).Replace(',', '.') + "đ";

    /// <summary>Số lượng kiểu Việt: 1200 → «1.200», 0.4 → «0,4».</summary>
    internal static string Qty(decimal v)
    {
        var s = v.ToString("#,0.##", CultureInfo.InvariantCulture);
        return string.Concat(s.Select(c => c == ',' ? '.' : c == '.' ? ',' : c));
    }

    /// <summary>«Đường hết» / «Sữa tươi còn 3 (tối thiểu 10)».</summary>
    internal static string LowStockText(string name, decimal onHand, decimal minStock) =>
        onHand <= 0
            ? $"{name.Trim()} hết"
            : $"{name.Trim()} còn {Qty(onHand)} (tối thiểu {Qty(minStock)})";

    private static readonly string[] ManagerRoles =
    [
        nameof(Roles.Admin),
        nameof(Roles.Director),
        nameof(Roles.Manager),
        nameof(Roles.DepartmentHead),
    ];

    /// <summary>Thu ngân / phục vụ / quản lý — nhận FCM đơn QR và đặt lịch khi app tắt.</summary>
    private static readonly string[] FrontlineRoles =
    [
        nameof(Roles.Admin),
        nameof(Roles.Director),
        nameof(Roles.Manager),
        nameof(Roles.DepartmentHead),
        nameof(Roles.Cashier),
        nameof(Roles.Waiter),
    ];

    public static async Task NotifySaleCompletedAsync(
        ISystemNotificationService notifications,
        ZKTecoDbContext db,
        Guid storeId,
        Guid orderId,
        string orderNo,
        decimal total,
        string? soldBy,
        Guid? fromUserId,
        CancellationToken cancellationToken = default)
    {
        try
        {
            // Chỉ quản lý (+ chủ nếu đúng cửa hàng): số tiền từng đơn là doanh số cửa hàng, thu ngân /
            // phục vụ không cần thấy đơn của người khác (họ xem đơn mình trên màn bán hàng).
            var userIds = await GetPosManagerUserIdsAsync(db, storeId, cancellationToken);
            if (await OwnerAtStoreAsync(db, storeId, cancellationToken) is Guid owner && !userIds.Contains(owner))
                userIds.Add(owner);
            // Người vừa bán đã thấy kết quả ngay trên màn hình — không đẩy lại popup cho chính họ.
            if (fromUserId.HasValue) userIds = userIds.Where(u => u != fromUserId.Value).ToList();
            if (userIds.Count == 0) return;

            // Title = đơn + số tiền (điều chính); body = ai bán · bàn. SoldBy có thể là email (chủ bán) —
            // không in email: formatter tự thêm tên người gửi (fromUserId) vào body.
            var seller = soldBy?.Trim();
            string sellerPart;
            if (string.Equals(seller, "Tingee", StringComparison.OrdinalIgnoreCase))
                sellerPart = "Khách chuyển khoản qua Tingee";
            else if (string.IsNullOrEmpty(seller) || seller.Contains('@'))
                sellerPart = "Đã thanh toán";
            else
                sellerPart = $"{seller} bán";
            var table = await db.PosSaleOrders.AsNoTracking()
                .Where(o => o.Id == orderId && o.ServiceResourceId != null)
                .Join(db.PosServiceResources.AsNoTracking(), o => o.ServiceResourceId, r => (Guid?)r.Id, (o, r) => r.Name)
                .FirstOrDefaultAsync(cancellationToken);
            var title = $"Đơn {orderNo} · {Vnd(total)}";
            var message = string.IsNullOrWhiteSpace(table) ? sellerPart : $"{sellerPart} · {table.Trim()}";

            await notifications.CreateAndSendToUsersAsync(
                userIds,
                NotificationType.Info,
                title,
                message,
                relatedEntityId: orderId,
                relatedEntityType: "PosSaleOrder",
                fromUserId: fromUserId,
                categoryCode: "pos",
                storeId: storeId);
        }
        catch
        {
            // Notification failure must not affect POS checkout.
        }
    }

    /// <summary>
    /// Đơn bàn đã được thanh toán ở nơi khác (máy khác / chuyển khoản tự hoàn tất) mà máy mất mạng cũng đã thu
    /// tiền và in hóa đơn offline cho chính bàn đó → báo quản lý + chủ để kiểm tra có thu hai lần không.
    /// </summary>
    public static async Task NotifyOfflineDoublePaymentAsync(
        ISystemNotificationService notifications,
        ZKTecoDbContext db,
        Guid storeId,
        Guid orderId,
        string title,
        string message,
        CancellationToken cancellationToken = default)
    {
        try
        {
            var userIds = await GetPosManagerUserIdsAsync(db, storeId, cancellationToken);
            if (await OwnerAtStoreAsync(db, storeId, cancellationToken) is Guid owner && !userIds.Contains(owner))
                userIds.Add(owner);
            if (userIds.Count == 0) return;
            await notifications.CreateAndSendToUsersAsync(
                userIds,
                NotificationType.Warning,
                title,
                message,
                relatedEntityId: orderId,
                relatedEntityType: "PosSaleOrder",
                categoryCode: "pos",
                storeId: storeId);
        }
        catch
        {
            // Lỗi gửi thông báo không làm hỏng việc đồng bộ đơn offline.
        }
    }

    public static async Task NotifyPurchaseReceiptCompletedAsync(
        ISystemNotificationService notifications,
        ZKTecoDbContext db,
        Guid storeId,
        Guid receiptId,
        string receiptNo,
        decimal grandTotal,
        string? supplierName,
        Guid? fromUserId,
        CancellationToken cancellationToken = default)
    {
        try
        {
            var userIds = await GetPosManagerUserIdsAsync(db, storeId, cancellationToken);
            if (userIds.Count == 0) return;

            var title = $"Nhập hàng {receiptNo} · {Vnd(grandTotal)}";
            // Không có NCC thì không in «NCC: —»; formatter thêm tên người nhập (fromUserId).
            var message = string.IsNullOrWhiteSpace(supplierName)
                ? "Đã nhập kho"
                : $"NCC {supplierName.Trim()}";

            await notifications.CreateAndSendToUsersAsync(
                userIds,
                NotificationType.Info,
                title,
                message,
                relatedEntityId: receiptId,
                relatedEntityType: "PosPurchaseReceipt",
                fromUserId: fromUserId,
                categoryCode: "pos",
                storeId: storeId);
        }
        catch
        {
            // Notification failure must not affect receipt completion.
        }
    }

    public static async Task NotifyLowStockAsync(
        ISystemNotificationService notifications,
        ZKTecoDbContext db,
        Guid storeId,
        IEnumerable<(Guid ProductId, string ProductName, decimal OnHand, decimal MinStock)> items,
        Guid? fromUserId,
        CancellationToken cancellationToken = default)
    {
        try
        {
            var lowAll = items
                .Where(i => i.MinStock > 0 && i.OnHand <= i.MinStock)
                .ToList();
            if (lowAll.Count == 0) return;

            // Chỉ báo mặt hàng chưa được báo trong ngày — cả báo theo đơn lẫn bản tổng hợp sáng
            // (PosStockAlertBackgroundService) dùng chung tiêu đề «Hàng cần nhập thêm» → không còn 2 thông báo
            // khác tên cho cùng một món. «Tồn kho thấp» = tiêu đề cũ, giữ để không báo lại trong ngày chuyển bản.
            var dayStartUtc = (DateTime.UtcNow + TimeSpan.FromHours(7)).Date - TimeSpan.FromHours(7);
            var todayMsgs = await db.Notifications.AsNoTracking()
                .Where(n => n.StoreId == storeId && n.Timestamp >= dayStartUtc &&
                            (n.Title == PosStockAlertBackgroundService.LowStockTitle || n.Title == LegacyLowStockTitle))
                .Select(n => n.Message)
                .Distinct()
                .ToListAsync(cancellationToken);
            var lowItems = lowAll
                .Where(i => !todayMsgs.Any(m => m.Contains(i.ProductName, StringComparison.OrdinalIgnoreCase)))
                .Take(2)
                .ToList();
            if (lowItems.Count == 0) return;

            var userIds = await GetPosManagerUserIdsAsync(db, storeId, cancellationToken);
            if (fromUserId.HasValue) userIds = userIds.Where(u => u != fromUserId.Value).ToList();
            if (userIds.Count == 0) return;

            var parts = lowItems.Select(i => LowStockText(i.ProductName, i.OnHand, i.MinStock)).ToList();
            if (lowAll.Count > lowItems.Count)
                parts.Add($"+{lowAll.Count - lowItems.Count} món");

            // Không gắn người bán (fromUserId) — tồn thấp không phải việc của người vừa bán; vẫn bỏ họ khỏi người nhận.
            await notifications.CreateAndSendToUsersAsync(
                userIds,
                NotificationType.Warning,
                PosStockAlertBackgroundService.LowStockTitle,
                string.Join(" · ", parts),
                relatedEntityId: lowItems[0].ProductId,
                relatedEntityType: "PosProduct",
                fromUserId: null,
                categoryCode: "pos",
                storeId: storeId);
        }
        catch
        {
            // Notification failure must not affect stock updates.
        }
    }

    public static async Task NotifyQrOnlineOrderAsync(
        ISystemNotificationService notifications,
        ZKTecoDbContext db,
        Guid storeId,
        Guid orderId,
        string orderNo,
        string customerName,
        string phone,
        decimal total,
        CancellationToken cancellationToken = default)
    {
        try
        {
            var userIds = await GetPosOpsUserIdsAsync(
                db, storeId, cancellationToken, "PosQrOrder", "PosSell", "PosKds");
            if (userIds.Count == 0) return;

            // Việc cần làm + số tiền lên title; body = khách · SĐT · mã đơn.
            var title = $"Đơn online {Vnd(total)} — gọi xác nhận";
            var message = string.Join(" · ", new[] { customerName, phone, orderNo }
                .Where(s => !string.IsNullOrWhiteSpace(s))
                .Select(s => s.Trim()));

            await notifications.CreateAndSendToUsersAsync(
                userIds,
                NotificationType.Info,
                title,
                message,
                relatedEntityId: orderId,
                relatedEntityType: "PosQrOnlineOrder",
                fromUserId: null,
                categoryCode: "pos",
                storeId: storeId);
        }
        catch
        {
            // Notification failure must not affect QR online submit.
        }
    }

    public static async Task NotifyQrTableOrderAsync(
        ISystemNotificationService notifications,
        ZKTecoDbContext db,
        Guid storeId,
        Guid orderId,
        string orderNo,
        string tableName,
        string itemPreview,
        bool needsConfirm,
        CancellationToken cancellationToken = default)
    {
        try
        {
            var userIds = await GetPosOpsUserIdsAsync(
                db, storeId, cancellationToken, "PosQrOrder", "PosSell", "PosKds");
            if (userIds.Count == 0) return;

            var title = needsConfirm ? "Đơn QR chờ xác nhận" : "Đơn QR bàn";
            var preview = string.IsNullOrWhiteSpace(itemPreview) ? "có món mới" : itemPreview.Trim();
            // Bàn + món trước, mã đơn ở cuối (ít quan trọng nhất).
            var message = $"{tableName} · {preview} · {orderNo}";

            await notifications.CreateAndSendToUsersAsync(
                userIds,
                NotificationType.Info,
                title,
                message,
                relatedEntityId: orderId,
                relatedEntityType: "PosQrTableOrder",
                fromUserId: null,
                categoryCode: "pos",
                storeId: storeId);
        }
        catch
        {
            // Notification failure must not affect QR table submit.
        }
    }

    public static async Task NotifyReservationCreatedAsync(
        ISystemNotificationService notifications,
        ZKTecoDbContext db,
        Guid storeId,
        Guid reservationId,
        string resourceName,
        string customerName,
        string? phone,
        DateTime reservedAt,
        int guestCount,
        bool hasPreOrder,
        Guid? fromUserId,
        CancellationToken cancellationToken = default)
    {
        try
        {
            var userIds = await GetPosOpsUserIdsAsync(
                db, storeId, cancellationToken, "PosBooking", "PosSell");
            if (userIds.Count == 0) return;

            // Giờ khách đến: lịch có thời lượng → ReservedAt (giờ bắt đầu slot); giữ bàn không thời lượng →
            // ReservedAt = lúc bấm đặt, giờ khách đến nằm ở ReservedUntil. Cả hai lưu UTC → đổi giờ VN.
            DateTime? arrivalUtc = reservedAt;
            var saved = await db.PosResourceReservations.AsNoTracking()
                .Where(r => r.Id == reservationId)
                .Select(r => new { r.ReservedAt, r.ReservedUntil, r.DurationMinutes })
                .FirstOrDefaultAsync(cancellationToken);
            if (saved != null)
                arrivalUtc = saved.DurationMinutes is > 0 ? saved.ReservedAt : saved.ReservedUntil;
            var when = arrivalUtc.HasValue
                ? ZKTecoADMS.Application.Helpers.VnTimeHelper.UtcToVn(arrivalUtc.Value)
                    .ToString("HH:mm dd/MM", CultureInfo.InvariantCulture)
                : null;

            var guests = guestCount < 1 ? 1 : guestCount;
            var title = string.Join(" · ", new[] { $"Đặt lịch {resourceName.Trim()}", when }
                .Where(s => !string.IsNullOrWhiteSpace(s)));
            var message = string.Join(" · ", new[]
                {
                    customerName?.Trim(),
                    string.IsNullOrWhiteSpace(phone) ? null : phone.Trim(),
                    $"{guests} khách",
                    hasPreOrder ? "có đặt món" : null,
                }
                .Where(s => !string.IsNullOrWhiteSpace(s)));

            await notifications.CreateAndSendToUsersAsync(
                userIds,
                NotificationType.Info,
                title,
                message,
                relatedEntityId: reservationId,
                relatedEntityType: "PosResourceReservation",
                fromUserId: fromUserId,
                categoryCode: "pos",
                storeId: storeId);
        }
        catch
        {
            // Notification failure must not affect reservation create.
        }
    }

    /// <summary>«Gửi thu ngân» từ tài khoản Order → người có quyền thanh toán (PosSell · Duyệt), chủ / quản lý.</summary>
    public static async Task NotifyPaymentRequestedAsync(
        ISystemNotificationService notifications,
        ZKTecoDbContext db,
        Guid storeId,
        Guid orderId,
        string message,
        Guid? fromUserId,
        CancellationToken cancellationToken = default)
    {
        try
        {
            var payRoles = await (
                from rp in db.RolePermissions.AsNoTracking()
                join p in db.Permissions.AsNoTracking() on rp.PermissionId equals p.Id
                where rp.IsActive && rp.CanApprove && p.Module == "PosSell"
                    && (rp.StoreId == storeId || rp.StoreId == null)
                select rp.RoleName
            ).Distinct().ToListAsync(cancellationToken);
            payRoles.AddRange([nameof(Roles.Admin), nameof(Roles.Director), nameof(Roles.Manager)]);
            var userIds = await db.Users.AsNoTracking()
                .Where(u => u.IsActive && u.StoreId == storeId && payRoles.Contains(u.Role)
                    && (fromUserId == null || u.Id != fromUserId))
                .Select(u => u.Id)
                .ToListAsync(cancellationToken);
            if (userIds.Count == 0) return;

            await notifications.CreateAndSendToUsersAsync(
                userIds,
                NotificationType.Info,
                "Gửi thu ngân",
                message,
                relatedEntityId: orderId,
                relatedEntityType: "PosSaleOrder",
                fromUserId: fromUserId,
                categoryCode: "pos",
                storeId: storeId);
        }
        catch
        {
            // Lỗi gửi thông báo không làm hỏng thao tác gửi thu ngân (sơ đồ bàn đã báo realtime).
        }
    }

    /// <summary>
    /// Bếp bấm «Ra món» / «Xong»: báo người đã gọi món (người tạo dòng món) để mang ra bàn.
    /// Mỗi đơn một thông báo; bỏ qua người vừa bấm ở bếp và tài khoản không thuộc cửa hàng.
    /// </summary>
    public static async Task NotifyKitchenReadyAsync(
        ISystemNotificationService notifications,
        ZKTecoDbContext db,
        Guid storeId,
        IReadOnlyCollection<(Guid OrderId, string ProductName, decimal Qty, string? OrderedBy)> lines,
        Guid? fromUserId,
        CancellationToken cancellationToken = default)
    {
        try
        {
            if (lines.Count == 0) return;
            var emails = lines
                .Select(l => l.OrderedBy?.Trim())
                .Where(e => !string.IsNullOrEmpty(e))
                .Select(e => e!.ToLowerInvariant())
                .Distinct()
                .ToList();
            if (emails.Count == 0) return;
            var users = await db.Users.AsNoTracking()
                .Where(u => u.IsActive && u.StoreId == storeId && u.Email != null
                    && emails.Contains(u.Email.ToLower())
                    && (fromUserId == null || u.Id != fromUserId))
                .Select(u => new { u.Id, Email = u.Email!.ToLower() })
                .ToListAsync(cancellationToken);
            if (users.Count == 0) return;

            var orderIds = lines.Select(l => l.OrderId).Distinct().ToList();
            var orders = await (
                from o in db.PosSaleOrders.AsNoTracking()
                where orderIds.Contains(o.Id)
                join r in db.PosServiceResources.AsNoTracking() on o.ServiceResourceId equals r.Id into rj
                from r in rj.DefaultIfEmpty()
                select new { o.Id, o.OrderNo, Table = r != null ? r.Name : null }
            ).ToListAsync(cancellationToken);

            foreach (var group in lines.GroupBy(l => l.OrderId))
            {
                var order = orders.FirstOrDefault(o => o.Id == group.Key);
                var place = !string.IsNullOrWhiteSpace(order?.Table)
                    ? order!.Table!.Trim()
                    : $"Đơn {order?.OrderNo}".Trim();
                var items = string.Join(", ", group
                    .GroupBy(l => l.ProductName.Trim())
                    .Select(g => $"{g.Key} ×{g.Sum(x => x.Qty):0.##}"));
                var to = users
                    .Where(u => group.Any(l => string.Equals(l.OrderedBy?.Trim(), u.Email,
                        StringComparison.OrdinalIgnoreCase)))
                    .Select(u => u.Id)
                    .ToList();
                if (to.Count == 0) continue;
                // Không gắn tên người ở bếp (fromUserId) — người nhận chỉ cần biết bàn nào, món gì.
                await notifications.CreateAndSendToUsersAsync(
                    to,
                    NotificationType.Success,
                    $"{place}: món đã xong",
                    $"{items} — mang ra cho khách",
                    relatedEntityId: group.Key,
                    relatedEntityType: "PosSaleOrder",
                    fromUserId: null,
                    categoryCode: "pos",
                    storeId: storeId);
            }
        }
        catch
        {
            // Lỗi gửi thông báo không làm hỏng thao tác ở bếp (màn bếp / sơ đồ bàn đã cập nhật realtime).
        }
    }

    private static async Task<List<Guid>> GetPosOpsUserIdsAsync(
        ZKTecoDbContext db,
        Guid storeId,
        CancellationToken cancellationToken,
        params string[] extraModules)
    {
        var ids = new HashSet<Guid>();

        var roleUsers = await db.Users.AsNoTracking()
            .Where(u => u.IsActive && u.StoreId == storeId && FrontlineRoles.Contains(u.Role))
            .Select(u => u.Id)
            .ToListAsync(cancellationToken);
        foreach (var id in roleUsers)
            ids.Add(id);

        if (await OwnerAtStoreAsync(db, storeId, cancellationToken) is Guid oid)
            ids.Add(oid);

        if (extraModules.Length > 0)
        {
            var rolesWithMod = await (
                from rp in db.RolePermissions.AsNoTracking()
                join p in db.Permissions.AsNoTracking() on rp.PermissionId equals p.Id
                where rp.IsActive && rp.CanView
                    && (rp.StoreId == storeId || rp.StoreId == null)
                    && extraModules.Contains(p.Module)
                select rp.RoleName
            ).Distinct().ToListAsync(cancellationToken);
            if (rolesWithMod.Count > 0)
            {
                var extra = await db.Users.AsNoTracking()
                    .Where(u => u.IsActive && u.StoreId == storeId && rolesWithMod.Contains(u.Role))
                    .Select(u => u.Id)
                    .ToListAsync(cancellationToken);
                foreach (var uid in extra)
                    ids.Add(uid);
            }
        }

        return ids.ToList();
    }

    /// <summary>
    /// Chủ cửa hàng, chỉ khi chủ đang trực thuộc đúng cửa hàng này. Chủ sở hữu nhiều cửa hàng
    /// có StoreId trỏ 1 cửa hàng — tránh điện thoại chủ bị dội QR/đặt lịch/bán hàng của
    /// mọi cửa hàng mình sở hữu (nhận "lung tung từ các shop khác").
    /// </summary>
    private static async Task<Guid?> OwnerAtStoreAsync(
        ZKTecoDbContext db,
        Guid storeId,
        CancellationToken cancellationToken)
    {
        var ownerId = await db.Stores.AsNoTracking()
            .Where(s => s.Id == storeId)
            .Select(s => s.OwnerId)
            .FirstOrDefaultAsync(cancellationToken);
        if (ownerId is not Guid oid || oid == Guid.Empty) return null;
        var atStore = await db.Users.AsNoTracking()
            .AnyAsync(u => u.Id == oid && u.StoreId == storeId, cancellationToken);
        return atStore ? oid : null;
    }

    internal static async Task<List<Guid>> GetPosManagerUserIdsAsync(
        ZKTecoDbContext db,
        Guid storeId,
        CancellationToken cancellationToken)
    {
        return await db.Users.AsNoTracking()
            .Where(u => u.IsActive && u.StoreId == storeId &&
                        ManagerRoles.Contains(u.Role))
            .Select(u => u.Id)
            .Distinct()
            .ToListAsync(cancellationToken);
    }
}
