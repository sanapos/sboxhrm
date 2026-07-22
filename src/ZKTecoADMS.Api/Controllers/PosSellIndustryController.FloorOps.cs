using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
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
    public record MergeSessionDto(Guid SourceSessionId);
    public record GuestCountDto(int GuestCount);
    public record KitchenSendDto(
        List<Guid>? LineIds = null,
        string? DeviceId = null,
        string? DeviceName = null);

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
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> PauseSession(Guid id)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        var session = await db.PosResourceSessions
            .AsTracking().FirstOrDefaultAsync(s => s.Id == id && s.StoreId == storeId && s.Deleted == null);
        if (session == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy phiên"));
        if (session.Status != PosResourceSessionStatus.Open)
            return BadRequest(AppResponse<object>.Fail("Chỉ tạm dừng phiên đang mở"));

        session.Status = PosResourceSessionStatus.Paused;
        session.PausedAt = DateTime.UtcNow;
        session.UpdatedAt = DateTime.UtcNow;
        session.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { sessionId = session.Id, status = "Paused" }));
    }

    [HttpPost("resource-sessions/{id:guid}/resume")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> ResumeSession(Guid id)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        var session = await db.PosResourceSessions
            .AsTracking().FirstOrDefaultAsync(s => s.Id == id && s.StoreId == storeId && s.Deleted == null);
        if (session == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy phiên"));
        if (session.Status != PosResourceSessionStatus.Paused)
            return BadRequest(AppResponse<object>.Fail("Phiên không ở trạng thái tạm dừng"));

        if (session.PausedAt.HasValue)
        {
            var pauseMins = (int)Math.Max(0, (DateTime.UtcNow - session.PausedAt.Value).TotalMinutes);
            session.AccumulatedPauseMinutes += pauseMins;
        }
        session.PausedAt = null;
        session.Status = PosResourceSessionStatus.Open;
        session.UpdatedAt = DateTime.UtcNow;
        session.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync();
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
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
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

        // �?ặt trước trên bàn nguồn (nếu còn) → đã dùng xong đư�?ng chuyển.
        await ClearBookedReservationsOnResourceAsync(storeId, fromId, asSeated: true);

        await db.SaveChangesAsync();
        var areaName = await db.PosServiceAreas.AsNoTracking()
            .Where(a => a.Id == target.AreaId)
            .Select(a => a.Name)
            .FirstOrDefaultAsync();
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
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
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
        await db.PosResourceReservations
            .Where(x => x.ResourceId == resourceId && x.Deleted == null
                && (x.StoreId == storeId || x.StoreId == Guid.Empty)
                && x.Status == PosResourceReservationStatus.Booked)
            .ExecuteUpdateAsync(s => s
                .SetProperty(x => x.Status, status)
                .SetProperty(x => x.UpdatedAt, now)
                .SetProperty(x => x.UpdatedBy, CurrentUserEmail)
                .SetProperty(x => x.Deleted, now));
    }

    [HttpPost("resource-sessions/{id:guid}/split")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> SplitSession(Guid id, [FromBody] SplitSessionDto dto)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        if (dto.LineIds == null || dto.LineIds.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Ch�?n ít nhất một dòng để tách"));

        var session = await db.PosResourceSessions
            .AsTracking().FirstOrDefaultAsync(s => s.Id == id && s.Deleted == null
                && (s.StoreId == storeId || s.StoreId == Guid.Empty));
        if (session == null || !session.SaleOrderId.HasValue)
            return NotFound(AppResponse<object>.Fail("Kh�ng t�m th?y phi�n/đơn"));
        if (!IsSessionLive(session.Status))
            return BadRequest(AppResponse<object>.Fail("Phiên đã đóng"));
        if (session.StoreId == Guid.Empty)
            session.StoreId = storeId;

        var target = await db.PosServiceResources
            .AsTracking().FirstOrDefaultAsync(r => r.Id == dto.TargetResourceId && r.StoreId == storeId
                && r.Deleted == null && r.IsActive);
        if (target == null) return BadRequest(AppResponse<object>.Fail("Bàn đích không hợp lệ"));

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
            ServiceStartedAt = now,
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
            StartedAt = now,
            Status = PosResourceSessionStatus.Open,
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
            // Bắt buộc Remove kh�?i collection nguồn — nếu không EF vẫn tính dòng vào đơn cũ
            // và autosave client có thể ghi đè trả món v�? bàn nguồn.
            sourceOrder.Lines.Remove(line);
            line.SaleOrderId = newOrder.Id;
            line.UpdatedAt = now;
            line.UpdatedBy = CurrentUserEmail;
            newOrder.Lines.Add(line);
        }

        RecalcOrderTotals(sourceOrder);
        RecalcOrderTotals(newOrder);

        // Bump lockVersion đơn nguồn — client cũ đang giữ gi�? full sẽ conflict thay vì ghi đè.
        sourceOrder.LockVersion = Math.Max(1, sourceOrder.LockVersion) + 1;
        sourceOrder.UpdatedAt = now;
        sourceOrder.UpdatedBy = CurrentUserEmail;

        target.NeedsCleaning = false;
        await db.SaveChangesAsync();

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

    [HttpPost("resource-sessions/{id:guid}/merge")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
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
        var moveLines = sourceOrder.Lines.Where(l => l.Deleted == null).ToList();
        foreach (var line in moveLines)
        {
            sourceOrder.Lines.Remove(line);
            line.SaleOrderId = targetOrder.Id;
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
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
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
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> RequestBill(Guid id, [FromQuery] bool requested = true)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));

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
        return Ok(AppResponse<object>.Success(new
        {
            billRequested = live.BillRequested,
            sessionId = live.Id,
            resourceId = live.ResourceId,
        }));
    }

    /// �?ánh dấu tạm tính theo bàn (lấy phiên Open đang sống) — đư�?ng tin cậy cho sơ đồ.
    [HttpPost("service-resources/{id:guid}/request-bill")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> RequestBillByResource(
        Guid id, [FromQuery] bool requested = true)
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
            return NotFound(AppResponse<object>.Fail("Bàn không có phiên đang mở"));

        if (live.StoreId == Guid.Empty)
            live.StoreId = storeId;
        live.BillRequested = requested;
        live.UpdatedAt = DateTime.UtcNow;
        live.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new
        {
            billRequested = live.BillRequested,
            sessionId = live.Id,
            resourceId = live.ResourceId,
        }));
    }

    [HttpPost("service-resources/{id:guid}/clean")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
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

        // �?óng luôn phiên orphan còn sót (đơn đã TT) — tránh bàn kẹt «cần d�?n».
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
            if (orderOk) continue; // còn đơn tạm thật — không đóng khi chỉ «đã d�?n»
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

    /// <summary>Đánh dấu món đã báo chế biến / gửi bếp (theo dòng hoặc tất cả chưa gửi).</summary>
    [HttpPost("resource-sessions/{id:guid}/kitchen-send")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> KitchenSend(Guid id, [FromBody] KitchenSendDto? dto)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
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
        foreach (var line in lines)
        {
            if (dto?.LineIds is { Count: > 0 } && !dto.LineIds.Contains(line.Id))
                continue;
            // Chỉ báo phần chưa gửi — tránh in trùng bill cùng món/qty.
            var pending = line.Qty - line.KitchenSentQty;
            if (pending <= 0) continue;
            line.KitchenSentQty = line.Qty;
            line.KitchenSentAt = now;
            line.UpdatedAt = now;
            line.UpdatedBy = CurrentUserEmail;
            sent++;
            sentQty += pending;
        }

        if (sent > 0)
            PosDraftLockHelper.BumpVersionOnly(order, now);

        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new
        {
            sentLines = sent,
            sentQty,
            alreadyAllSent = sent == 0,
            saleOrderId = session.SaleOrderId,
            kitchenSentAt = now,
            lockVersion = order.LockVersion,
            message = sent == 0
                ? "Không có món mới — các món đã báo bếp rồi"
                : $"Đã báo {sent} dòng ({sentQty:0.###} phần) lên bếp",
        }));
    }

    [HttpPut("service-resources/layout")]
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
        string? LineNote = null);

    public record KitchenVoidBatchDto(
        List<KitchenVoidLineDto> Lines,
        Guid? SaleOrderId = null,
        string? OrderNo = null,
        Guid? ResourceSessionId = null,
        Guid? ServiceResourceId = null,
        string? ResourceName = null,
        bool Printed = true,
        string? DeviceName = null);

    /// <summary>Ghi phiếu hủy món đã báo bếp (đối soát / chống gian lận sau tạm tính).</summary>
    [HttpPost("kitchen-voids")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
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

        var now = DateTime.UtcNow;
        var who = CurrentUserEmail;
        var rows = new List<PosKitchenVoidSlip>();
        foreach (var line in dto.Lines.Where(l => l.Qty > 0 && !string.IsNullOrWhiteSpace(l.ProductName)))
        {
            rows.Add(new PosKitchenVoidSlip
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
                AfterBillRequested = afterBill,
                Printed = dto.Printed,
                VoidedAt = now,
                VoidedBy = who,
                DeviceName = dto.DeviceName?.Trim(),
                IsActive = true,
                CreatedAt = now,
                CreatedBy = who,
            });
        }
        if (rows.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Không có dòng hủy hợp lệ"));

        db.PosKitchenVoidSlips.AddRange(rows);
        await db.SaveChangesAsync();
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

    static void RecalcOrderTotals(PosSaleOrder order)
    {
        var lines = order.Lines?.Where(l => l.Deleted == null).ToList() ?? [];
        order.SubTotal = lines.Sum(l => l.LineTotal);
        order.Total = Math.Max(0, order.SubTotal - order.Discount);
        order.UpdatedAt = DateTime.UtcNow;
    }
}
