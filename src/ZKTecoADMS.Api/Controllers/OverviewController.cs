using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Api.Services.Shipping;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Trang Tổng quan: gom «việc cần xử lý» của HRM + POS trong MỘT lần gọi
/// (trước đây màn tổng quan gọi hơn 30 API lẻ).
/// </summary>
[ApiController]
[Route("api/overview")]
[Authorize(Policy = PolicyNames.AtLeastManager)]
public class OverviewController(ZKTecoDbContext db) : AuthenticatedControllerBase
{
    public record TodoItem(string Key, string Group, string Label, int Count, string Severity, string? ModuleCode);

    /// <summary>
    /// Đếm việc chờ xử lý. Khối HRM / POS trả về khi gói có module tương ứng
    /// (client lọc tiếp theo quyền người xem).
    /// </summary>
    [HttpGet("todos")]
    public async Task<ActionResult<AppResponse<List<TodoItem>>>> Todos(CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var items = new List<TodoItem>();
        var nowUtc = DateTime.UtcNow;

        // ── HRM ──
        var leaves = await db.Leaves.AsNoTracking()
            .CountAsync(x => x.StoreId == storeId && x.Deleted == null && x.Status == LeaveStatus.Pending, ct);
        var mobile = await db.MobileAttendanceRecords.AsNoTracking()
            .CountAsync(x => x.StoreId == storeId && x.Deleted == null && x.Status == "pending", ct);
        var corrections = await db.AttendanceCorrectionRequests.AsNoTracking()
            .CountAsync(x => x.StoreId == storeId && x.Deleted == null && x.Status == CorrectionStatus.Pending, ct);
        var swaps = await db.ShiftSwapRequests.AsNoTracking()
            .CountAsync(x => x.StoreId == storeId && x.Deleted == null && x.Status == ShiftSwapStatus.TargetAccepted, ct);
        var advances = await db.AdvanceRequests.AsNoTracking()
            .CountAsync(x => x.StoreId == storeId && x.Deleted == null && x.Status == AdvanceRequestStatus.Pending, ct);
        items.Add(new("leave", "hrm", "Đơn nghỉ phép chờ duyệt", leaves, "warning", "Leave"));
        items.Add(new("mobileAttendance", "hrm", "Chấm công mobile chờ duyệt", mobile, "warning", "MobileAttendance"));
        items.Add(new("correction", "hrm", "Yêu cầu sửa công chờ duyệt", corrections, "warning", "AttendanceCorrection"));
        items.Add(new("shiftSwap", "hrm", "Đổi ca chờ quản lý duyệt", swaps, "info", "ShiftSwap"));
        items.Add(new("advance", "hrm", "Ứng lương chờ duyệt", advances, "warning", "Advance"));

        // ── POS ──
        var trackedTypes = new[] { PosProductType.Goods, PosProductType.Material };
        var outOfStock = await db.PosProducts.AsNoTracking()
            .CountAsync(p => p.StoreId == storeId && p.Deleted == null && p.IsActive
                             && trackedTypes.Contains(p.ProductType) && p.OnHandQty <= 0, ct);
        var lowStock = await db.PosProducts.AsNoTracking()
            .CountAsync(p => p.StoreId == storeId && p.Deleted == null && p.IsActive
                             && trackedTypes.Contains(p.ProductType)
                             && p.MinStockQty > 0 && p.OnHandQty > 0 && p.OnHandQty <= p.MinStockQty, ct);
        // Theo «số ngày cảnh báo HSD» của từng hàng; lô đã hết hạn tách riêng (trước: cứng 30 ngày, gộp cả lô hết hạn).
        var expiryLots = await PosStockAlertHelper.ExpiryLotsAsync(db, storeId, ct);
        var expiredLots = expiryLots.Count(l => l.Expired);
        var nearExpiry = expiryLots.Count - expiredLots;
        var onlinePending = await db.PosSaleOrders.AsNoTracking()
            .CountAsync(o => o.StoreId == storeId && o.Deleted == null
                             && o.SalesChannel == QrOnlineOrderStatuses.Channel
                             && o.DeliveryStatus == QrOnlineOrderStatuses.Pending
                             && o.Status != PosSaleOrderStatus.Cancelled, ct);
        var shipIssues = await db.PosSaleOrders.AsNoTracking()
            .CountAsync(o => o.StoreId == storeId && o.Deleted == null && o.IsDelivery
                             && (o.DeliveryStatusCode == ShipmentStatus.DeliveryFailed
                                 || o.DeliveryStatusCode == ShipmentStatus.Returning
                                 || (o.DeliveryStatusCode == ShipmentStatus.Returned && o.DeliveryReturnReceivedAt == null)), ct);
        var codPending = await db.PosSaleOrders.AsNoTracking()
            .CountAsync(o => o.StoreId == storeId && o.Deleted == null && o.IsDelivery
                             && o.DeliveryStatusCode == ShipmentStatus.Delivered
                             && o.DeliveryCodAmount > 0 && o.DeliveryCodSettledAt == null, ct);
        items.Add(new("outOfStock", "pos", "Hàng đã hết", outOfStock, "danger", "PosProducts"));
        items.Add(new("lowStock", "pos", "Hàng dưới tồn tối thiểu", lowStock, "warning", "PosProducts"));
        items.Add(new("expiredLots", "pos", "Lô hàng đã hết hạn (cần xuất hủy)", expiredLots, "danger", "PosReportExpiry"));
        items.Add(new("nearExpiry", "pos", "Lô hàng sắp hết hạn", nearExpiry, "warning", "PosReportExpiry"));
        items.Add(new("onlinePending", "pos", "Đơn online chờ xác nhận", onlinePending, "danger", "PosQrOrder"));
        items.Add(new("shippingIssue", "pos", "Vận đơn giao thất bại / hoàn hàng", shipIssues, "danger", "PosShipping"));
        items.Add(new("codPending", "pos", "Đơn COD chưa đối soát", codPending, "info", "PosShipping"));

        return Ok(AppResponse<List<TodoItem>>.Success(items));
    }
}
