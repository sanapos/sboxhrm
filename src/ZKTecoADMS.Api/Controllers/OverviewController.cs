using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Api.Services.Shipping;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Helpers;
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
        var todayVn = VnTimeHelper.NowVn().Date;
        var regs = await db.ScheduleRegistrations.AsNoTracking()
            .CountAsync(x => x.StoreId == storeId && x.Deleted == null && x.Status == ScheduleRegistrationStatus.Pending
                             && x.Date >= todayVn, ct);
        items.Add(new("scheduleReg", "hrm", "Đăng ký ca chờ duyệt", regs, "warning", "WorkSchedule"));
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

    public record HighlightItem(string Id, string Title, string? Detail, DateTime? When);

    /// <summary>
    /// Tin mới cho Tổng quan: truyền thông nội bộ, công việc, KPI, phản ánh, sản lượng.
    /// Mỗi khối có <c>hasNews</c> — client chỉ hiện khối có tin mới (và người xem có quyền module).
    /// </summary>
    [HttpGet("highlights")]
    public async Task<ActionResult<AppResponse<object>>> Highlights(CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var nowUtc = DateTime.UtcNow;
        var todayVn = VnTimeHelper.NowVn().Date;
        var todayStartUtc = todayVn.AddHours(-7);
        var since3dUtc = nowUtc.AddDays(-3);

        // ── Truyền thông nội bộ: bài đăng 3 ngày gần đây ──
        var commQ = db.InternalCommunications.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Status == CommunicationStatus.Published
                        && x.PublishedAt != null && x.PublishedAt >= since3dUtc && x.PublishedAt <= nowUtc);
        var commCount = await commQ.CountAsync(ct);
        var commItems = await commQ.OrderByDescending(x => x.PublishedAt).Take(3)
            .Select(x => new HighlightItem(x.Id.ToString(), x.Title, x.AuthorName, x.PublishedAt))
            .ToListAsync(ct);

        // ── Công việc ──
        var openStatuses = new[] { WorkTaskStatus.Completed, WorkTaskStatus.Cancelled };
        var taskBase = db.WorkTasks.AsNoTracking().Where(x => x.StoreId == storeId && x.Deleted == null);
        var tasksNewToday = await taskBase.CountAsync(x => x.CreatedAt >= todayStartUtc, ct);
        var tasksOverdue = await taskBase.CountAsync(x => !openStatuses.Contains(x.Status)
            && x.DueDate != null && x.DueDate < todayStartUtc, ct);
        var tasksDueToday = await taskBase.CountAsync(x => !openStatuses.Contains(x.Status)
            && x.DueDate != null && x.DueDate >= todayStartUtc && x.DueDate < todayStartUtc.AddDays(1), ct);
        var tasksDoneToday = await taskBase.CountAsync(x => x.Status == WorkTaskStatus.Completed
            && x.CompletedDate != null && x.CompletedDate >= todayStartUtc, ct);
        var taskItems = await taskBase
            .Where(x => (x.CreatedAt >= todayStartUtc)
                        || (!openStatuses.Contains(x.Status) && x.DueDate != null && x.DueDate < todayStartUtc.AddDays(1)))
            .OrderBy(x => x.DueDate == null).ThenBy(x => x.DueDate).Take(3)
            .Select(x => new HighlightItem(x.Id.ToString(), x.Title,
                x.DueDate != null && x.DueDate < todayStartUtc ? "Quá hạn" : x.CreatedAt >= todayStartUtc ? "Mới giao" : "Hạn hôm nay",
                x.DueDate))
            .ToListAsync(ct);

        // ── KPI: kết quả cập nhật trong 24 giờ + kỳ đang chạy ──
        var since1dUtc = nowUtc.AddDays(-1);
        var kpiNew = await db.KpiResults.AsNoTracking()
            .CountAsync(x => x.StoreId == storeId && x.Deleted == null
                             && (x.CreatedAt >= since1dUtc || (x.LastModified != null && x.LastModified >= since1dUtc)), ct);
        var period = await db.KpiPeriods.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.PeriodStart <= todayVn && p.PeriodEnd >= todayVn)
            .OrderByDescending(p => p.PeriodStart)
            .Select(p => new { p.Id, p.Name })
            .FirstOrDefaultAsync(ct);
        double? kpiAvg = null;
        var kpiItems = new List<HighlightItem>();
        var kpiTargets = 0;
        if (period != null)
        {
            var targets = await db.KpiEmployeeTargets.AsNoTracking()
                .Where(t => t.KpiPeriodId == period.Id && t.Deleted == null)
                .Select(t => new { t.EmployeeId, t.CompletionRate, t.Employee.LastName, t.Employee.FirstName })
                .ToListAsync(ct);
            kpiTargets = targets.Count;
            if (targets.Count > 0)
            {
                kpiAvg = Math.Round((double)targets.Average(t => t.CompletionRate), 1);
                kpiItems = targets.GroupBy(t => t.EmployeeId)
                    .Select(g => new { g.First().LastName, g.First().FirstName, Rate = g.Average(x => x.CompletionRate) })
                    .OrderByDescending(x => x.Rate).Take(3)
                    .Select(x => new HighlightItem("", $"{x.LastName} {x.FirstName}".Trim(), $"{x.Rate:0.#}%", null))
                    .ToList();
            }
        }

        // ── Phản ánh / ý kiến ──
        var fbBase = db.Feedbacks.AsNoTracking().Where(x => x.StoreId == storeId && x.Deleted == null);
        var fbPending = await fbBase.CountAsync(x => x.Status == "Pending" || x.Status == "InProgress", ct);
        var fbNew = await fbBase.CountAsync(x => x.CreatedAt >= since3dUtc, ct);
        var fbItems = await fbBase.Where(x => x.Status == "Pending" || x.Status == "InProgress" || x.CreatedAt >= since3dUtc)
            .OrderByDescending(x => x.CreatedAt).Take(3)
            .Select(x => new HighlightItem(x.Id.ToString(), x.Title,
                x.IsAnonymous || x.SenderEmployee == null ? "Ẩn danh" : (x.SenderEmployee.LastName + " " + x.SenderEmployee.FirstName),
                x.CreatedAt))
            .ToListAsync(ct);

        // ── Sản lượng hôm nay ──
        var prodToday = db.ProductionEntries.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null && x.WorkDate >= todayVn && x.WorkDate < todayVn.AddDays(1));
        var prodRows = await prodToday
            .Select(x => new { x.EmployeeId, x.Quantity, x.Amount, Product = x.ProductItem.Name })
            .ToListAsync(ct);
        var prodItems = prodRows.GroupBy(x => x.Product)
            .OrderByDescending(g => g.Sum(x => x.Quantity)).Take(3)
            .Select(g => new HighlightItem("", g.Key, $"SL {g.Sum(x => x.Quantity):0.##}", null))
            .ToList();

        // Giờ trong DB là UTC nhưng đọc ra Kind=Unspecified → JSON thiếu «Z», app hiểu thành giờ máy (lệch 7 giờ).
        static List<HighlightItem> Utc(List<HighlightItem> xs) =>
            xs.Select(i => i with { When = i.When is DateTime w ? DateTime.SpecifyKind(w, DateTimeKind.Utc) : null }).ToList();
        commItems = Utc(commItems);
        taskItems = Utc(taskItems);
        fbItems = Utc(fbItems);

        return Ok(AppResponse<object>.Success(new
        {
            communication = new { hasNews = commCount > 0, count = commCount, items = commItems },
            tasks = new
            {
                hasNews = tasksNewToday + tasksOverdue + tasksDueToday + tasksDoneToday > 0,
                newToday = tasksNewToday, overdue = tasksOverdue, dueToday = tasksDueToday, doneToday = tasksDoneToday,
                items = taskItems,
            },
            kpi = new { hasNews = kpiNew > 0, updated = kpiNew, periodName = period?.Name, targets = kpiTargets, avgCompletion = kpiAvg, items = kpiItems },
            feedback = new { hasNews = fbPending + fbNew > 0, pending = fbPending, newCount = fbNew, items = fbItems },
            production = new
            {
                hasNews = prodRows.Count > 0,
                entries = prodRows.Count,
                employees = prodRows.Select(x => x.EmployeeId).Distinct().Count(),
                quantity = prodRows.Sum(x => x.Quantity),
                amount = prodRows.Sum(x => x.Amount ?? 0),
                items = prodItems,
            },
        }));
    }
}
