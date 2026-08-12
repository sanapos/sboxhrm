using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Chuy?n/t�ch/g?p b�n, pause, b�o b?p, layout so d?.</summary>
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

    /// <summary>DTO class (kh�ng d�ng positional record) � tr�nh JSON bind sai layoutX/Y.</summary>
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
            return BadRequest(AppResponse<object>.Fail("Thi?u c?a h�ng"));
        var session = await db.PosResourceSessions
            .AsTracking().FirstOrDefaultAsync(s => s.Id == id && s.StoreId == storeId && s.Deleted == null);
        if (session == null) return NotFound(AppResponse<object>.Fail("Kh�ng t�m th?y phi�n"));
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

    [HttpPost("resource-sessions/{id:guid}/resume")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> ResumeSession(Guid id)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thi?u c?a h�ng"));
        var session = await db.PosResourceSessions
            .AsTracking().FirstOrDefaultAsync(s => s.Id == id && s.StoreId == storeId && s.Deleted == null);
        if (session == null) return NotFound(AppResponse<object>.Fail("Kh�ng t�m th?y phi�n"));
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

    /// <summary>��ng phi�n Open/Paused m� don kh�ng c�n Draft � tr�nh b�n �tr?ng� tr�n UI nhung API b�o dang c� kh�ch.</summary>
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
            return BadRequest(AppResponse<object>.Fail("Thi?u c?a h�ng"));
        if (dto == null || dto.TargetResourceId == Guid.Empty)
            return BadRequest(AppResponse<object>.Fail("Thi?u b�n d�ch"));

        // Cho ph�p StoreId r?ng (phi�n cu) � gi?ng request-bill.
        var session = await db.PosResourceSessions
            .AsTracking().FirstOrDefaultAsync(s => s.Id == id && s.Deleted == null
                && (s.StoreId == storeId || s.StoreId == Guid.Empty));
        // Fallback: id c� th? l� resourceId (client g?i nh?m) ? l?y phi�n live c?a b�n.
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
        if (session == null) return NotFound(AppResponse<object>.Fail("Kh�ng t�m th?y phi�n"));
        if (!IsSessionLive(session.Status))
            return BadRequest(AppResponse<object>.Fail("Phi�n d� d�ng"));
        if (session.StoreId == Guid.Empty)
            session.StoreId = storeId;

        var target = await db.PosServiceResources
            .AsTracking().FirstOrDefaultAsync(r => r.Id == dto.TargetResourceId && r.StoreId == storeId
                && r.Deleted == null && r.IsActive);
        if (target == null) return BadRequest(AppResponse<object>.Fail("B�n ?�ch kh�ng h?p l?"));
        if (target.Id == session.ResourceId)
            return BadRequest(AppResponse<object>.Fail("B�n ?�ch tr�ng b�n hi?n t?i"));
        if (!await CanOperateResourceAsync(storeId, session.ResourceId)
            || !await CanOperateAreaAsync(storeId, target.AreaId))
            return BadRequest(AppResponse<object>.Fail("Bạn không được phép chuyển bàn ngoài khu vực được gán"));

        await CloseOrphanLiveSessionsOnResourceAsync(storeId, target.Id);

        var busy = await db.PosResourceSessions.AnyAsync(s =>
            s.ResourceId == target.Id && s.Deleted == null
            && (s.Status == PosResourceSessionStatus.Open
                || s.Status == PosResourceSessionStatus.Paused));
        if (busy) return BadRequest(AppResponse<object>.Fail("B�n d�ch dang c� kh�ch"));

        // H?y d?t tru?c c�n s�t tr�n b�n d�ch.
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

        // ???t tru?c tr�n b�n ngu?n (n?u c�n) ? d� d�ng xong du??ng chuy?n.
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

    /// <summary>Chuy?n b�n theo resourceId ngu?n (tin c?y hon sessionId tr�n so d?).</summary>
    [HttpPost("service-resources/{id:guid}/transfer")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> TransferByResource(
        Guid id, [FromBody] TransferSessionDto? dto)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thi?u c?a h�ng"));
        var live = await db.PosResourceSessions
            .AsTracking().Where(s => s.ResourceId == id && s.Deleted == null
                && (s.StoreId == storeId || s.StoreId == Guid.Empty)
                && (s.Status == PosResourceSessionStatus.Open
                    || s.Status == PosResourceSessionStatus.Paused))
            .OrderByDescending(s => s.StartedAt)
            .FirstOrDefaultAsync();
        if (live == null)
            return NotFound(AppResponse<object>.Fail("B�n ngu?n kh�ng c� phi�n dang m?"));
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
            return BadRequest(AppResponse<object>.Fail("Thi?u c?a h�ng"));
        if (dto.LineIds == null || dto.LineIds.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Ch??n �t nh?t m?t d�ng d? t�ch"));

        var session = await db.PosResourceSessions
            .AsTracking().FirstOrDefaultAsync(s => s.Id == id && s.Deleted == null
                && (s.StoreId == storeId || s.StoreId == Guid.Empty));
        if (session == null || !session.SaleOrderId.HasValue)
            return NotFound(AppResponse<object>.Fail("Kh?ng t?m th?y phi?n/don"));
        if (!IsSessionLive(session.Status))
            return BadRequest(AppResponse<object>.Fail("Phi�n d� d�ng"));
        if (session.StoreId == Guid.Empty)
            session.StoreId = storeId;

        var target = await db.PosServiceResources
            .AsTracking().FirstOrDefaultAsync(r => r.Id == dto.TargetResourceId && r.StoreId == storeId
                && r.Deleted == null && r.IsActive);
        if (target == null) return BadRequest(AppResponse<object>.Fail("B�n d�ch kh�ng h?p l?"));

        if (!await CanOperateResourceAsync(storeId, session.ResourceId)
            || !await CanOperateAreaAsync(storeId, target.AreaId))
            return BadRequest(AppResponse<object>.Fail(
                "Bạn không được phép tách bàn ngoài khu vực được gán"));

        await CloseOrphanLiveSessionsOnResourceAsync(storeId, target.Id);

        var busy = await db.PosResourceSessions.AnyAsync(s =>
            s.ResourceId == target.Id && s.Deleted == null
            && (s.Status == PosResourceSessionStatus.Open
                || s.Status == PosResourceSessionStatus.Paused));
        if (busy) return BadRequest(AppResponse<object>.Fail("B�n d�ch dang c� kh�ch"));

        await ClearBookedReservationsOnResourceAsync(storeId, target.Id, asSeated: false);

        var sourceOrder = await db.PosSaleOrders
            .AsTracking().Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == session.SaleOrderId
                && (o.StoreId == storeId || o.StoreId == Guid.Empty));
        if (sourceOrder == null) return NotFound(AppResponse<object>.Fail("Kh�ng t�m th?y don"));
        if (sourceOrder.StoreId == Guid.Empty)
            sourceOrder.StoreId = storeId;

        var moveLines = sourceOrder.Lines
            .Where(l => l.Deleted == null && dto.LineIds.Contains(l.Id))
            .ToList();
        if (moveLines.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Kh�ng c� d�ng h?p l? d? t�ch"));
        if (moveLines.Count >= sourceOrder.Lines.Count(l => l.Deleted == null))
            return BadRequest(AppResponse<object>.Fail("Kh�ng t�ch h?t m�n � d�ng chuy?n b�n"));

        // M? phi�n + don m?i tr�n b�n d�ch (t�ch FK: don tru?c ? phi�n ? g?n l?i).
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
            SalesChannel = sourceOrder.SalesChannel ?? "T?i ch?",
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
            // B?t bu?c Remove kh??i collection ngu?n � n?u kh�ng EF v?n t�nh d�ng v�o don cu
            // v� autosave client c� th? ghi d� tr? m�n v?? b�n ngu?n.
            sourceOrder.Lines.Remove(line);
            line.SaleOrderId = newOrder.Id;
            line.ServiceStartedAt ??= session.StartedAt;
            line.UpdatedAt = now;
            line.UpdatedBy = CurrentUserEmail;
            newOrder.Lines.Add(line);
        }

        RecalcOrderTotals(sourceOrder);
        RecalcOrderTotals(newOrder);

        // Bump lockVersion don ngu?n � client cu dang gi? gi?? full s? conflict thay v� ghi d�.
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

    [HttpPost("resource-sessions/{id:guid}/merge")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> MergeSession(Guid id, [FromBody] MergeSessionDto? dto)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thi?u c?a h�ng"));
        if (dto == null || dto.SourceSessionId == Guid.Empty)
            return BadRequest(AppResponse<object>.Fail("Thi?u b�n ngu?n d? g?p"));
        if (dto.SourceSessionId == id)
            return BadRequest(AppResponse<object>.Fail("Kh�ng g?p c�ng m?t phi�n"));

        var targetSession = await db.PosResourceSessions
            .AsTracking().FirstOrDefaultAsync(s => s.Id == id && s.Deleted == null
                && (s.StoreId == storeId || s.StoreId == Guid.Empty));
        var sourceSession = await db.PosResourceSessions
            .AsTracking().FirstOrDefaultAsync(s => s.Id == dto.SourceSessionId && s.Deleted == null
                && (s.StoreId == storeId || s.StoreId == Guid.Empty));
        if (targetSession == null || sourceSession == null)
            return NotFound(AppResponse<object>.Fail("Kh�ng t�m th?y phi�n"));
        if (!IsSessionLive(targetSession.Status) || !IsSessionLive(sourceSession.Status))
            return BadRequest(AppResponse<object>.Fail("C? hai phi�n ph?i dang m?"));
        if (!targetSession.SaleOrderId.HasValue || !sourceSession.SaleOrderId.HasValue)
            return BadRequest(AppResponse<object>.Fail("Phi�n thi?u don Draft"));
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
            return NotFound(AppResponse<object>.Fail("Kh�ng t�m th?y don"));
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
            ? $"G?p v�o {targetOrder.OrderNo}"
            : $"{sourceOrder.Note} � G?p v�o {targetOrder.OrderNo}";

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
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> SetGuestCount(Guid id, [FromBody] GuestCountDto dto)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thi?u c?a h�ng"));
        var session = await db.PosResourceSessions
            .AsTracking().FirstOrDefaultAsync(s => s.Id == id && s.StoreId == storeId && s.Deleted == null);
        if (session == null) return NotFound(AppResponse<object>.Fail("Kh�ng t�m th?y phi�n"));
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
            return NotFound(AppResponse<object>.Fail("Kh�ng t�m th?y phi�n"));

        // N?u phi�n d� d�ng / l?ch store ? chuy?n sang phi�n Open/Paused dang s?ng c?a b�n.
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
                    "Phi�n b�n d� d�ng � m? l?i b�n r?i in t?m t�nh"));
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

    /// ??�nh d?u t?m t�nh theo b�n (l?y phi�n Open dang s?ng) � du??ng tin c?y cho so d?.
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
            return NotFound(AppResponse<object>.Fail("B�n kh�ng c� phi�n dang m?"));

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
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> MarkCleaned(Guid id)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thi?u c?a h�ng"));
        var resource = await db.PosServiceResources
            .AsTracking().FirstOrDefaultAsync(r => r.Id == id && r.StoreId == storeId && r.Deleted == null);
        if (resource == null) return NotFound(AppResponse<object>.Fail("Kh�ng t�m th?y"));

        var now = DateTime.UtcNow;
        resource.NeedsCleaning = false;
        resource.UpdatedAt = now;
        resource.UpdatedBy = CurrentUserEmail;

        // ??�ng lu�n phi�n orphan c�n s�t (don d� TT) � tr�nh b�n k?t �c?n d??n�.
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
            if (orderOk) continue; // c�n don t?m th?t � kh�ng d�ng khi ch? �d� d??n�
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

    /// <summary>��nh d?u m�n d� b�o ch? bi?n / g?i b?p (theo d�ng ho?c t?t c? chua g?i).</summary>
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
            return NotFound(AppResponse<object>.Fail("Kh�ng t�m th?y phi�n/don"));

        var order = await db.PosSaleOrders
            .AsTracking().FirstOrDefaultAsync(o => o.Id == session.SaleOrderId && o.StoreId == storeId
                && o.Deleted == null);
        if (order == null)
            return NotFound(AppResponse<object>.Fail("Kh�ng t�m th?y don"));

        var lockDisplay = string.IsNullOrWhiteSpace(CurrentUserEmail)
            ? CurrentUserId.ToString("N")[..8]
            : CurrentUserEmail!;
        var actor = new PosDraftLockHelper.LockActor(
            CurrentUserId, EmployeeId, lockDisplay, dto?.DeviceId, dto?.DeviceName);
        var lockErr = PosDraftLockHelper.EnsureCanMutate(order, actor, expectedLockVersion: null);
        if (lockErr != null)
            return Conflict(AppResponse<object>.Fail(lockErr));

        // Ghim m�y n?u kh�a cu thi?u device (client m?i).
        PosDraftLockHelper.StampDeviceIfMissing(order, actor);

        // H?t TTL / chua kh�a ? chi?m quy?n m�y dang b�o b?p.
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
            // Ch? b�o ph?n chua g?i � tr�nh in tr�ng bill c�ng m�n/qty.
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
        NotifyFloorChanged(storeId, "kitchenSend",
            orderId: session.SaleOrderId, resourceId: session.ResourceId, sessionId: session.Id);
        return Ok(AppResponse<object>.Success(new
        {
            sentLines = sent,
            sentQty,
            alreadyAllSent = sent == 0,
            saleOrderId = session.SaleOrderId,
            kitchenSentAt = now,
            lockVersion = order.LockVersion,
            message = sent == 0
                ? "Kh�ng c� m�n m?i � c�c m�n d� b�o b?p r?i"
                : $"�� b�o {sent} d�ng ({sentQty:0.###} ph?n) l�n b?p",
        }));
    }

    [HttpPut("service-resources/layout")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> SaveLayout([FromBody] LayoutBatchDto? dto)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thi?u c?a h�ng"));
        if (dto?.Items == null || dto.Items.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Kh�ng c� v? tr�"));

        var saved = 0;
        var now = DateTime.UtcNow;
        var by = CurrentUserEmail;
        foreach (var item in dto.Items)
        {
            if (item.Id == Guid.Empty) continue;
            // ExecuteUpdate ghi th?ng DB � kh�ng ph? thu?c change-tracker.
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
                "Kh�ng kh?p b�n n�o � ki?m tra id / c?a h�ng"));

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
        string? DeviceName = null,
        string? Reason = null,
        string? DetailNote = null);

    /// <summary>Ghi phi?u h?y m�n d� b�o b?p (d?i so�t / ch?ng gian l?n sau t?m t�nh).</summary>
    [HttpPost("kitchen-voids")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> CreateKitchenVoids([FromBody] KitchenVoidBatchDto dto)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thi?u c?a h�ng"));
        if (dto.Lines == null || dto.Lines.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Kh�ng c� d�ng h?y"));

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
            });
        }
        if (rows.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Kh�ng c� d�ng h?y h?p l?"));

        db.PosKitchenVoidSlips.AddRange(rows);
        foreach (var r in rows)
        {
            db.PosCancelReturnAudits.Add(new PosCancelReturnAudit
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                ActionType = "KitchenVoid",
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
                Amount = 0,
                OccurredAt = now,
                Actor = who,
                DeviceName = r.DeviceName,
                IsActive = true,
                CreatedAt = now,
                CreatedBy = who,
            });
        }
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
            return BadRequest(AppResponse<object>.Fail("Thi?u c?a h�ng"));

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

    /// <summary>Lịch sử hủy món / hủy đơn / trả hàng (lọc thao tác + trước/sau tạm tính).</summary>
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

        var q = db.PosCancelReturnAudits.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null);
        if (from.HasValue) q = q.Where(x => x.OccurredAt >= from.Value.ToUniversalTime());
        if (to.HasValue) q = q.Where(x => x.OccurredAt <= to.Value.ToUniversalTime());
        if (!string.IsNullOrWhiteSpace(actionType))
        {
            var at = actionType.Trim();
            q = q.Where(x => x.ActionType == at);
        }
        if (afterBillOnly == true) q = q.Where(x => x.AfterProvisionalBill);
        if (beforeBillOnly == true) q = q.Where(x => !x.AfterProvisionalBill);
        if (!string.IsNullOrWhiteSpace(actor))
        {
            var a = actor.Trim().ToLower();
            q = q.Where(x => x.Actor != null && x.Actor.ToLower().Contains(a));
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

        take = Math.Clamp(take, 1, 500);
        var list = await q.OrderByDescending(x => x.OccurredAt).Take(take)
            .Select(x => new
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
                x.DeviceName,
            })
            .ToListAsync();

        return Ok(AppResponse<object>.Success(new
        {
            items = list,
            kitchenVoidCount = list.Count(x => x.ActionType == "KitchenVoid"),
            saleCancelCount = list.Count(x => x.ActionType == "SaleCancel"),
            saleReturnCount = list.Count(x => x.ActionType == "SaleReturn"),
            afterBillCount = list.Count(x => x.AfterProvisionalBill),
            beforeBillCount = list.Count(x => !x.AfterProvisionalBill),
        }));
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
    public ActionResult<AppResponse<object>> PutCustomerDisplayState([FromBody] CustomerDisplayStateDto dto)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        if (string.IsNullOrWhiteSpace(dto.StateJson))
            return BadRequest(AppResponse<object>.Fail("Thiếu state"));

        var code = (dto.ViewerCode ?? "").Trim();
        if (code.Length < 4)
            return BadRequest(AppResponse<object>.Fail("Thiếu mã xem màn phụ (viewerCode)"));

        ZKTecoADMS.Api.Services.PosCustomerDisplayStateStore.Publish(storeId, code, dto.StateJson.Trim());
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
    public ActionResult<object> GetCustomerDisplayPublicState([FromQuery] string? code)
    {
        var json = ZKTecoADMS.Api.Services.PosCustomerDisplayStateStore.GetByViewerCode(code);
        if (string.IsNullOrWhiteSpace(json))
            return NotFound(new { isSuccess = false, message = "Chưa có dữ liệu màn phụ — mở bán hàng trên máy thu ngân trước" });
        return Ok(new { isSuccess = true, data = new { stateJson = json } });
    }
}
