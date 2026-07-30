using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Đặt bàn trước — khách + món đặt trước; nhận bàn khi khách đến.</summary>
public partial class PosSellIndustryController
{
    public record ReservationPreOrderItemDto(
        Guid ProductId,
        Guid? VariantId = null,
        string? Name = null,
        decimal Qty = 1,
        decimal UnitPrice = 0,
        string? UnitName = null,
        string? Note = null);

    public record CreateReservationDto(
        Guid ResourceId,
        string CustomerName,
        string? Phone = null,
        int GuestCount = 1,
        Guid? CustomerId = null,
        DateTime? ReservedUntil = null,
        string? Note = null,
        List<ReservationPreOrderItemDto>? PreOrderItems = null);

    public record ReservationDto(
        Guid Id,
        Guid ResourceId,
        string ResourceCode,
        string ResourceName,
        string CustomerName,
        string? Phone,
        int GuestCount,
        DateTime ReservedAt,
        DateTime? ReservedUntil,
        string Status,
        string? Note,
        int PreOrderCount,
        string? PreOrderJson);

    [HttpGet("resource-reservations")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<ReservationDto>>>> ListReservations(
        [FromQuery] Guid? resourceId = null)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<List<ReservationDto>>.Fail("Thiếu cửa hàng"));

        var q = db.PosResourceReservations.AsNoTracking()
            .Include(x => x.Resource)
            .Where(x => x.StoreId == storeId && x.Deleted == null
                && x.Status == PosResourceReservationStatus.Booked);
        if (resourceId.HasValue)
            q = q.Where(x => x.ResourceId == resourceId.Value);

        var list = await q.OrderByDescending(x => x.ReservedAt).ToListAsync();
        var dtos = list.Select(ToReservationDto).ToList();
        return Ok(AppResponse<List<ReservationDto>>.Success(dtos));
    }

    [HttpPost("resource-reservations")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> CreateReservation(
        [FromBody] CreateReservationDto dto)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        if (string.IsNullOrWhiteSpace(dto.CustomerName))
            return BadRequest(AppResponse<object>.Fail("Nhập tên khách đặt bàn"));

        var resource = await db.PosServiceResources
            .FirstOrDefaultAsync(r => r.Id == dto.ResourceId && r.StoreId == storeId
                && r.Deleted == null && r.IsActive);
        if (resource == null)
            return BadRequest(AppResponse<object>.Fail("Bàn/phòng không hợp lệ"));

        var live = await db.PosResourceSessions.AnyAsync(s =>
            s.ResourceId == dto.ResourceId
            && (s.Status == PosResourceSessionStatus.Open || s.Status == PosResourceSessionStatus.Paused)
            && s.Deleted == null);
        if (live)
            return BadRequest(AppResponse<object>.Fail("Bàn đang mở — không đặt trước được"));

        var alreadyBooked = await db.PosResourceReservations.AnyAsync(x =>
            x.ResourceId == dto.ResourceId && x.StoreId == storeId && x.Deleted == null
            && x.Status == PosResourceReservationStatus.Booked);
        if (alreadyBooked)
            return BadRequest(AppResponse<object>.Fail("Bàn đã có đặt trước — hủy hoặc nhận bàn trước"));

        var now = DateTime.UtcNow;
        string? preJson = null;
        if (dto.PreOrderItems is { Count: > 0 })
        {
            preJson = JsonSerializer.Serialize(dto.PreOrderItems.Select(i => new
            {
                productId = i.ProductId,
                variantId = i.VariantId,
                name = i.Name,
                qty = i.Qty <= 0 ? 1 : i.Qty,
                unitPrice = i.UnitPrice,
                unitName = i.UnitName,
                note = i.Note,
            }));
        }

        var name = dto.CustomerName.Trim();
        if (dto.CustomerId.HasValue)
        {
            var cust = await db.PosCustomers.AsNoTracking()
                .FirstOrDefaultAsync(c => c.Id == dto.CustomerId && c.StoreId == storeId && c.Deleted == null);
            if (cust != null) name = cust.Name;
        }

        var entity = new PosResourceReservation
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            ResourceId = resource.Id,
            CustomerId = dto.CustomerId,
            CustomerName = name,
            Phone = string.IsNullOrWhiteSpace(dto.Phone) ? null : dto.Phone.Trim(),
            GuestCount = dto.GuestCount < 1 ? 1 : dto.GuestCount,
            ReservedAt = now,
            ReservedUntil = dto.ReservedUntil,
            Status = PosResourceReservationStatus.Booked,
            PreOrderJson = preJson,
            Note = string.IsNullOrWhiteSpace(dto.Note) ? null : dto.Note.Trim(),
            IsActive = true,
            CreatedBy = CurrentUserEmail,
            CreatedAt = now,
        };
        db.PosResourceReservations.Add(entity);
        await db.SaveChangesAsync();

        return Ok(AppResponse<object>.Success(new
        {
            id = entity.Id,
            resourceId = resource.Id,
            resourceName = resource.Name,
            customerName = entity.CustomerName,
            guestCount = entity.GuestCount,
            preOrderCount = dto.PreOrderItems?.Count ?? 0,
        }));
    }

    [HttpPost("resource-reservations/{id:guid}/cancel")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> CancelReservation(Guid id)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        var entity = await db.PosResourceReservations
            .AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.Deleted == null
                && (x.StoreId == storeId || x.StoreId == Guid.Empty));
        if (entity == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy đặt bàn"));
        if (entity.Status != PosResourceReservationStatus.Booked)
            return BadRequest(AppResponse<object>.Fail("Đặt bàn không còn hiệu lực"));

        var now = DateTime.UtcNow;
        if (entity.StoreId == Guid.Empty) entity.StoreId = storeId;
        entity.Status = PosResourceReservationStatus.Cancelled;
        entity.Deleted = now;
        entity.DeletedBy = CurrentUserEmail;
        entity.UpdatedAt = now;
        entity.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { cancelled = true, id = entity.Id }));
    }

    /// <summary>Khách đến — mở phiên, gắn món đặt trước vào đơn Draft.</summary>
    [HttpPost("resource-reservations/{id:guid}/seat")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> SeatReservation(Guid id)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        var booking = await db.PosResourceReservations
            .AsTracking()
            .Include(x => x.Resource)
            .FirstOrDefaultAsync(x => x.Id == id && x.Deleted == null
                && (x.StoreId == storeId || x.StoreId == Guid.Empty));
        if (booking == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy đặt bàn"));
        if (booking.Status != PosResourceReservationStatus.Booked)
            return BadRequest(AppResponse<object>.Fail("Đặt bàn không còn hiệu lực"));
        if (booking.StoreId == Guid.Empty) booking.StoreId = storeId;

        // DbContext mặc định NoTracking — bắt buộc AsTracking để SaveChangesAsync thực sự ghi resource.
        var resource = booking.Resource
            ?? await db.PosServiceResources.AsTracking().FirstOrDefaultAsync(r =>
                r.Id == booking.ResourceId && r.StoreId == storeId && r.Deleted == null);
        if (resource == null || !resource.IsActive)
            return BadRequest(AppResponse<object>.Fail("Bàn/phòng không hợp lệ"));

        var live = await db.PosResourceSessions.AnyAsync(s =>
            s.ResourceId == booking.ResourceId
            && (s.Status == PosResourceSessionStatus.Open || s.Status == PosResourceSessionStatus.Paused)
            && s.Deleted == null);
        if (live)
            return BadRequest(AppResponse<object>.Fail("Bàn đang có phiên mở"));

        try
        {
            var now = DateTime.UtcNow;
            var (orderNo, invoiceSlot) = await AllocateTableDraftNoAsync(storeId);

            var order = new PosSaleOrder
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                OrderNo = orderNo,
                InvoiceSlot = invoiceSlot,
                Status = PosSaleOrderStatus.Draft,
                PaymentMethod = "Tiền mặt",
                CustomerId = booking.CustomerId,
                CustomerName = string.IsNullOrWhiteSpace(booking.CustomerName)
                    ? "Bán cho người tiêu dùng"
                    : booking.CustomerName,
                ServiceResourceId = resource.Id,
                ServiceStartedAt = now,
                SaleDate = now,
                SalesChannel = "Tại chỗ",
                Note = booking.Note,
                IsActive = true,
                CreatedBy = CurrentUserEmail,
                CreatedAt = now,
            };
            var lockDisplay = CurrentUserEmail;
            if (string.IsNullOrWhiteSpace(lockDisplay))
                lockDisplay = CurrentUserId.ToString("N")[..8];
            PosDraftLockHelper.AssignOnCreate(
                order,
                new PosDraftLockHelper.LockActor(
                    CurrentUserId, EmployeeId, lockDisplay!, null, null));

            db.PosSaleOrders.Add(order);
            await db.SaveChangesAsync();

            var preCount = await ApplyPreOrderLinesAsync(storeId, order, booking.PreOrderJson, now);

            var session = new PosResourceSession
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                ResourceId = resource.Id,
                SaleOrderId = order.Id,
                CustomerId = booking.CustomerId,
                StartedAt = now,
                Status = PosResourceSessionStatus.Open,
                GuestCount = booking.GuestCount < 1 ? 1 : booking.GuestCount,
                Note = booking.Note,
                IsActive = true,
                CreatedBy = CurrentUserEmail,
                CreatedAt = now,
            };
            db.PosResourceSessions.Add(session);

            order.ResourceSessionId = session.Id;
            order.UpdatedAt = now;

            booking.Status = PosResourceReservationStatus.Seated;
            booking.SeatedSessionId = session.Id;
            booking.UpdatedAt = now;
            booking.UpdatedBy = CurrentUserEmail;

            resource.NeedsCleaning = false;
            resource.UpdatedAt = now;

            await db.SaveChangesAsync();

            return Ok(AppResponse<object>.Success(new
            {
                sessionId = session.Id,
                saleOrderId = order.Id,
                orderNo = order.OrderNo,
                resourceId = resource.Id,
                resourceCode = resource.Code,
                resourceName = resource.Name,
                startedAt = session.StartedAt,
                guestCount = session.GuestCount,
                customerName = order.CustomerName,
                preOrderLines = preCount,
                reservationId = booking.Id,
            }));
        }
        catch (DbUpdateException ex)
        {
            var detail = ex.InnerException?.Message ?? ex.Message;
            var msg = detail.Contains("23505", StringComparison.Ordinal)
                ? "Mã đơn tạm bị trùng — thử lại lần nữa"
                : "Không nhận bàn được. Thử lại.";
            return BadRequest(AppResponse<object>.Fail(msg));
        }
    }

    async Task<int> ApplyPreOrderLinesAsync(
        Guid storeId, PosSaleOrder order, string? preOrderJson, DateTime now)
    {
        if (string.IsNullOrWhiteSpace(preOrderJson)) return 0;

        List<ReservationPreOrderItemDto>? items;
        try
        {
            items = JsonSerializer.Deserialize<List<ReservationPreOrderItemDto>>(
                preOrderJson,
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        }
        catch
        {
            return 0;
        }

        if (items == null || items.Count == 0) return 0;

        var productIds = items.Select(i => i.ProductId).Distinct().ToList();
        var products = await db.PosProducts.AsNoTracking()
            .Where(p => productIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
            .ToDictionaryAsync(p => p.Id);

        decimal subTotal = 0;
        var added = 0;
        foreach (var item in items)
        {
            if (!products.TryGetValue(item.ProductId, out var p)) continue;
            var qty = item.Qty <= 0 ? 1 : item.Qty;
            var unitPrice = item.UnitPrice > 0 ? item.UnitPrice : p.BasePrice;
            var name = string.IsNullOrWhiteSpace(item.Name) ? p.Name : item.Name!.Trim();
            var lineTotal = qty * unitPrice;
            subTotal += lineTotal;
            db.PosSaleOrderLines.Add(new PosSaleOrderLine
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                SaleOrderId = order.Id,
                ProductId = p.Id,
                VariantId = item.VariantId,
                ProductName = name,
                UnitName = string.IsNullOrWhiteSpace(item.UnitName) ? p.BaseUnitName : item.UnitName,
                Qty = qty,
                UnitPrice = unitPrice,
                DiscountAmount = 0,
                LineTotal = lineTotal,
                LineNote = string.IsNullOrWhiteSpace(item.Note) ? null : item.Note.Trim(),
                IsActive = true,
                CreatedBy = CurrentUserEmail,
                CreatedAt = now,
            });
            added++;
        }

        order.SubTotal = subTotal;
        order.Total = subTotal;
        return added;
    }

    static ReservationDto ToReservationDto(PosResourceReservation x)
    {
        var preCount = 0;
        if (!string.IsNullOrWhiteSpace(x.PreOrderJson))
        {
            try
            {
                using var doc = JsonDocument.Parse(x.PreOrderJson);
                if (doc.RootElement.ValueKind == JsonValueKind.Array)
                    preCount = doc.RootElement.GetArrayLength();
            }
            catch { /* ignore */ }
        }

        return new ReservationDto(
            x.Id,
            x.ResourceId,
            x.Resource?.Code ?? "",
            x.Resource?.Name ?? "",
            x.CustomerName,
            x.Phone,
            x.GuestCount,
            x.ReservedAt,
            x.ReservedUntil,
            x.Status.ToString(),
            x.Note,
            preCount,
            x.PreOrderJson);
    }
}
