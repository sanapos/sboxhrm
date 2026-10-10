using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Chuyển/tách/gộp bàn, pause, báo bếp, layout sơ đồ.</summary>
public partial class PosSellIndustryController
{
    public record TransferSessionDto(Guid TargetResourceId);
    public record SplitSessionDto(Guid TargetResourceId, List<Guid> LineIds);
    public class SplitBillItemDto
    {
        public Guid LineId { get; set; }
        public decimal Qty { get; set; }
    }
    public class SplitBillDto
    {
        public List<SplitBillItemDto> Items { get; set; } = [];
        public string? DeviceId { get; set; }
        public string? DeviceName { get; set; }
    }
    public record MergeSessionDto(Guid SourceSessionId);
    public record GuestCountDto(int GuestCount);
    public record KitchenSendDto(
        List<Guid>? LineIds = null,
        string? DeviceId = null,
        string? DeviceName = null,
        /// <summary>Mã chống mất phiếu: báo lại cùng mã → trả lại đúng các món lần trước để in.</summary>
        string? RequestId = null);

    /// <summary>DTO class (không dùng positional record) — tránh JSON bind sai layoutX/Y.</summary>
    public class LayoutItemDto
    {
        public Guid Id { get; set; }
        public double LayoutX { get; set; }
        public double LayoutY { get; set; }
        public double? LayoutW { get; set; }
        public double? LayoutH { get; set; }
    }

    public class LayoutBatchDto
    {
        public List<LayoutItemDto> Items { get; set; } = [];
    }

    static bool IsSessionLive(PosResourceSessionStatus status) =>
        status is PosResourceSessionStatus.Open or PosResourceSessionStatus.Paused;

    [HttpPost("resource-sessions/{id:guid}/pause")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> PauseSession(Guid id)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        var session = await db.PosResourceSessions
            .AsTracking().FirstOrDefaultAsync(s => s.Id == id && s.StoreId == storeId && s.Deleted == null);
        if (session == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy phiên"));
        if (session.Status != PosResourceSessionStatus.Open)
            return BadRequest(AppResponse<object>.Fail("Chỉ tạm dừng phiên đang mở"));
        if (!await CanOperateResourceAsync(storeId, session.ResourceId))
            return BadRequest(AppResponse<object>.Fail("Bạn không được phép thao tác bàn ở khu vực này"));

        session.Status = PosResourceSessionStatus.Paused;
        session.PausedAt = DateTime.UtcNow;
        session.UpdatedAt = DateTime.UtcNow;
        session.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync();
        NotifyFloorChanged(storeId, "pauseSession",
            resourceId: session.ResourceId, sessionId: session.Id);
        return Ok(AppResponse<object>.Success(new { sessionId = session.Id, status = "Paused" }));
    }

    /// <summary>
    /// Chốt tiền giờ: đồng hồ dừng tại lúc chốt, tiền giờ không tăng (khách xin tính tiền, trả sau).
    /// Mở chốt → đồng hồ chạy tiếp, không tính khoảng đã chốt.
    /// </summary>
    [HttpPost("resource-sessions/{id:guid}/lock-billing")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> LockBilling(Guid id)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        var session = await db.PosResourceSessions
            .AsTracking().FirstOrDefaultAsync(s => s.Id == id && s.StoreId == storeId && s.Deleted == null);
        if (session == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy phiên"));
        if (!IsSessionLive(session.Status))
            return BadRequest(AppResponse<object>.Fail("Phiên đã đóng"));
        if (session.BillingLockedAt.HasValue)
            return Ok(AppResponse<object>.Success(new { sessionId = session.Id, billingLockedAt = session.BillingLockedAt }));
        if (!await CanOperateResourceAsync(storeId, session.ResourceId))
            return BadRequest(AppResponse<object>.Fail("Bạn không được phép thao tác bàn ở khu vực này"));

        var now = DateTime.UtcNow;
        // Dừng đồng hồ như tạm dừng (dùng chung cách trừ phút) + đánh dấu chốt.
        if (session.Status == PosResourceSessionStatus.Open)
        {
            session.Status = PosResourceSessionStatus.Paused;
            session.PausedAt = now;
        }
        session.BillingLockedAt = now;
        session.BillingLockedBy = CurrentUserEmail;
        session.UpdatedAt = now;
        session.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync();
        NotifyFloorChanged(storeId, "lockBilling", resourceId: session.ResourceId, sessionId: session.Id);
        return Ok(AppResponse<object>.Success(new { sessionId = session.Id, billingLockedAt = now }));
    }

    [HttpPost("resource-sessions/{id:guid}/unlock-billing")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> UnlockBilling(Guid id)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        var session = await db.PosResourceSessions
            .AsTracking().FirstOrDefaultAsync(s => s.Id == id && s.StoreId == storeId && s.Deleted == null);
        if (session == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy phiên"));
        if (!session.BillingLockedAt.HasValue)
            return BadRequest(AppResponse<object>.Fail("Phiên chưa chốt giờ"));
        if (!await CanOperateResourceAsync(storeId, session.ResourceId))
            return BadRequest(AppResponse<object>.Fail("Bạn không được phép thao tác bàn ở khu vực này"));

        var now = DateTime.UtcNow;
        if (session.Status == PosResourceSessionStatus.Paused && session.PausedAt.HasValue)
        {
            session.AccumulatedPauseMinutes += (int)Math.Max(0, (now - session.PausedAt.Value).TotalMinutes);
            session.PausedAt = null;
            session.Status = PosResourceSessionStatus.Open;
        }
        session.BillingLockedAt = null;
        session.BillingLockedBy = null;
        session.UpdatedAt = now;
        session.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync();
        NotifyFloorChanged(storeId, "unlockBilling", resourceId: session.ResourceId, sessionId: session.Id);
        return Ok(AppResponse<object>.Success(new
        {
            sessionId = session.Id,
            accumulatedPauseMinutes = session.AccumulatedPauseMinutes,
        }));
    }

    [HttpPost("resource-sessions/{id:guid}/resume")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> ResumeSession(Guid id)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        var session = await db.PosResourceSessions
            .AsTracking().FirstOrDefaultAsync(s => s.Id == id && s.StoreId == storeId && s.Deleted == null);
        if (session == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy phiên"));
        if (session.Status != PosResourceSessionStatus.Paused)
            return BadRequest(AppResponse<object>.Fail("Phiên không ở trạng thái tạm dừng"));
        if (!await CanOperateResourceAsync(storeId, session.ResourceId))
            return BadRequest(AppResponse<object>.Fail("Bạn không được phép thao tác bàn ở khu vực này"));

        if (session.PausedAt.HasValue)
        {
            var pauseMins = (int)Math.Max(0, (DateTime.UtcNow - session.PausedAt.Value).TotalMinutes);
            session.AccumulatedPauseMinutes += pauseMins;
        }
        session.PausedAt = null;
        session.Status = PosResourceSessionStatus.Open;
        session.BillingLockedAt = null;
        session.BillingLockedBy = null;
        session.UpdatedAt = DateTime.UtcNow;
        session.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync();
        NotifyFloorChanged(storeId, "resumeSession",
            resourceId: session.ResourceId, sessionId: session.Id);
        return Ok(AppResponse<object>.Success(new
        {
            sessionId = session.Id,
            status = "Open",
            accumulatedPauseMinutes = session.AccumulatedPauseMinutes,
        }));
    }

    /// <summary>Đóng phiên Open/Paused mà đơn không còn Draft — tránh bàn «trống» trên UI nhưng API báo đang có khách.</summary>
    async Task<int> CloseOrphanLiveSessionsOnResourceAsync(Guid storeId, Guid resourceId)
    {
        var live = await db.PosResourceSessions
            .AsTracking().Where(s => s.ResourceId == resourceId && s.Deleted == null
                && (s.StoreId == storeId || s.StoreId == Guid.Empty)
                && (s.Status == PosResourceSessionStatus.Open
                    || s.Status == PosResourceSessionStatus.Paused))
            .ToListAsync();
        if (live.Count == 0) return 0;

        var orderIds = live.Where(s => s.SaleOrderId.HasValue)
            .Select(s => s.SaleOrderId!.Value).Distinct().ToList();
        var draftIds = orderIds.Count == 0
            ? new HashSet<Guid>()
            : (await db.PosSaleOrders.AsNoTracking()
                .Where(o => orderIds.Contains(o.Id)
                    && (o.StoreId == storeId || o.StoreId == Guid.Empty)
                    && o.Deleted == null && o.Status == PosSaleOrderStatus.Draft)
                .Select(o => o.Id)
                .ToListAsync()).ToHashSet();

        var now = DateTime.UtcNow;
        var closed = 0;
        foreach (var s in live)
        {
            if (s.SaleOrderId.HasValue && draftIds.Contains(s.SaleOrderId.Value))
                continue;
            s.Status = PosResourceSessionStatus.Closed;
            s.EndedAt = now;
            s.UpdatedAt = now;
            s.UpdatedBy = CurrentUserEmail;
            if (s.StoreId == Guid.Empty) s.StoreId = storeId;
            closed++;
        }
        if (closed > 0) await db.SaveChangesAsync();
        return closed;
    }

    [HttpPost("resource-sessions/{id:guid}/transfer")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> TransferSession(Guid id, [FromBody] TransferSessionDto? dto)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        if (dto == null || dto.TargetResourceId == Guid.Empty)
            return BadRequest(AppResponse<object>.Fail("Thiếu bàn đích"));

        // Cho phép StoreId rỗng (phiên cũ) — giống request-bill.
        var session = await db.PosResourceSessions
            .AsTracking().FirstOrDefaultAsync(s => s.Id == id && s.Deleted == null
                && (s.StoreId == storeId || s.StoreId == Guid.Empty));
        // Fallback: id có thể là resourceId (client gửi nhầm) → lấy phiên live của bàn.
        if (session == null || !IsSessionLive(session.Status))
        {
            session = await db.PosResourceSessions
                .AsTracking().Where(s => s.ResourceId == id && s.Deleted == null
                    && (s.StoreId == storeId || s.StoreId == Guid.Empty)
                    && (s.Status == PosResourceSessionStatus.Open
                        || s.Status == PosResourceSessionStatus.Paused))
                .OrderByDescending(s => s.StartedAt)
                .FirstOrDefaultAsync();
        }
        if (session == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy phiên"));
        if (!IsSessionLive(session.Status))
            return BadRequest(AppResponse<object>.Fail("Phiên đã đóng"));
        if (session.StoreId == Guid.Empty)
            session.StoreId = storeId;

        var target = await db.PosServiceResources
            .AsTracking().FirstOrDefaultAsync(r => r.Id == dto.TargetResourceId && r.StoreId == storeId
                && r.Deleted == null && r.IsActive);
        if (target == null) return BadRequest(AppResponse<object>.Fail("Bàn đích không hợp lệ"));
        if (target.Id == session.ResourceId)
            return BadRequest(AppResponse<object>.Fail("Bàn đích trùng bàn hiện tại"));
        if (!await CanOperateResourceAsync(storeId, session.ResourceId)
            || !await CanOperateAreaAsync(storeId, target.AreaId))
            return BadRequest(AppResponse<object>.Fail("Bạn không được phép chuyển bàn ngoài khu vực được gán"));

        await CloseOrphanLiveSessionsOnResourceAsync(storeId, target.Id);

        var busy = await db.PosResourceSessions.AnyAsync(s =>
            s.ResourceId == target.Id && s.Deleted == null
            && (s.Status == PosResourceSessionStatus.Open
                || s.Status == PosResourceSessionStatus.Paused));
        if (busy) return BadRequest(AppResponse<object>.Fail("Bàn đích đang có khách"));

        // Hủy đặt trước còn sót trên bàn đích.
        await ClearBookedReservationsOnResourceAsync(storeId, target.Id, asSeated: false);

        var fromId = session.ResourceId;
        session.ResourceId = target.Id;
        session.UpdatedAt = DateTime.UtcNow;
        session.UpdatedBy = CurrentUserEmail;

        if (session.SaleOrderId.HasValue)
        {
            var order = await db.PosSaleOrders
                .AsTracking().FirstOrDefaultAsync(o => o.Id == session.SaleOrderId
                    && (o.StoreId == storeId || o.StoreId == Guid.Empty));
            if (order != null)
            {
                if (order.StoreId == Guid.Empty)
                    order.StoreId = storeId;
                order.ServiceResourceId = target.Id;
                order.LockVersion = Math.Max(1, order.LockVersion) + 1;
                order.UpdatedAt = DateTime.UtcNow;
                order.UpdatedBy = CurrentUserEmail;
            }
        }

        var from = await db.PosServiceResources
            .AsTracking().FirstOrDefaultAsync(r => r.Id == fromId && r.StoreId == storeId);
        if (from != null)
        {
            from.NeedsCleaning = false;
            from.UpdatedAt = DateTime.UtcNow;
        }
        target.NeedsCleaning = false;

        // Đặt trước trên bàn nguồn (nếu còn) → đã dùng xong đường chuyển.
        await ClearBookedReservationsOnResourceAsync(storeId, fromId, asSeated: true);

        await db.SaveChangesAsync();
        var areaName = await db.PosServiceAreas.AsNoTracking()
            .Where(a => a.Id == target.AreaId)
            .Select(a => a.Name)
            .FirstOrDefaultAsync();
        NotifyFloorChanged(storeId, "transfer",
            orderId: session.SaleOrderId, resourceId: target.Id, sessionId: session.Id);
        return Ok(AppResponse<object>.Success(new
        {
            sessionId = session.Id,
            saleOrderId = session.SaleOrderId,
            fromResourceId = fromId,
            toResourceId = target.Id,
            toResourceName = target.Name,
            toAreaName = areaName,
        }));
    }

    /// <summary>Chuyển bàn theo resourceId nguồn (tin cậy hơn sessionId trên sơ đồ).</summary>
    [HttpPost("service-resources/{id:guid}/transfer")]
    [ZKTecoADMS.Api.Controllers.Filters.NotifyPosFloor("transfer", "resource")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> TransferByResource(
        Guid id, [FromBody] TransferSessionDto? dto)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        var live = await db.PosResourceSessions
            .AsTracking().Where(s => s.ResourceId == id && s.Deleted == null
                && (s.StoreId == storeId || s.StoreId == Guid.Empty)
                && (s.Status == PosResourceSessionStatus.Open
                    || s.Status == PosResourceSessionStatus.Paused))
            .OrderByDescending(s => s.StartedAt)
            .FirstOrDefaultAsync();
        if (live == null)
            return NotFound(AppResponse<object>.Fail("Bàn nguồn không có phiên đang mở"));
        return await TransferSession(live.Id, dto);
    }

    async Task ClearBookedReservationsOnResourceAsync(Guid storeId, Guid resourceId, bool asSeated)
    {
        var now = DateTime.UtcNow;
        var status = asSeated
            ? PosResourceReservationStatus.Seated
            : PosResourceReservationStatus.Cancelled;

        // Classic (không duration) hoặc timed đang/đã bắt đầu trong cửa sổ gần → clear.
        // Timed tương lai giữ nguyên để salon multi-slot không mất lịch.
        var candidates = await db.PosResourceReservations
            .Where(x => x.ResourceId == resourceId && x.Deleted == null
                && (x.StoreId == storeId || x.StoreId == Guid.Empty)
                && x.Status == PosResourceReservationStatus.Booked)
            .Select(x => new { x.Id, x.ReservedAt, x.ReservedUntil, x.DurationMinutes })
            .ToListAsync();

        var clearIds = candidates
            .Where(x =>
            {
                if (x.DurationMinutes is null or <= 0) return true;
                var end = x.ReservedUntil ?? x.ReservedAt.AddMinutes(x.DurationMinutes.Value);
                // Đang trong slot hoặc slot đã bắt đầu ≤ 30' trước (khách đến sớm / muộn ít).
                return x.ReservedAt <= now.AddMinutes(30) && now < end.AddMinutes(ReservationNoShowGraceMinutes);
            })
            .Select(x => x.Id)
            .ToList();

        if (clearIds.Count == 0) return;

        await db.PosResourceReservations
            .Where(x => clearIds.Contains(x.Id))
            .ExecuteUpdateAsync(s => s
                .SetProperty(x => x.Status, status)
                .SetProperty(x => x.UpdatedAt, now)
                .SetProperty(x => x.UpdatedBy, CurrentUserEmail)
                .SetProperty(x => x.Deleted, now));
    }

    [HttpPost("resource-sessions/{id:guid}/split")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> SplitSession(Guid id, [FromBody] SplitSessionDto dto)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        if (dto.LineIds == null || dto.LineIds.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Chọn ít nhất một dòng để tách"));

        var session = await db.PosResourceSessions
            .AsTracking().FirstOrDefaultAsync(s => s.Id == id && s.Deleted == null
                && (s.StoreId == storeId || s.StoreId == Guid.Empty));
        if (session == null || !session.SaleOrderId.HasValue)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy phiên/đơn"));
        if (!IsSessionLive(session.Status))
            return BadRequest(AppResponse<object>.Fail("Phiên đã đóng"));
        if (session.StoreId == Guid.Empty)
            session.StoreId = storeId;

        var target = await db.PosServiceResources
            .AsTracking().FirstOrDefaultAsync(r => r.Id == dto.TargetResourceId && r.StoreId == storeId
                && r.Deleted == null && r.IsActive);
        if (target == null) return BadRequest(AppResponse<object>.Fail("Bàn đích không hợp lệ"));

        if (!await CanOperateResourceAsync(storeId, session.ResourceId)
            || !await CanOperateAreaAsync(storeId, target.AreaId))
            return BadRequest(AppResponse<object>.Fail(
                "Bạn không được phép tách bàn ngoài khu vực được gán"));

        await CloseOrphanLiveSessionsOnResourceAsync(storeId, target.Id);

        var busy = await db.PosResourceSessions.AnyAsync(s =>
            s.ResourceId == target.Id && s.Deleted == null
            && (s.Status == PosResourceSessionStatus.Open
                || s.Status == PosResourceSessionStatus.Paused));
        if (busy) return BadRequest(AppResponse<object>.Fail("Bàn đích đang có khách"));

        await ClearBookedReservationsOnResourceAsync(storeId, target.Id, asSeated: false);

        var sourceOrder = await db.PosSaleOrders
            .AsTracking().Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == session.SaleOrderId
                && (o.StoreId == storeId || o.StoreId == Guid.Empty));
        if (sourceOrder == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy đơn"));
        if (sourceOrder.StoreId == Guid.Empty)
            sourceOrder.StoreId = storeId;

        var moveLines = sourceOrder.Lines
            .Where(l => l.Deleted == null && dto.LineIds.Contains(l.Id))
            .ToList();
        if (moveLines.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Không có dòng hợp lệ để tách"));
        if (moveLines.Count >= sourceOrder.Lines.Count(l => l.Deleted == null))
            return BadRequest(AppResponse<object>.Fail("Không tách hết món — dùng chuyển bàn"));

        // Mở phiên + đơn mới trên bàn đích (tách FK: đơn trước → phiên → gắn lại).
        var (orderNo, invoiceSlot) = await AllocateTableDraftNoAsync(storeId);
        var now = DateTime.UtcNow;
        var newOrder = new PosSaleOrder
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            OrderNo = orderNo,
            InvoiceSlot = invoiceSlot,
            Status = PosSaleOrderStatus.Draft,
            PaymentMethod = sourceOrder.PaymentMethod,
            CustomerId = sourceOrder.CustomerId,
            CustomerName = sourceOrder.CustomerName,
            ServiceResourceId = target.Id,
            ServiceStartedAt = sourceOrder.ServiceStartedAt ?? session.StartedAt,
            SaleDate = now,
            SalesChannel = sourceOrder.SalesChannel ?? "Tại chỗ",
            PriceListId = sourceOrder.PriceListId,
            PriceListName = sourceOrder.PriceListName,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
            CreatedAt = now,
        };
        var lockDisplay = CurrentUserEmail;
        if (string.IsNullOrWhiteSpace(lockDisplay))
            lockDisplay = CurrentUserId.ToString("N")[..8];
        PosDraftLockHelper.AssignOnCreate(
            newOrder,
            new PosDraftLockHelper.LockActor(
                CurrentUserId, EmployeeId, lockDisplay!, null, null));

        db.PosSaleOrders.Add(newOrder);
        await db.SaveChangesAsync();

        var newSession = new PosResourceSession
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            ResourceId = target.Id,
            SaleOrderId = newOrder.Id,
            CustomerId = sourceOrder.CustomerId,
            StartedAt = session.StartedAt,
            Status = session.Status == PosResourceSessionStatus.Paused
                ? PosResourceSessionStatus.Paused
                : PosResourceSessionStatus.Open,
            PausedAt = session.PausedAt,
            AccumulatedPauseMinutes = session.AccumulatedPauseMinutes,
            GuestCount = 1,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
            CreatedAt = now,
        };
        db.PosResourceSessions.Add(newSession);
        await db.SaveChangesAsync();

        newOrder.ResourceSessionId = newSession.Id;

        foreach (var line in moveLines)
        {
            // Bắt buộc Remove khỏi collection nguồn — nếu không EF vẫn tính dòng vào đơn cũ
            // và autosave client có thể ghi đè trả món về bàn nguồn.
            sourceOrder.Lines.Remove(line);
            line.SaleOrderId = newOrder.Id;
            line.ServiceStartedAt ??= session.StartedAt;
            line.UpdatedAt = now;
            line.UpdatedBy = CurrentUserEmail;
            newOrder.Lines.Add(line);
        }

        RecalcOrderTotals(sourceOrder);
        RecalcOrderTotals(newOrder);

        // Bump lockVersion đơn nguồn — client cũ đang giữ giỏ full sẽ conflict thay vì ghi đè.
        sourceOrder.LockVersion = Math.Max(1, sourceOrder.LockVersion) + 1;
        sourceOrder.UpdatedAt = now;
        sourceOrder.UpdatedBy = CurrentUserEmail;

        target.NeedsCleaning = false;
        await db.SaveChangesAsync();

        NotifyFloorChanged(storeId, "split",
            orderId: sourceOrder.Id, resourceId: target.Id, sessionId: newSession.Id);
        return Ok(AppResponse<object>.Success(new
        {
            sourceSessionId = session.Id,
            sourceOrderId = sourceOrder.Id,
            sourceLockVersion = sourceOrder.LockVersion,
            newSessionId = newSession.Id,
            newSaleOrderId = newOrder.Id,
            newOrderNo = newOrder.OrderNo,
            movedLines = moveLines.Count,
        }));
    }

    /// <summary>
    /// Tách bill trên cùng bàn: món chọn thành đơn tạm mới để thanh toán,
    /// phần còn lại giữ phiên bàn. Không cần bàn trống.
    /// </summary>
    [HttpPost("resource-sessions/{id:guid}/split-bill")]
    [RequireAnyActionOnModule("PosSell", ModulePermissionAction.Create, ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> SplitBill(Guid id, [FromBody] SplitBillDto? dto)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        var items = dto?.Items?
            .Where(x => x.LineId != Guid.Empty && x.Qty > 0)
            .GroupBy(x => x.LineId)
            .Select(g => new SplitBillItemDto { LineId = g.Key, Qty = g.Sum(x => x.Qty) })
            .ToList() ?? [];
        if (items.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Chọn ít nhất một món để tách bill"));

        var session = await db.PosResourceSessions
            .AsTracking().FirstOrDefaultAsync(s => s.Id == id && s.Deleted == null
                && (s.StoreId == storeId || s.StoreId == Guid.Empty));
        if (session == null || !session.SaleOrderId.HasValue)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy phiên/đơn"));
        if (!IsSessionLive(session.Status))
            return BadRequest(AppResponse<object>.Fail("Phiên đã đóng"));
        if (session.StoreId == Guid.Empty)
            session.StoreId = storeId;
        if (!await CanOperateResourceAsync(storeId, session.ResourceId))
            return BadRequest(AppResponse<object>.Fail("Bạn không được phép tách bill bàn này"));

        var sourceOrder = await db.PosSaleOrders
            .AsTracking().Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == session.SaleOrderId
                && (o.StoreId == storeId || o.StoreId == Guid.Empty));
        if (sourceOrder == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy đơn"));
        if (sourceOrder.Status != PosSaleOrderStatus.Draft)
            return BadRequest(AppResponse<object>.Fail("Chỉ tách bill đơn tạm"));
        if (sourceOrder.StoreId == Guid.Empty)
            sourceOrder.StoreId = storeId;

        var liveLines = sourceOrder.Lines.Where(l => l.Deleted == null).ToList();
        var byId = liveLines.ToDictionary(l => l.Id);
        decimal sourceQty = liveLines.Sum(l => l.Qty);
        decimal takeQtyTotal = 0;
        foreach (var item in items)
        {
            if (!byId.TryGetValue(item.LineId, out var line))
                return BadRequest(AppResponse<object>.Fail("Có dòng không thuộc đơn này"));
            if (item.Qty > line.Qty)
                return BadRequest(AppResponse<object>.Fail(
                    $"SL tách vượt quá {line.ProductName} (còn {line.Qty:0.###})"));
            takeQtyTotal += item.Qty;
        }
        if (takeQtyTotal <= 0)
            return BadRequest(AppResponse<object>.Fail("Chọn số lượng để tách bill"));
        if (takeQtyTotal >= sourceQty)
            return BadRequest(AppResponse<object>.Fail(
                "Không tách hết món — dùng Thanh toán cho cả bàn"));

        var now = DateTime.UtcNow;
        var (orderNo, invoiceSlot) = await AllocateTableDraftNoAsync(storeId);
        var newOrder = new PosSaleOrder
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            OrderNo = orderNo,
            InvoiceSlot = invoiceSlot,
            Status = PosSaleOrderStatus.Draft,
            PaymentMethod = sourceOrder.PaymentMethod,
            CustomerId = sourceOrder.CustomerId,
            CustomerName = sourceOrder.CustomerName,
            ServiceResourceId = sourceOrder.ServiceResourceId,
            ResourceSessionId = null,
            SplitFromOrderId = sourceOrder.Id,
            ServiceStartedAt = sourceOrder.ServiceStartedAt ?? session.StartedAt,
            SaleDate = now,
            SalesChannel = "Tách bill",
            PriceListId = sourceOrder.PriceListId,
            PriceListName = sourceOrder.PriceListName,
            Note = string.IsNullOrWhiteSpace(sourceOrder.Note)
                ? $"Tách từ {sourceOrder.OrderNo}"
                : sourceOrder.Note,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
            CreatedAt = now,
        };
        var lockDisplay = CurrentUserEmail;
        if (string.IsNullOrWhiteSpace(lockDisplay))
            lockDisplay = CurrentUserId.ToString("N")[..8];
        PosDraftLockHelper.AssignOnCreate(
            newOrder,
            new PosDraftLockHelper.LockActor(
                CurrentUserId, EmployeeId, lockDisplay!, dto?.DeviceId, dto?.DeviceName));
        db.PosSaleOrders.Add(newOrder);
        await db.SaveChangesAsync();

        foreach (var item in items)
        {
            var line = byId[item.LineId];
            var take = item.Qty;
            if (take >= line.Qty)
            {
                sourceOrder.Lines.Remove(line);
                line.SaleOrderId = newOrder.Id;
                line.UpdatedAt = now;
                line.UpdatedBy = CurrentUserEmail;
                newOrder.Lines.Add(line);
                continue;
            }

            var oldQty = line.Qty;
            var (takeDisc, takeTotal) = ScaleLineMoney(line.DiscountAmount, line.LineTotal, take, oldQty);
            var remainDisc = line.DiscountAmount - takeDisc;
            var remainTotal = line.LineTotal - takeTotal;
            var takeKitchen = Math.Min(take, line.KitchenSentQty);

            var moved = CloneSplitLine(
                line, newOrder.Id, storeId, take, takeKitchen, takeDisc, takeTotal,
                CurrentUserEmail, now);
            newOrder.Lines.Add(moved);
            db.PosSaleOrderLines.Add(moved);

            line.Qty = oldQty - take;
            line.DiscountAmount = remainDisc;
            line.LineTotal = remainTotal;
            line.KitchenSentQty = Math.Max(0, line.KitchenSentQty - takeKitchen);
            if (line.KitchenDoneQty > line.KitchenSentQty)
                line.KitchenDoneQty = line.KitchenSentQty;
            PosKitchenKdsHelper.Clamp(line);
            if (line.KitchenSentQty <= 0)
                line.KitchenSentAt = null;
            line.UpdatedAt = now;
            line.UpdatedBy = CurrentUserEmail;
        }

        RecalcOrderTotals(sourceOrder);
        RecalcOrderTotals(newOrder);
        sourceOrder.LockVersion = Math.Max(1, sourceOrder.LockVersion) + 1;
        sourceOrder.UpdatedAt = now;
        sourceOrder.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync();

        NotifyFloorChanged(storeId, "splitBill",
            orderId: sourceOrder.Id, resourceId: session.ResourceId, sessionId: session.Id);
        return Ok(AppResponse<object>.Success(new
        {
            sourceSessionId = session.Id,
            sourceOrderId = sourceOrder.Id,
            sourceLockVersion = sourceOrder.LockVersion,
            newSaleOrderId = newOrder.Id,
            newOrderNo = newOrder.OrderNo,
            splitFromOrderId = sourceOrder.Id,
            tableResourceId = session.ResourceId,
        }));
    }

    static (decimal Discount, decimal LineTotal) ScaleLineMoney(
        decimal discount, decimal lineTotal, decimal newQty, decimal oldQty)
    {
        if (oldQty <= 0) return (0, 0);
        var r = newQty / oldQty;
        return (
            Math.Round(discount * r, 0, MidpointRounding.AwayFromZero),
            Math.Round(lineTotal * r, 0, MidpointRounding.AwayFromZero));
    }

    static PosSaleOrderLine CloneSplitLine(
        PosSaleOrderLine src,
        Guid newOrderId,
        Guid storeId,
        decimal qty,
        decimal kitchenSent,
        decimal discount,
        decimal lineTotal,
        string? by,
        DateTime now) =>
        new()
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            SaleOrderId = newOrderId,
            ProductId = src.ProductId,
            VariantId = src.VariantId,
            ProductName = src.ProductName,
            UnitName = src.UnitName,
            UnitId = src.UnitId,
            Qty = qty,
            UnitPrice = src.UnitPrice,
            DiscountAmount = discount,
            LineTotal = lineTotal,
            LineNote = src.LineNote,
            DurationMinutes = src.DurationMinutes,
            BillableMinutes = src.BillableMinutes,
            ServiceStartedAt = src.ServiceStartedAt,
            ServiceEndedAt = src.ServiceEndedAt,
            ServicePausedAt = src.ServicePausedAt,
            ServicePauseMinutes = src.ServicePauseMinutes,
            AssignedEmployeeId = src.AssignedEmployeeId,
            KitchenSentQty = kitchenSent,
            KitchenSentAt = kitchenSent > 0 ? src.KitchenSentAt ?? now : null,
            KitchenDoneQty = kitchenSent > 0
                ? Math.Min(kitchenSent, src.KitchenDoneQty)
                : 0,
            KitchenPrepStatus = kitchenSent > 0
                ? (string.IsNullOrWhiteSpace(src.KitchenPrepStatus) || src.KitchenPrepStatus == "none"
                    ? "queued"
                    : src.KitchenPrepStatus)
                : "none",
            ToppingsJson = src.ToppingsJson,
            IsActive = true,
            CreatedAt = now,
            CreatedBy = by,
        };

    [HttpPost("resource-sessions/{id:guid}/merge")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> MergeSession(Guid id, [FromBody] MergeSessionDto? dto)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        if (dto == null || dto.SourceSessionId == Guid.Empty)
            return BadRequest(AppResponse<object>.Fail("Thiếu bàn nguồn để gộp"));
        if (dto.SourceSessionId == id)
            return BadRequest(AppResponse<object>.Fail("Không gộp cùng một phiên"));

        var targetSession = await db.PosResourceSessions
            .AsTracking().FirstOrDefaultAsync(s => s.Id == id && s.Deleted == null
                && (s.StoreId == storeId || s.StoreId == Guid.Empty));
        var sourceSession = await db.PosResourceSessions
            .AsTracking().FirstOrDefaultAsync(s => s.Id == dto.SourceSessionId && s.Deleted == null
                && (s.StoreId == storeId || s.StoreId == Guid.Empty));
        if (targetSession == null || sourceSession == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy phiên"));
        if (!IsSessionLive(targetSession.Status) || !IsSessionLive(sourceSession.Status))
            return BadRequest(AppResponse<object>.Fail("Cả hai phiên phải đang mở"));
        if (!targetSession.SaleOrderId.HasValue || !sourceSession.SaleOrderId.HasValue)
            return BadRequest(AppResponse<object>.Fail("Phiên thiếu đơn Draft"));
        if (!await CanOperateResourceAsync(storeId, targetSession.ResourceId)
            || !await CanOperateResourceAsync(storeId, sourceSession.ResourceId))
            return BadRequest(AppResponse<object>.Fail("Bạn không được phép gộp bàn ngoài khu vực được gán"));
        if (targetSession.StoreId == Guid.Empty) targetSession.StoreId = storeId;
        if (sourceSession.StoreId == Guid.Empty) sourceSession.StoreId = storeId;

        var targetOrder = await db.PosSaleOrders.AsTracking().Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == targetSession.SaleOrderId
                && (o.StoreId == storeId || o.StoreId == Guid.Empty));
        var sourceOrder = await db.PosSaleOrders.AsTracking().Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == sourceSession.SaleOrderId
                && (o.StoreId == storeId || o.StoreId == Guid.Empty));
        if (targetOrder == null || sourceOrder == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy đơn"));
        if (targetOrder.StoreId == Guid.Empty) targetOrder.StoreId = storeId;
        if (sourceOrder.StoreId == Guid.Empty) sourceOrder.StoreId = storeId;

        var now = DateTime.UtcNow;
        // Chốt pause bàn nguồn (đang đóng); bàn đích giữ pause hiện tại nếu đang tạm dừng.
        PosServiceBillingHelper.FinalizeOpenPause(sourceSession, now);
        if (sourceSession.StartedAt < targetSession.StartedAt)
        {
            targetSession.StartedAt = sourceSession.StartedAt;
            targetOrder.ServiceStartedAt =
                sourceOrder.ServiceStartedAt ?? sourceSession.StartedAt;
        }
        targetSession.AccumulatedPauseMinutes += sourceSession.AccumulatedPauseMinutes;

        var moveLines = sourceOrder.Lines.Where(l => l.Deleted == null).ToList();
        foreach (var line in moveLines)
        {
            sourceOrder.Lines.Remove(line);
            line.SaleOrderId = targetOrder.Id;
            line.ServiceStartedAt ??= sourceSession.StartedAt;
            line.UpdatedAt = now;
            line.UpdatedBy = CurrentUserEmail;
            targetOrder.Lines.Add(line);
        }

        sourceSession.Status = PosResourceSessionStatus.Closed;
        sourceSession.EndedAt = now;
        sourceSession.UpdatedAt = now;
        sourceSession.UpdatedBy = CurrentUserEmail;

        sourceOrder.Status = PosSaleOrderStatus.Cancelled;
        sourceOrder.ServiceResourceId = null;
        sourceOrder.ResourceSessionId = null;
        sourceOrder.ServiceEndedAt = now;
        sourceOrder.LockVersion = Math.Max(1, sourceOrder.LockVersion) + 1;
        sourceOrder.UpdatedAt = now;
        sourceOrder.Note = string.IsNullOrWhiteSpace(sourceOrder.Note)
            ? $"Gộp vào {targetOrder.OrderNo}"
            : $"{sourceOrder.Note} · Gộp vào {targetOrder.OrderNo}";

        targetOrder.LockVersion = Math.Max(1, targetOrder.LockVersion) + 1;
        targetOrder.UpdatedAt = now;

        var fromResource = await db.PosServiceResources
            .AsTracking().FirstOrDefaultAsync(r => r.Id == sourceSession.ResourceId && r.StoreId == storeId);
        if (fromResource != null)
        {
            fromResource.NeedsCleaning = false;
            fromResource.UpdatedAt = now;
        }

        targetSession.GuestCount = Math.Max(1, targetSession.GuestCount + Math.Max(1, sourceSession.GuestCount));
        RecalcOrderTotals(sourceOrder);
        RecalcOrderTotals(targetOrder);
        await ClearBookedReservationsOnResourceAsync(storeId, sourceSession.ResourceId, asSeated: true);
        await db.SaveChangesAsync();

        NotifyFloorChanged(storeId, "merge",
            orderId: targetOrder.Id, resourceId: targetSession.ResourceId, sessionId: targetSession.Id);
        return Ok(AppResponse<object>.Success(new
        {
            targetSessionId = targetSession.Id,
            targetOrderId = targetOrder.Id,
            mergedLines = moveLines.Count,
            guestCount = targetSession.GuestCount,
            targetLockVersion = targetOrder.LockVersion,
        }));
    }

    [HttpPut("resource-sessions/{id:guid}/guests")]
    [ZKTecoADMS.Api.Controllers.Filters.NotifyPosFloor("guests", "session")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> SetGuestCount(Guid id, [FromBody] GuestCountDto dto)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        var session = await db.PosResourceSessions
            .AsTracking().FirstOrDefaultAsync(s => s.Id == id && s.StoreId == storeId && s.Deleted == null);
        if (session == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy phiên"));
        session.GuestCount = Math.Max(1, dto.GuestCount);
        session.UpdatedAt = DateTime.UtcNow;
        session.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { guestCount = session.GuestCount }));
    }

    [HttpPost("resource-sessions/{id:guid}/request-bill")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> RequestBill(Guid id, [FromQuery] bool requested = true)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        if (requested && await RequireProvisionalBillAsync(storeId) is { } denied)
            return denied;

        var session = await db.PosResourceSessions
            .AsTracking().FirstOrDefaultAsync(s => s.Id == id && s.Deleted == null);
        if (session == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy phiên"));

        // Nếu phiên đã đóng / lệch store → chuyển sang phiên Open/Paused đang sống của bàn.
        var live = session;
        var isLive = (live.Status == PosResourceSessionStatus.Open
                      || live.Status == PosResourceSessionStatus.Paused)
                     && (live.StoreId == storeId || live.StoreId == Guid.Empty);
        if (!isLive)
        {
            live = await db.PosResourceSessions
                .AsTracking().Where(s => s.ResourceId == session.ResourceId && s.Deleted == null
                    && (s.StoreId == storeId || s.StoreId == Guid.Empty)
                    && (s.Status == PosResourceSessionStatus.Open
                        || s.Status == PosResourceSessionStatus.Paused))
                .OrderByDescending(s => s.StartedAt)
                .FirstOrDefaultAsync();
            if (live == null)
                return BadRequest(AppResponse<object>.Fail(
                    "Phiên bàn đã đóng — mở lại bàn rồi in tạm tính"));
        }

        if (live.StoreId == Guid.Empty)
            live.StoreId = storeId;
        live.BillRequested = requested;
        live.UpdatedAt = DateTime.UtcNow;
        live.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync();
        NotifyFloorChanged(storeId, "requestBill",
            resourceId: live.ResourceId, sessionId: live.Id);
        return Ok(AppResponse<object>.Success(new
        {
            billRequested = live.BillRequested,
            sessionId = live.Id,
            resourceId = live.ResourceId,
        }));
    }

    /// Đánh dấu tạm tính theo bàn (lấy phiên Open đang sống) — đường tin cậy cho sơ đồ.
    [HttpPost("service-resources/{id:guid}/request-bill")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> RequestBillByResource(
        Guid id, [FromQuery] bool requested = true)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        if (requested && await RequireProvisionalBillAsync(storeId) is { } denied)
            return denied;

        var live = await db.PosResourceSessions
            .AsTracking().Where(s => s.ResourceId == id && s.Deleted == null
                && (s.StoreId == storeId || s.StoreId == Guid.Empty)
                && (s.Status == PosResourceSessionStatus.Open
                    || s.Status == PosResourceSessionStatus.Paused))
            .OrderByDescending(s => s.StartedAt)
            .FirstOrDefaultAsync();
        if (live == null)
            return NotFound(AppResponse<object>.Fail("Bàn không có phiên đang mở"));

        if (live.StoreId == Guid.Empty)
            live.StoreId = storeId;
        live.BillRequested = requested;
        live.UpdatedAt = DateTime.UtcNow;
        live.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync();
        NotifyFloorChanged(storeId, "requestBill",
            resourceId: live.ResourceId, sessionId: live.Id);
        return Ok(AppResponse<object>.Success(new
        {
            billRequested = live.BillRequested,
            sessionId = live.Id,
            resourceId = live.ResourceId,
        }));
    }

    [HttpPost("service-resources/{id:guid}/clean")]
    [ZKTecoADMS.Api.Controllers.Filters.NotifyPosFloor("clean", "resource")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> MarkCleaned(Guid id)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        var resource = await db.PosServiceResources
            .AsTracking().FirstOrDefaultAsync(r => r.Id == id && r.StoreId == storeId && r.Deleted == null);
        if (resource == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy"));

        var now = DateTime.UtcNow;
        resource.NeedsCleaning = false;
        resource.UpdatedAt = now;
        resource.UpdatedBy = CurrentUserEmail;

        // Đóng luôn phiên orphan còn sót (đơn đã TT) — tránh bàn kẹt «cần dọn».
        var live = await db.PosResourceSessions
            .AsTracking().Where(s => s.ResourceId == id && s.StoreId == storeId && s.Deleted == null
                && (s.Status == PosResourceSessionStatus.Open
                    || s.Status == PosResourceSessionStatus.Paused))
            .ToListAsync();
        foreach (var s in live)
        {
            var orderOk = false;
            if (s.SaleOrderId.HasValue)
            {
                orderOk = await db.PosSaleOrders.AsNoTracking().AnyAsync(o =>
                    o.Id == s.SaleOrderId && o.StoreId == storeId
                    && o.Deleted == null && o.Status == PosSaleOrderStatus.Draft);
            }
            if (orderOk) continue; // còn đơn tạm thật — không đóng khi chỉ «đã dọn»
            s.Status = PosResourceSessionStatus.Closed;
            s.EndedAt = now;
            s.UpdatedAt = now;
            s.UpdatedBy = CurrentUserEmail;
        }

        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new
        {
            cleaned = true,
            needsCleaning = false,
            closedOrphans = live.Count(s => s.Status == PosResourceSessionStatus.Closed),
        }));
    }

    /// <summary>
    /// Ghi chú in bếp = tên topping nối bằng dấu phẩy, rồi tới ghi chú dòng —
    /// giữ đúng định dạng «noteWithToppings» của app để phiếu in từ sơ đồ bàn
    /// và phiếu in từ màn bán hàng nhìn giống nhau.
    /// </summary>
    static string? KitchenNoteText(string? toppingsJson, string? lineNote) =>
        PosSaleStockHelper.FormatToppingKitchenNote(toppingsJson, lineNote);

    /// <summary>Đánh dấu món đã báo chế biến / gửi bếp (theo dòng hoặc tất cả chưa gửi).</summary>
    [HttpPost("resource-sessions/{id:guid}/kitchen-send")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> KitchenSend(Guid id, [FromBody] KitchenSendDto? dto)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        if (await RequireRestaurantKitchenAsync(storeId) is { } denied)
            return denied;
        var session = await db.PosResourceSessions
            .AsTracking().FirstOrDefaultAsync(s => s.Id == id && s.StoreId == storeId && s.Deleted == null);
        if (session == null || !session.SaleOrderId.HasValue)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy phiên/đơn"));

        var order = await db.PosSaleOrders
            .AsTracking().FirstOrDefaultAsync(o => o.Id == session.SaleOrderId && o.StoreId == storeId
                && o.Deleted == null);
        if (order == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy đơn"));

        var lockDisplay = string.IsNullOrWhiteSpace(CurrentUserEmail)
            ? CurrentUserId.ToString("N")[..8]
            : CurrentUserEmail!;
        var actor = new PosDraftLockHelper.LockActor(
            CurrentUserId, EmployeeId, lockDisplay, dto?.DeviceId, dto?.DeviceName);
        var lockErr = PosDraftLockHelper.EnsureCanMutate(order, actor, expectedLockVersion: null);
        if (lockErr != null)
            return Conflict(AppResponse<object>.Fail(lockErr));

        // Báo lại cùng mã (mất mạng lúc trả kết quả lần trước): server đã đánh dấu
        // «đã gửi» nhưng máy chưa nhận được danh sách để in → trả lại đúng lần đó.
        // Không trả lại thì máy nhận «đã gửi hết» và phiếu bếp mất hẳn.
        var kitchenRequestId = PosIdempotency.Normalize(dto?.RequestId);
        if (kitchenRequestId != null
            && kitchenRequestId == order.KitchenSendRequestId
            && PosKitchenSendReplay.TryRead(order.KitchenSendReplayJson) is { } replay)
        {
            return Ok(AppResponse<object>.Success(new
            {
                sentLines = replay.SentLines,
                sentQty = replay.SentQty,
                sentItems = replay.SentItems,
                orderNo = order.OrderNo,
                alreadyAllSent = false,
                replayed = true,
                saleOrderId = session.SaleOrderId,
                kitchenSentAt = replay.KitchenSentAt,
                lockVersion = order.LockVersion,
                message = "Đã báo bếp (gửi lại lần trước)",
            }));
        }

        // Ghim máy nếu khóa cũ thiếu device (client mới).
        PosDraftLockHelper.StampDeviceIfMissing(order, actor);

        // Hết TTL / chưa khóa → chiếm quyền máy đang báo bếp.
        if (!PosDraftLockHelper.IsHeldBy(order, actor))
        {
            var acquireErr = PosDraftLockHelper.TryAcquire(
                order, actor, force: false, bumpVersion: true);
            if (acquireErr != null)
                return Conflict(AppResponse<object>.Fail(acquireErr));
        }

        var lines = await db.PosSaleOrderLines
            .AsTracking().Where(l => l.SaleOrderId == session.SaleOrderId && l.StoreId == storeId && l.Deleted == null)
            .ToListAsync();

        var now = DateTime.UtcNow;
        var sent = 0;
        decimal sentQty = 0;
        // Màn sơ đồ bàn không giữ giỏ hàng nên không tự dựng được phiếu bếp.
        // Trả đúng phần vừa báo để client in — trước đây server đánh dấu đã gửi
        // mà không phiếu nào ra giấy, và vì đã gửi nên mở bàn ra cũng không in lại.
        var sentItems = new List<object>();
        foreach (var line in lines)
        {
            if (dto?.LineIds is { Count: > 0 } && !dto.LineIds.Contains(line.Id))
                continue;
            // Chỉ báo phần chưa gửi — tránh in trùng bill cùng món/qty.
            var pending = line.Qty - line.KitchenSentQty;
            if (pending <= 0) continue;
            var sentBefore = line.KitchenSentQty;
            line.KitchenSentQty = line.Qty;
            line.KitchenSentAt = now;
            PosKitchenKdsHelper.OnSent(line);
            line.UpdatedAt = now;
            line.UpdatedBy = CurrentUserEmail;
            sent++;
            sentQty += pending;
            sentItems.Add(new
            {
                productId = line.ProductId,
                productName = line.ProductName,
                qty = pending,
                unitName = line.UnitName,
                note = KitchenNoteText(line.ToppingsJson, line.LineNote),
                // Mốc phần đã báo trước đó + id dòng — client ghép vào mã chống
                // trùng. Thêm phần mới sinh dòng mới nên hai lần báo cùng «1
                // phần»; thiếu hai khóa này thì phiếu sau bị nuốt.
                sentBefore,
                lineId = line.Id,
            });
        }

        if (sent > 0)
        {
            PosDraftLockHelper.BumpVersionOnly(order, now);
            if (kitchenRequestId != null)
            {
                order.KitchenSendRequestId = kitchenRequestId;
                order.KitchenSendReplayJson = PosKitchenSendReplay.Serialize(sent, sentQty, sentItems, now);
            }
        }

        await db.SaveChangesAsync();
        NotifyFloorChanged(storeId, "kitchenSend",
            orderId: session.SaleOrderId, resourceId: session.ResourceId, sessionId: session.Id);
        return Ok(AppResponse<object>.Success(new
        {
            sentLines = sent,
            sentQty,
            sentItems,
            orderNo = order.OrderNo,
            alreadyAllSent = sent == 0,
            saleOrderId = session.SaleOrderId,
            kitchenSentAt = now,
            lockVersion = order.LockVersion,
            message = sent == 0
                ? "Không có món mới — các món đã báo bếp rồi"
                : $"Đã báo {sent} dòng ({sentQty:0.###} phần) lên bếp",
        }));
    }

    // Thiết lập sơ đồ (khu / bàn / vị trí) = quyền Sửa bán hàng; thu ngân (Tạo) chỉ thao tác bán.
    [HttpPut("service-resources/layout")]
    [ZKTecoADMS.Api.Controllers.Filters.NotifyPosFloor("layoutChanged")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> SaveLayout([FromBody] LayoutBatchDto? dto)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        if (dto?.Items == null || dto.Items.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Không có vị trí"));

        var saved = 0;
        var now = DateTime.UtcNow;
        var by = CurrentUserEmail;
        foreach (var item in dto.Items)
        {
            if (item.Id == Guid.Empty) continue;
            // ExecuteUpdate ghi thẳng DB — không phụ thuộc change-tracker.
            var n = await db.PosServiceResources
                .AsTracking().Where(r => r.Id == item.Id && r.StoreId == storeId && r.Deleted == null)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(r => r.LayoutX, item.LayoutX)
                    .SetProperty(r => r.LayoutY, item.LayoutY)
                    .SetProperty(r => r.LayoutW, item.LayoutW ?? 120)
                    .SetProperty(r => r.LayoutH, item.LayoutH ?? 100)
                    .SetProperty(r => r.UpdatedAt, now)
                    .SetProperty(r => r.UpdatedBy, by));
            saved += n;
        }

        if (saved == 0)
            return BadRequest(AppResponse<object>.Fail(
                "Không khớp bàn nào — kiểm tra id / cửa hàng"));

        return Ok(AppResponse<object>.Success(new { saved }));
    }

    public record KitchenVoidLineDto(
        Guid? ProductId,
        string ProductName,
        decimal Qty,
        string? UnitName = null,
        string? LineNote = null,
        decimal? UnitPrice = null);

    public record KitchenVoidBatchDto(
        List<KitchenVoidLineDto> Lines,
        Guid? SaleOrderId = null,
        string? OrderNo = null,
        Guid? ResourceSessionId = null,
        Guid? ServiceResourceId = null,
        string? ResourceName = null,
        bool Printed = true,
        string? DeviceName = null,
        string? Reason = null,
        string? DetailNote = null);

    /// <summary>Ghi phiếu hủy món đã báo bếp (đối soát / chống gian lận sau tạm tính).</summary>
    [HttpPost("kitchen-voids")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> CreateKitchenVoids([FromBody] KitchenVoidBatchDto dto)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        if (dto.Lines == null || dto.Lines.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Không có dòng hủy"));

        var afterBill = false;
        if (dto.ResourceSessionId.HasValue)
        {
            var sess = await db.PosResourceSessions.AsNoTracking()
                .FirstOrDefaultAsync(s => s.Id == dto.ResourceSessionId && s.StoreId == storeId
                    && s.Deleted == null);
            afterBill = sess?.BillRequested == true;
        }

        // Giá trị món hủy: trước đây luôn 0đ → báo cáo «Hủy món bếp» không biết thất thoát bao nhiêu.
        // Ưu tiên giá máy bán gửi lên → đơn giá dòng trong đơn → giá bán của hàng hóa.
        var productIds = dto.Lines.Where(l => l.ProductId.HasValue).Select(l => l.ProductId!.Value).Distinct().ToList();
        var orderPrices = dto.SaleOrderId is Guid soId && productIds.Count > 0
            ? (await db.PosSaleOrderLines.AsNoTracking()
                .Where(l => l.SaleOrderId == soId && l.StoreId == storeId && productIds.Contains(l.ProductId))
                .Select(l => new { l.ProductId, l.UnitPrice, l.Qty, l.LineTotal })
                .ToListAsync())
                .GroupBy(l => l.ProductId)
                .ToDictionary(g => g.Key, g => g.Max(l => l.Qty > 0 ? l.LineTotal / l.Qty : l.UnitPrice))
            : new Dictionary<Guid, decimal>();
        var basePrices = productIds.Count > 0
            ? await db.PosProducts.AsNoTracking()
                .Where(p => p.StoreId == storeId && productIds.Contains(p.Id))
                .Select(p => new { p.Id, p.BasePrice })
                .ToDictionaryAsync(p => p.Id, p => p.BasePrice)
            : new Dictionary<Guid, decimal>();
        decimal PriceOf(KitchenVoidLineDto l) =>
            l.UnitPrice is > 0 ? l.UnitPrice.Value
            : l.ProductId is Guid pid && orderPrices.TryGetValue(pid, out var op) && op > 0 ? op
            : l.ProductId is Guid pid2 ? basePrices.GetValueOrDefault(pid2) : 0;
        var amounts = new Dictionary<PosKitchenVoidSlip, decimal>();

        var now = DateTime.UtcNow;
        var who = CurrentUserEmail;
        var rows = new List<PosKitchenVoidSlip>();
        foreach (var line in dto.Lines.Where(l => l.Qty > 0 && !string.IsNullOrWhiteSpace(l.ProductName)))
        {
            var slip = new PosKitchenVoidSlip
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                SaleOrderId = dto.SaleOrderId,
                OrderNo = dto.OrderNo?.Trim(),
                ResourceSessionId = dto.ResourceSessionId,
                ServiceResourceId = dto.ServiceResourceId,
                ResourceName = dto.ResourceName?.Trim(),
                ProductId = line.ProductId,
                ProductName = line.ProductName.Trim(),
                UnitName = line.UnitName?.Trim(),
                Qty = line.Qty,
                LineNote = line.LineNote?.Trim(),
                Reason = dto.Reason?.Trim(),
                DetailNote = dto.DetailNote?.Trim(),
                AfterBillRequested = afterBill,
                Printed = dto.Printed,
                VoidedAt = now,
                VoidedBy = who,
                DeviceName = dto.DeviceName?.Trim(),
                IsActive = true,
                CreatedAt = now,
                CreatedBy = who,
            };
            PosCancelAuditHelper.ClipSlip(slip);
            amounts[slip] = Math.Round(PriceOf(line) * line.Qty, 0, MidpointRounding.AwayFromZero);
            rows.Add(slip);
        }
        if (rows.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Không có dòng hủy hợp lệ"));

        db.PosKitchenVoidSlips.AddRange(rows);
        foreach (var r in rows)
        {
            PosCancelAuditHelper.Add(db, new PosCancelReturnAudit
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                ActionType = PosCancelAuditHelper.KitchenVoid,
                Reason = r.Reason,
                DetailNote = r.DetailNote,
                AfterProvisionalBill = afterBill,
                SaleOrderId = r.SaleOrderId,
                OrderNo = r.OrderNo,
                ResourceSessionId = r.ResourceSessionId,
                ServiceResourceId = r.ServiceResourceId,
                ResourceName = r.ResourceName,
                ProductId = r.ProductId,
                ProductName = r.ProductName,
                UnitName = r.UnitName,
                Qty = r.Qty,
                Amount = amounts.GetValueOrDefault(r),
                OccurredAt = now,
                Actor = who,
                DeviceName = r.DeviceName,
                IsActive = true,
                CreatedAt = now,
                CreatedBy = who,
            });
        }
        await db.SaveChangesAsync();
        var tableLabel = (dto.ResourceName ?? "").Trim();
        var voice = string.Join(". ", rows.Select(r =>
        {
            var q = r.Qty == decimal.Truncate(r.Qty)
                ? ((long)r.Qty).ToString()
                : r.Qty.ToString("0.###");
            return $"Thông báo hủy {q} món {tableLabel} {r.ProductName}".Trim();
        }));
        NotifyFloorChanged(storeId, "kitchenVoid",
            orderId: dto.SaleOrderId,
            resourceId: dto.ServiceResourceId,
            sessionId: dto.ResourceSessionId,
            tableName: tableLabel,
            message: voice);
        return Ok(AppResponse<object>.Success(new
        {
            created = rows.Count,
            afterBillRequested = afterBill,
            ids = rows.Select(r => r.Id).ToList(),
        }));
    }

    [HttpGet("kitchen-voids")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> ListKitchenVoids(
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null,
        [FromQuery] bool? afterBillOnly = null,
        [FromQuery] bool? beforeBillOnly = null,
        [FromQuery] Guid? resourceId = null,
        [FromQuery] string? resourceName = null,
        [FromQuery] string? voidedBy = null,
        [FromQuery] int take = 200)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));

        var q = db.PosKitchenVoidSlips.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null);
        if (from.HasValue) q = q.Where(x => x.VoidedAt >= from.Value.ToUniversalTime());
        if (to.HasValue) q = q.Where(x => x.VoidedAt <= to.Value.ToUniversalTime());
        if (afterBillOnly == true) q = q.Where(x => x.AfterBillRequested);
        if (beforeBillOnly == true) q = q.Where(x => !x.AfterBillRequested);
        if (resourceId.HasValue) q = q.Where(x => x.ServiceResourceId == resourceId);
        if (!string.IsNullOrWhiteSpace(resourceName))
        {
            var rn = resourceName.Trim().ToLower();
            q = q.Where(x => x.ResourceName != null && x.ResourceName.ToLower().Contains(rn));
        }
        if (!string.IsNullOrWhiteSpace(voidedBy))
        {
            var vb = voidedBy.Trim().ToLower();
            q = q.Where(x => x.VoidedBy != null && x.VoidedBy.ToLower().Contains(vb));
        }

        take = Math.Clamp(take, 1, 500);
        var list = await q.OrderByDescending(x => x.VoidedAt).Take(take)
            .Select(x => new
            {
                x.Id,
                x.OrderNo,
                x.SaleOrderId,
                x.ServiceResourceId,
                x.ResourceName,
                x.ProductName,
                x.UnitName,
                x.Qty,
                x.LineNote,
                x.Reason,
                x.DetailNote,
                x.AfterBillRequested,
                x.Printed,
                x.VoidedAt,
                x.VoidedBy,
                x.DeviceName,
            })
            .ToListAsync();

        return Ok(AppResponse<object>.Success(new
        {
            items = list,
            afterBillCount = list.Count(x => x.AfterBillRequested),
            beforeBillCount = list.Count(x => !x.AfterBillRequested),
        }));
    }

    /// <summary>
    /// Lịch sử hủy món / hủy đơn / hủy đơn tạm / xóa đơn / trả hàng / hủy phiếu trả (lọc thao tác + trước/sau tạm tính).
    /// Thu ngân chỉ có quyền Bán hàng: chỉ thấy lượt của chính mình; quản lý / người xem hóa đơn, trả hàng: cả cửa hàng.
    /// Tổng số lượt / tiền tính trên TOÀN BỘ kết quả lọc (trước đây tính trên 400 dòng tải về → kỳ dài bị thiếu).
    /// </summary>
    [HttpGet("cancel-return-audits")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> ListCancelReturnAudits(
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null,
        [FromQuery] string? actionType = null,
        [FromQuery] bool? afterBillOnly = null,
        [FromQuery] bool? beforeBillOnly = null,
        [FromQuery] string? actor = null,
        [FromQuery] string? search = null,
        [FromQuery] int take = 300)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));

        var seeAll = await CanSeeAllCancelAuditsAsync(storeId);
        var q = db.PosCancelReturnAudits.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null);
        if (!seeAll)
        {
            var me = CurrentUserEmail ?? "";
            q = q.Where(x => x.Actor == me);
        }
        if (from.HasValue) q = q.Where(x => x.OccurredAt >= from.Value.ToUniversalTime());
        if (to.HasValue) q = q.Where(x => x.OccurredAt <= to.Value.ToUniversalTime());
        if (afterBillOnly == true) q = q.Where(x => x.AfterProvisionalBill);
        if (beforeBillOnly == true) q = q.Where(x => !x.AfterProvisionalBill);
        if (!string.IsNullOrWhiteSpace(actor))
        {
            // Lọc theo tên hoặc email: nhật ký chỉ lưu email → đổi tên ra email.
            var a = actor.Trim().ToLower();
            var emails = await db.Users.AsNoTracking()
                .Where(u => u.Email != null && ((u.LastName + " " + u.FirstName).ToLower().Contains(a)
                    || (u.FirstName + " " + u.LastName).ToLower().Contains(a)))
                .Select(u => u.Email!.ToLower())
                .Take(200)
                .ToListAsync();
            q = q.Where(x => x.Actor != null && (x.Actor.ToLower().Contains(a) || emails.Contains(x.Actor.ToLower())));
        }
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            q = q.Where(x =>
                (x.OrderNo != null && x.OrderNo.ToLower().Contains(s)) ||
                (x.ResourceName != null && x.ResourceName.ToLower().Contains(s)) ||
                (x.ProductName != null && x.ProductName.ToLower().Contains(s)) ||
                (x.Reason != null && x.Reason.ToLower().Contains(s)) ||
                (x.DetailNote != null && x.DetailNote.ToLower().Contains(s)));
        }

        // Tổng theo loại, tính trước khi lọc loại — thẻ KPI luôn đủ các loại.
        var byType = await q.GroupBy(x => new { x.ActionType, x.AfterProvisionalBill })
            .Select(g => new { g.Key.ActionType, g.Key.AfterProvisionalBill, Count = g.Count(), Amount = g.Sum(x => x.Amount) })
            .ToListAsync();

        var at = string.IsNullOrWhiteSpace(actionType) ? null : actionType.Trim();
        if (at != null) q = q.Where(x => x.ActionType == at);

        take = Math.Clamp(take, 1, 500);
        var total = await q.CountAsync();
        var list = await q.OrderByDescending(x => x.OccurredAt).Take(take).ToListAsync();

        // Tên nhân viên thay cho email.
        var actorEmails = list.Where(x => !string.IsNullOrWhiteSpace(x.Actor)).Select(x => x.Actor!.ToLower()).Distinct().ToList();
        var names = actorEmails.Count == 0
            ? new Dictionary<string, string>()
            : (await db.Users.AsNoTracking()
                .Where(u => u.Email != null && actorEmails.Contains(u.Email.ToLower()))
                .Select(u => new { u.Email, u.LastName, u.FirstName })
                .ToListAsync())
                .GroupBy(u => u.Email!.ToLower())
                .ToDictionary(g => g.Key, g => $"{g.First().LastName} {g.First().FirstName}".Trim());
        string? NameOf(string? email) =>
            email != null && names.TryGetValue(email.ToLower(), out var n) && n.Length > 0 ? n : null;

        var types = PosCancelAuditHelper.All.Select(t => new
        {
            actionType = t,
            count = byType.Where(b => b.ActionType == t).Sum(b => b.Count),
            amount = byType.Where(b => b.ActionType == t).Sum(b => b.Amount),
        }).ToList();
        var inType = at == null ? byType : byType.Where(b => b.ActionType == at).ToList();

        return Ok(AppResponse<object>.Success(new
        {
            items = list.Select(x => new
            {
                x.Id,
                x.ActionType,
                x.Reason,
                x.DetailNote,
                x.AfterProvisionalBill,
                x.SaleOrderId,
                x.OrderNo,
                x.ServiceResourceId,
                x.ResourceName,
                x.ProductName,
                x.UnitName,
                x.Qty,
                x.Amount,
                x.OccurredAt,
                x.Actor,
                actorName = NameOf(x.Actor),
                x.DeviceName,
            }),
            total,
            truncated = total > list.Count,
            scope = seeAll ? "store" : "mine",
            totalCount = inType.Sum(b => b.Count),
            totalAmount = inType.Sum(b => b.Amount),
            types,
            kitchenVoidCount = types.First(t => t.actionType == PosCancelAuditHelper.KitchenVoid).count,
            saleCancelCount = types.First(t => t.actionType == PosCancelAuditHelper.SaleCancel).count,
            saleReturnCount = types.First(t => t.actionType == PosCancelAuditHelper.SaleReturn).count,
            afterBillCount = inType.Where(b => b.AfterProvisionalBill).Sum(b => b.Count),
            afterBillAmount = inType.Where(b => b.AfterProvisionalBill).Sum(b => b.Amount),
            beforeBillCount = inType.Where(b => !b.AfterProvisionalBill).Sum(b => b.Count),
        }));
    }

    /// <summary>Xem lịch sử hủy / trả của cả cửa hàng: quản lý, hoặc có quyền xem Hóa đơn / Trả hàng bán.</summary>
    async Task<bool> CanSeeAllCancelAuditsAsync(Guid storeId)
    {
        if (IsManager) return true;
        var svc = HttpContext.RequestServices.GetRequiredService<ZKTecoADMS.Application.Interfaces.IModulePermissionService>();
        foreach (var module in new[] { "PosSaleOrders", "PosSaleReturns" })
        {
            if (await svc.HasPermissionAsync(CurrentUserId, CurrentUserRole, storeId, module, ModulePermissionAction.View))
                return true;
        }
        return false;
    }

    static void RecalcOrderTotals(PosSaleOrder order)
    {
        var lines = order.Lines?.Where(l => l.Deleted == null).ToList() ?? [];
        order.SubTotal = lines.Sum(l => l.LineTotal);
        order.Total = Math.Max(0, order.SubTotal - order.Discount);
        order.UpdatedAt = DateTime.UtcNow;
    }

    public record CustomerDisplayStateDto(string StateJson, string? ViewerCode = null);

    /// <summary>POS đẩy trạng thái màn phụ lên server (máy khác mở link vẫn xem được).</summary>
    /// Dùng PosSell Create — thu ngân luôn đẩy được (PosCustomerDisplay kế thừa qua implicit grant).
    [HttpPut("customer-display/state")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public ActionResult<AppResponse<object>> PutCustomerDisplayState(
        [FromBody] CustomerDisplayStateDto dto,
        [FromServices] Microsoft.Extensions.Caching.Distributed.IDistributedCache? dist)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        if (string.IsNullOrWhiteSpace(dto.StateJson))
            return BadRequest(AppResponse<object>.Fail("Thiếu state"));

        var code = (dto.ViewerCode ?? "").Trim();
        if (code.Length < 4)
            return BadRequest(AppResponse<object>.Fail("Thiếu mã xem màn phụ (viewerCode)"));

        ZKTecoADMS.Api.Services.PosCustomerDisplayStateStore.Publish(storeId, code, dto.StateJson.Trim(), dist);
        return Ok(AppResponse<object>.Success(new { ok = true }));
    }

    /// <summary>Máy đã đăng nhập — đọc state mới nhất của cửa hàng.</summary>
    [HttpGet("customer-display/state")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public ActionResult<AppResponse<object>> GetCustomerDisplayState()
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        var json = ZKTecoADMS.Api.Services.PosCustomerDisplayStateStore.GetByStore(storeId);
        return Ok(AppResponse<object>.Success(new { stateJson = json }));
    }

    /// <summary>Máy khác mở link công khai ?v=CODE — không cần đăng nhập.</summary>
    [HttpGet("customer-display/public-state")]
    [Microsoft.AspNetCore.Authorization.AllowAnonymous]
    public async Task<ActionResult<object>> GetCustomerDisplayPublicState(
        [FromQuery] string? code,
        [FromServices] Microsoft.Extensions.Caching.Distributed.IDistributedCache? dist)
    {
        var json = await ZKTecoADMS.Api.Services.PosCustomerDisplayStateStore.GetByViewerCodeAsync(code, dist);
        if (string.IsNullOrWhiteSpace(json))
            return NotFound(new { isSuccess = false, message = "Chưa có dữ liệu màn phụ — mở bán hàng trên máy thu ngân trước" });
        return Ok(new { isSuccess = true, data = new { stateJson = json } });
    }
}
