using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Hubs;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Dọn dẹp định kỳ cho QR / đơn online / đặt bàn:
///  • đặt bàn quá giờ + thời gian chờ → «Không đến» (cọc giữ → mất cọc), không phải chờ ai bấm;
///  • đơn online chờ xác nhận quá lâu → tự hủy, nhả tồn đang giữ chỗ (tránh spam khóa tồn khả dụng);
///  • đơn nháp QR tại bàn do khách tự mở, chưa vào bếp, chưa thu tiền, bỏ quên → hủy, đóng phiên.
/// Cấu hình: QrOnline:AutoCancelHours (mặc định 24, 0 = tắt), QrTable:AutoCancelHours (mặc định 24, 0 = tắt).
/// </summary>
public class PosQrMaintenanceBackgroundService(
    IServiceProvider sp, IConfiguration config, ILogger<PosQrMaintenanceBackgroundService> logger)
    : BackgroundService
{
    const int NoShowGraceMinutes = 15;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await Task.Delay(TimeSpan.FromMinutes(3), stoppingToken);
        while (!stoppingToken.IsCancellationRequested)
        {
            try { await RunOnceAsync(stoppingToken); }
            catch (Exception ex) { logger.LogError(ex, "PosQrMaintenance run failed"); }
            await Task.Delay(TimeSpan.FromMinutes(10), stoppingToken);
        }
    }

    internal async Task RunOnceAsync(CancellationToken ct)
    {
        using var scope = sp.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();

        // 0) Dọn bảng chỉ tăng: nhật ký chống gửi trùng QR (>7 ngày), thông báo hẹn giờ đã xử lý (>90 ngày)
        try
        {
            var logCut = DateTime.UtcNow.AddDays(-7);
            await db.PosQrRequestLogs.IgnoreQueryFilters().Where(x => x.CreatedAt < logCut).ExecuteDeleteAsync(ct);
            var schedCut = DateTime.UtcNow.AddDays(-90);
            await db.StoreScheduledNotifications.IgnoreQueryFilters()
                .Where(x => x.Status != StoreNotificationBroadcast.Pending && x.SendAt < schedCut)
                .ExecuteDeleteAsync(ct);
        }
        catch (Exception ex) { logger.LogWarning(ex, "PosQrMaintenance cleanup failed"); }

        // 1) Đặt bàn quá hạn → Không đến
        var cutoff = DateTime.UtcNow.AddMinutes(-NoShowGraceMinutes);
        var storeIds = await db.PosResourceReservations.AsNoTracking()
            .Where(x => x.Deleted == null && x.Status == PosResourceReservationStatus.Booked
                        && x.ReservedUntil != null && x.ReservedUntil < cutoff && x.ReservedAt <= cutoff)
            .Select(x => x.StoreId).Distinct().ToListAsync(ct);
        foreach (var sid in storeIds)
        {
            try
            {
                if (await ExpireOverdueReservationsAsync(db, sid, "system", NoShowGraceMinutes) > 0)
                    PosFloorRealtimeHelper.Notify(sp.GetService<IHubContext<AttendanceHub>>(), sid, "reservationNoShow");
            }
            catch (Exception ex) { logger.LogWarning(ex, "No-show store {StoreId} failed", sid); }
            db.ChangeTracker.Clear();
        }

        // 2) Đơn online chờ xác nhận quá lâu
        var onlineHours = config.GetValue("QrOnline:AutoCancelHours", 24);
        if (onlineHours > 0)
        {
            var until = DateTime.UtcNow.AddHours(-onlineHours);
            var ids = await db.PosSaleOrders.AsNoTracking()
                .Where(o => o.Deleted == null && o.SalesChannel == QrOnlineOrderStatuses.Channel
                            && o.Status == PosSaleOrderStatus.Draft && o.CreatedAt < until
                            && (o.DeliveryStatus == null || o.DeliveryStatus == "" ||
                                o.DeliveryStatus == QrOnlineOrderStatuses.Pending))
                .OrderBy(o => o.CreatedAt).Select(o => o.Id).Take(100).ToListAsync(ct);
            await CancelStaleDraftsAsync(db, ids, $"Tự hủy: quá {onlineHours} giờ chưa xác nhận", online: true, ct);
        }

        // 3) Đơn nháp QR tại bàn bị bỏ quên
        var tableHours = config.GetValue("QrTable:AutoCancelHours", 24);
        if (tableHours > 0)
        {
            var until = DateTime.UtcNow.AddHours(-tableHours);
            var ids = await db.PosSaleOrders.AsNoTracking()
                .Where(o => o.Deleted == null && o.SalesChannel == "QR bàn" && o.Status == PosSaleOrderStatus.Draft
                            && o.CreatedBy == "QR khách" && o.PaidAmount <= 0
                            && (o.UpdatedAt ?? o.CreatedAt) < until
                            && !o.Lines.Any(l => l.Deleted == null && l.KitchenSentQty > 0))
                .OrderBy(o => o.CreatedAt).Select(o => o.Id).Take(100).ToListAsync(ct);
            await CancelStaleDraftsAsync(db, ids, $"Tự hủy: quá {tableHours} giờ không xử lý", online: false, ct);
        }
    }

    /// <summary>Đánh «Không đến» các lịch Booked quá giờ + thời gian chờ; cọc Held → Forfeited.</summary>
    public static async Task<int> ExpireOverdueReservationsAsync(
        ZKTecoDbContext db, Guid storeId, string actor, int graceMinutes)
    {
        var cutoff = DateTime.UtcNow.AddMinutes(-graceMinutes);
        var overdue = await db.PosResourceReservations.AsTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null
                        && x.Status == PosResourceReservationStatus.Booked
                        && x.ReservedUntil != null && x.ReservedUntil < cutoff && x.ReservedAt <= cutoff)
            .ToListAsync();
        if (overdue.Count == 0) return 0;
        var now = DateTime.UtcNow;
        foreach (var x in overdue)
        {
            x.Status = PosResourceReservationStatus.NoShow;
            if (x.DepositStatus == PosReservationDepositStatus.Held && x.DepositPaid > 0)
            {
                x.DepositStatus = PosReservationDepositStatus.Forfeited;
                await PosFinanceSyncHelper.ReclassifyDepositOnForfeitAsync(db, x);
            }
            x.UpdatedAt = now;
            x.UpdatedBy = actor;
            x.IsActive = false;
        }
        await db.SaveChangesAsync();
        return overdue.Count;
    }

    async Task CancelStaleDraftsAsync(ZKTecoDbContext db, List<Guid> ids, string reason, bool online, CancellationToken ct)
    {
        foreach (var id in ids)
        {
            if (ct.IsCancellationRequested) return;
            try
            {
                db.ChangeTracker.Clear();
                var order = await db.PosSaleOrders.AsTracking().Include(o => o.Lines)
                    .FirstOrDefaultAsync(o => o.Id == id && o.Deleted == null && o.Status == PosSaleOrderStatus.Draft, ct);
                if (order == null) continue;
                var prior = order.Lines.Where(l => l.Deleted == null)
                    .Select(l => (l.ProductId, l.Qty, l.VariantId, l.UnitId, l.ToppingsJson)).ToList();
                if (prior.Count > 0)
                    await PosSaleStockHelper.SyncDraftStockReservationAsync(db, order.StoreId, prior, [], true);
                var now = DateTime.UtcNow;
                order.Status = PosSaleOrderStatus.Cancelled;
                if (online) order.DeliveryStatus = QrOnlineOrderStatuses.Cancelled;
                order.Note = string.IsNullOrWhiteSpace(order.Note) ? reason : $"{order.Note} · {reason}";
                order.UpdatedAt = now;
                order.UpdatedBy = "system";
                if (!online && order.ResourceSessionId.HasValue)
                {
                    var sess = await db.PosResourceSessions.AsTracking()
                        .FirstOrDefaultAsync(s => s.Id == order.ResourceSessionId && s.Deleted == null, ct);
                    if (sess != null && sess.Status != PosResourceSessionStatus.Closed)
                    {
                        sess.Status = PosResourceSessionStatus.Closed;
                        sess.EndedAt = now;
                        sess.UpdatedAt = now;
                        sess.UpdatedBy = "system";
                    }
                }
                await db.SaveChangesAsync(ct);
                // Bàn / đơn online trên các máy cập nhật ngay (không đợi vòng hỏi).
                PosFloorRealtimeHelper.Notify(sp.GetService<IHubContext<AttendanceHub>>(), order.StoreId,
                    online ? "qrOnlineStatus" : "draftCancelled",
                    orderId: order.Id, resourceId: order.ServiceResourceId, sessionId: order.ResourceSessionId);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Auto-cancel draft {OrderId} failed", id);
            }
        }
    }
}
