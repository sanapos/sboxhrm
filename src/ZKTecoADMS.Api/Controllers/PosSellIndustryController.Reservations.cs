using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Đặt bàn trước — khách + món + cọc; nhận bàn khi khách đến.</summary>
public partial class PosSellIndustryController
{
    /// <summary>Phút grace sau ReservedUntil trước khi đánh NoShow.</summary>
    const int ReservationNoShowGraceMinutes = 15;

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
        /// <summary>Giờ khách đến (F&amp;B) hoặc bắt đầu slot (salon).</summary>
        DateTime? ReservedUntil = null,
        /// <summary>Bắt đầu khung giờ hẹn (salon). Null = dùng ReservedUntil hoặc now.</summary>
        DateTime? SlotStart = null,
        int? DurationMinutes = null,
        /// <summary>Khách sạn: số đêm. Ghi đè DurationMinutes = StayNights × 24h.</summary>
        int? StayNights = null,
        Guid? ServiceProductId = null,
        Guid? AssignedEmployeeId = null,
        string? Note = null,
        List<ReservationPreOrderItemDto>? PreOrderItems = null,
        decimal DepositAmount = 0,
        decimal DepositPaid = 0,
        string? DepositPaymentMethod = null);

    public record CollectDepositDto(
        decimal Amount,
        string? PaymentMethod = null);

    public record CancelReservationDto(
        bool ForfeitDeposit = false,
        bool RefundDeposit = false);

    public record ReservationDto(
        Guid Id,
        Guid ResourceId,
        string ResourceCode,
        string ResourceName,
        string? AreaName,
        string CustomerName,
        string? Phone,
        Guid? CustomerId,
        int GuestCount,
        DateTime ReservedAt,
        DateTime? ReservedUntil,
        string Status,
        string? Note,
        int PreOrderCount,
        string? PreOrderJson,
        decimal DepositAmount,
        decimal DepositPaid,
        string DepositStatus,
        string? DepositPaymentMethod,
        DateTime? DepositPaidAt,
        int? DurationMinutes = null,
        Guid? ServiceProductId = null,
        string? ServiceProductName = null,
        Guid? AssignedEmployeeId = null,
        string? AssignedEmployeeName = null,
        bool IsTimedSlot = false,
        decimal PreOrderValue = 0,
        string? ResourceKind = null);

    [HttpGet("resource-reservations")]
    [RequireModulePermission("PosBooking", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<ReservationDto>>>> ListReservations(
        [FromQuery] Guid? resourceId = null,
        [FromQuery] DateTime? day = null,
        [FromQuery] bool includeClosed = false)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<List<ReservationDto>>.Fail("Thiếu cửa hàng"));

        await ExpireOverdueReservationsAsync(storeId);

        var q = db.PosResourceReservations.AsNoTracking()
            .Include(x => x.Resource)!.ThenInclude(r => r!.Area)
            .Include(x => x.ServiceProduct)
            .Include(x => x.AssignedEmployee)
            .Where(x => x.StoreId == storeId);
        if (!includeClosed)
            q = q.Where(x => x.Deleted == null && x.Status == PosResourceReservationStatus.Booked);
        else
            q = q.Where(x => x.Deleted == null || x.Status != PosResourceReservationStatus.Booked);
        if (resourceId.HasValue)
            q = q.Where(x => x.ResourceId == resourceId.Value);
        if (day.HasValue)
        {
            var d = day.Value.Kind == DateTimeKind.Unspecified
                ? DateTime.SpecifyKind(day.Value.Date, DateTimeKind.Utc)
                : day.Value.ToUniversalTime().Date;
            var next = d.AddDays(1);
            // Slot giao ngày: bắt đầu trong ngày, hoặc kết thúc trong ngày, hoặc bao trùm cả ngày.
            q = q.Where(x =>
                (x.ReservedAt < next && (x.ReservedUntil ?? x.ReservedAt) >= d));
        }

        var list = await q.OrderBy(x => x.ReservedAt).ToListAsync();
        return Ok(AppResponse<List<ReservationDto>>.Success(list.Select(ToReservationDto).ToList()));
    }

    public record ReservationDayPipelineDto(
        string Date,
        int Booked,
        int Seated,
        int Cancelled,
        int NoShow,
        decimal DepositHeld,
        decimal DepositApplied,
        decimal DepositForfeited,
        decimal PreOrderValue,
        decimal ExpectedRevenue);

    /// <summary>
    /// Doanh thu tạm tính theo ngày đặt (VN). ExpectedRevenue = cọc held + giá món đặt trước (booked).
    /// </summary>
    [HttpGet("resource-reservations/pipeline")]
    [RequireModulePermission("PosBooking", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> ReservationPipeline(
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));

        await ExpireOverdueReservationsAsync(storeId);

        var fromD = VnCalendarDate((from ?? DateTime.UtcNow).ToUniversalTime());
        var toD = VnCalendarDate((to ?? fromD).ToUniversalTime());
        if (toD < fromD) (fromD, toD) = (toD, fromD);
        if ((toD - fromD).TotalDays > 62) toD = fromD.AddDays(62);

        var fromUtc = DateTime.SpecifyKind(fromD.AddHours(-7), DateTimeKind.Utc);
        var toUtc = DateTime.SpecifyKind(toD.AddDays(1).AddHours(-7), DateTimeKind.Utc);

        var rows = await db.PosResourceReservations.AsNoTracking()
            .Where(x => x.StoreId == storeId
                && x.ReservedAt < toUtc
                && (x.ReservedUntil ?? x.ReservedAt) >= fromUtc
                && (x.Deleted == null || x.Status != PosResourceReservationStatus.Booked))
            .Select(x => new
            {
                x.ReservedAt,
                x.Status,
                x.DepositPaid,
                x.DepositStatus,
                x.PreOrderJson,
            })
            .ToListAsync();

        var byDate = new Dictionary<string, ReservationDayPipelineDto>();
        for (var d = fromD; d <= toD; d = d.AddDays(1))
        {
            var key = d.ToString("yyyy-MM-dd");
            byDate[key] = new ReservationDayPipelineDto(key, 0, 0, 0, 0, 0, 0, 0, 0, 0);
        }

        foreach (var x in rows)
        {
            var key = VnCalendarDate(x.ReservedAt).ToString("yyyy-MM-dd");
            if (!byDate.TryGetValue(key, out var cur)) continue;
            var (_, preVal) = ParsePreOrder(x.PreOrderJson);
            var booked = x.Status == PosResourceReservationStatus.Booked;
            byDate[key] = cur with
            {
                Booked = cur.Booked + (booked ? 1 : 0),
                Seated = cur.Seated + (x.Status == PosResourceReservationStatus.Seated ? 1 : 0),
                Cancelled = cur.Cancelled + (x.Status == PosResourceReservationStatus.Cancelled ? 1 : 0),
                NoShow = cur.NoShow + (x.Status == PosResourceReservationStatus.NoShow ? 1 : 0),
                DepositHeld = cur.DepositHeld
                    + (x.DepositStatus == PosReservationDepositStatus.Held ? x.DepositPaid : 0),
                DepositApplied = cur.DepositApplied
                    + (x.DepositStatus == PosReservationDepositStatus.Applied ? x.DepositPaid : 0),
                DepositForfeited = cur.DepositForfeited
                    + (x.DepositStatus == PosReservationDepositStatus.Forfeited ? x.DepositPaid : 0),
                PreOrderValue = cur.PreOrderValue + (booked ? preVal : 0),
                ExpectedRevenue = cur.ExpectedRevenue
                    + (booked ? preVal + (x.DepositStatus == PosReservationDepositStatus.Held ? x.DepositPaid : 0) : 0),
            };
        }

        var days = byDate.Values.OrderBy(x => x.Date).ToList();
        return Ok(AppResponse<object>.Success(new
        {
            from = fromD.ToString("yyyy-MM-dd"),
            to = toD.ToString("yyyy-MM-dd"),
            days,
            totals = new ReservationDayPipelineDto(
                "total",
                days.Sum(x => x.Booked),
                days.Sum(x => x.Seated),
                days.Sum(x => x.Cancelled),
                days.Sum(x => x.NoShow),
                days.Sum(x => x.DepositHeld),
                days.Sum(x => x.DepositApplied),
                days.Sum(x => x.DepositForfeited),
                days.Sum(x => x.PreOrderValue),
                days.Sum(x => x.ExpectedRevenue)),
        }));
    }

    /// <summary>Lịch trống bàn/phòng theo ngày (đặt trước + phiên đang mở).</summary>
    [HttpGet("resource-reservations/availability")]
    [RequireModulePermission("PosBooking", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> ReservationAvailability(
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null,
        [FromQuery] string? kind = null)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));

        var fromD = VnCalendarDate((from ?? DateTime.UtcNow).ToUniversalTime());
        var toD = VnCalendarDate((to ?? fromD.AddDays(6)).ToUniversalTime());
        if (toD < fromD) (fromD, toD) = (toD, fromD);
        if ((toD - fromD).TotalDays > 31) toD = fromD.AddDays(31);

        PosResourceKind? kindFilter = null;
        if (!string.IsNullOrWhiteSpace(kind))
        {
            kindFilter = kind.Trim().ToLowerInvariant() switch
            {
                "chair" or "ghe" => PosResourceKind.Chair,
                "room" or "phong" => PosResourceKind.Room,
                "table" or "ban" => PosResourceKind.Table,
                _ => null,
            };
        }

        var resources = await db.PosServiceResources.AsNoTracking()
            .Include(r => r.Area)
            .Where(r => r.StoreId == storeId && r.Deleted == null && r.IsActive
                && (kindFilter == null || r.ResourceKind == kindFilter.Value))
            .OrderBy(r => r.SortOrder).ThenBy(r => r.Name)
            .ToListAsync();

        var fromUtc = DateTime.SpecifyKind(fromD.AddHours(-7), DateTimeKind.Utc);
        var toUtc = DateTime.SpecifyKind(toD.AddDays(1).AddHours(-7), DateTimeKind.Utc);
        var bookings = await db.PosResourceReservations.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null
                && x.Status == PosResourceReservationStatus.Booked
                && x.ReservedAt < toUtc
                && (x.ReservedUntil ?? x.ReservedAt) >= fromUtc)
            .Select(x => new { x.ResourceId, x.ReservedAt, x.ReservedUntil, x.DurationMinutes })
            .ToListAsync();

        var live = await db.PosResourceSessions.AsNoTracking()
            .Where(s => s.StoreId == storeId && s.Deleted == null
                && (s.Status == PosResourceSessionStatus.Open
                    || s.Status == PosResourceSessionStatus.Paused))
            .Select(s => s.ResourceId)
            .ToListAsync();
        var liveSet = live.ToHashSet();
        var todayVn = VnCalendarDate(DateTime.UtcNow);

        var days = new List<string>();
        for (var d = fromD; d <= toD; d = d.AddDays(1))
            days.Add(d.ToString("yyyy-MM-dd"));

        var items = resources.Select(r =>
        {
            var dayMap = days.Select(ds =>
            {
                var day = DateTime.Parse(ds);
                var dayStartUtc = DateTime.SpecifyKind(day.AddHours(-7), DateTimeKind.Utc);
                var dayEndUtc = dayStartUtc.AddDays(1);
                var booked = bookings.Any(b =>
                {
                    if (b.ResourceId != r.Id) return false;
                    var end = b.ReservedUntil ?? (b.DurationMinutes is > 0
                        ? b.ReservedAt.AddMinutes(b.DurationMinutes.Value)
                        : b.ReservedAt.AddHours(4));
                    return b.ReservedAt < dayEndUtc && end >= dayStartUtc;
                });
                var occupiedToday = liveSet.Contains(r.Id) && day == todayVn;
                var status = occupiedToday ? "Occupied" : booked ? "Booked" : "Free";
                return new { date = ds, status };
            }).ToList();
            return new
            {
                id = r.Id,
                name = r.Name,
                code = r.Code,
                areaName = r.Area?.Name,
                kind = r.ResourceKind.ToString(),
                days = dayMap,
            };
        }).ToList();

        return Ok(AppResponse<object>.Success(new { from = days.FirstOrDefault(), to = days.LastOrDefault(), days, items }));
    }

    [HttpPost("resource-reservations")]
    [RequireModulePermission("PosBooking", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> CreateReservation(
        [FromBody] CreateReservationDto dto)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        if (string.IsNullOrWhiteSpace(dto.CustomerName) && !dto.CustomerId.HasValue)
            return BadRequest(AppResponse<object>.Fail("Nhập tên khách đặt bàn"));

        await ExpireOverdueReservationsAsync(storeId);

        var resource = await db.PosServiceResources
            .FirstOrDefaultAsync(r => r.Id == dto.ResourceId && r.StoreId == storeId
                && r.Deleted == null && r.IsActive);
        if (resource == null)
            return BadRequest(AppResponse<object>.Fail("Bàn/phòng không hợp lệ"));

        var now = DateTime.UtcNow;
        int? duration = dto.DurationMinutes is > 0 ? dto.DurationMinutes : null;
        if (dto.StayNights is > 0)
            duration = dto.StayNights.Value * 24 * 60;
        PosProduct? serviceProduct = null;
        if (dto.ServiceProductId.HasValue)
        {
            serviceProduct = await db.PosProducts.AsNoTracking()
                .FirstOrDefaultAsync(p => p.Id == dto.ServiceProductId && p.StoreId == storeId
                    && p.Deleted == null && p.IsActive
                    && p.ProductType == PosProductType.Service);
            if (serviceProduct == null)
                return BadRequest(AppResponse<object>.Fail("Dịch vụ không hợp lệ"));
            duration ??= serviceProduct.DefaultDurationMinutes is > 0
                ? serviceProduct.DefaultDurationMinutes
                : 60;
        }

        var isTimed = duration is > 0;
        DateTime slotStart;
        DateTime? slotEnd;
        if (isTimed)
        {
            slotStart = ToUtc(dto.SlotStart ?? dto.ReservedUntil) ?? now;
            slotEnd = slotStart.AddMinutes(duration!.Value);
        }
        else
        {
            slotStart = now;
            slotEnd = ToUtc(dto.ReservedUntil);
        }

        if (dto.AssignedEmployeeId.HasValue)
        {
            var empOk = await db.Employees.AnyAsync(e =>
                e.Id == dto.AssignedEmployeeId && e.Deleted == null
                && e.WorkStatus != EmployeeWorkStatus.Resigned);
            if (!empOk)
                return BadRequest(AppResponse<object>.Fail("Nhân viên không hợp lệ"));
        }

        var live = await db.PosResourceSessions.AnyAsync(s =>
            s.ResourceId == dto.ResourceId
            && (s.Status == PosResourceSessionStatus.Open || s.Status == PosResourceSessionStatus.Paused)
            && s.Deleted == null);
        if (live && (!isTimed || (slotStart <= now && slotEnd > now)))
            return BadRequest(AppResponse<object>.Fail("Bàn đang mở — không đặt trước được"));

        var booked = await db.PosResourceReservations.AsNoTracking()
            .Where(x => x.ResourceId == dto.ResourceId && x.StoreId == storeId
                && x.Deleted == null && x.Status == PosResourceReservationStatus.Booked)
            .Select(x => new { x.ReservedAt, x.ReservedUntil, x.DurationMinutes })
            .ToListAsync();

        if (isTimed)
        {
            var overlap = booked.Any(x =>
            {
                var otherTimed = x.DurationMinutes is > 0;
                if (!otherTimed) return true; // classic hold chặn mọi slot
                var oStart = x.ReservedAt;
                var oEnd = x.ReservedUntil ?? oStart.AddMinutes(x.DurationMinutes ?? 60);
                return slotStart < oEnd && oStart < slotEnd!.Value;
            });
            if (overlap)
                return BadRequest(AppResponse<object>.Fail(
                    "Khung giờ trùng đặt trước khác trên bàn/ghế này"));
        }
        else if (booked.Count > 0)
        {
            return BadRequest(AppResponse<object>.Fail(
                "Bàn đã có đặt trước — hủy hoặc nhận bàn trước"));
        }

        if (isTimed && dto.AssignedEmployeeId.HasValue)
        {
            var empBooked = await db.PosResourceReservations.AsNoTracking()
                .Where(x => x.StoreId == storeId && x.Deleted == null
                    && x.Status == PosResourceReservationStatus.Booked
                    && x.AssignedEmployeeId == dto.AssignedEmployeeId
                    && x.DurationMinutes != null && x.DurationMinutes > 0)
                .Select(x => new { x.ReservedAt, x.ReservedUntil, x.DurationMinutes })
                .ToListAsync();
            var empOverlap = empBooked.Any(x =>
            {
                var oStart = x.ReservedAt;
                var oEnd = x.ReservedUntil ?? oStart.AddMinutes(x.DurationMinutes ?? 60);
                return slotStart < oEnd && oStart < slotEnd!.Value;
            });
            if (empOverlap)
                return BadRequest(AppResponse<object>.Fail(
                    "Nhân viên đã có lịch hẹn trùng khung giờ"));
        }

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
        else if (serviceProduct != null)
        {
            preJson = JsonSerializer.Serialize(new[]
            {
                new
                {
                    productId = serviceProduct.Id,
                    variantId = (Guid?)null,
                    name = serviceProduct.Name,
                    qty = 1m,
                    unitPrice = serviceProduct.BasePrice,
                    unitName = serviceProduct.BaseUnitName,
                    note = (string?)null,
                }
            });
        }

        var name = (dto.CustomerName ?? "").Trim();
        string? phone = string.IsNullOrWhiteSpace(dto.Phone) ? null : dto.Phone.Trim();
        if (dto.CustomerId.HasValue)
        {
            var cust = await db.PosCustomers.AsNoTracking()
                .FirstOrDefaultAsync(c => c.Id == dto.CustomerId && c.StoreId == storeId && c.Deleted == null);
            if (cust == null)
                return BadRequest(AppResponse<object>.Fail("Khách hàng không hợp lệ"));
            if (string.IsNullOrWhiteSpace(name)) name = cust.Name;
            phone ??= string.IsNullOrWhiteSpace(cust.Phone) ? null : cust.Phone.Trim();
        }
        if (string.IsNullOrWhiteSpace(name))
            return BadRequest(AppResponse<object>.Fail("Nhập tên khách đặt bàn"));

        var depositAmount = Math.Max(0, dto.DepositAmount);
        var depositPaid = Math.Max(0, dto.DepositPaid);
        if (depositPaid > 0 && depositAmount <= 0) depositAmount = depositPaid;
        var depositStatus = depositPaid > 0
            ? PosReservationDepositStatus.Held
            : PosReservationDepositStatus.None;

        var entity = new PosResourceReservation
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            ResourceId = resource.Id,
            CustomerId = dto.CustomerId,
            CustomerName = name,
            Phone = phone,
            GuestCount = dto.GuestCount < 1 ? 1 : dto.GuestCount,
            ReservedAt = slotStart,
            ReservedUntil = slotEnd,
            DurationMinutes = duration,
            ServiceProductId = serviceProduct?.Id,
            AssignedEmployeeId = dto.AssignedEmployeeId,
            Status = PosResourceReservationStatus.Booked,
            PreOrderJson = preJson,
            Note = string.IsNullOrWhiteSpace(dto.Note) ? null : dto.Note.Trim(),
            DepositAmount = depositAmount,
            DepositPaid = depositPaid,
            DepositStatus = depositStatus,
            DepositPaymentMethod = depositPaid > 0
                ? (string.IsNullOrWhiteSpace(dto.DepositPaymentMethod)
                    ? "Tiền mặt"
                    : dto.DepositPaymentMethod.Trim())
                : null,
            DepositPaidAt = depositPaid > 0 ? now : null,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
            CreatedAt = now,
        };
        db.PosResourceReservations.Add(entity);
        if (depositPaid > 0)
        {
            await PosFinanceSyncHelper.SyncReservationDepositCollectedAsync(
                db, entity, depositPaid, CurrentUserId);
        }
        await db.SaveChangesAsync();

        NotifyFloorChanged(storeId, "reservationCreate", resourceId: resource.Id);

        return Ok(AppResponse<object>.Success(new
        {
            id = entity.Id,
            resourceId = resource.Id,
            resourceName = resource.Name,
            customerName = entity.CustomerName,
            customerId = entity.CustomerId,
            guestCount = entity.GuestCount,
            preOrderCount = preJson == null ? 0 : 1,
            depositAmount = entity.DepositAmount,
            depositPaid = entity.DepositPaid,
            depositStatus = entity.DepositStatus.ToString(),
            durationMinutes = entity.DurationMinutes,
            slotStart = entity.ReservedAt,
            slotEnd = entity.ReservedUntil,
            isTimedSlot = entity.IsTimedSlot,
            serviceProductId = entity.ServiceProductId,
            assignedEmployeeId = entity.AssignedEmployeeId,
        }));
    }

    static DateTime? ToUtc(DateTime? value)
    {
        if (value == null) return null;
        var v = value.Value;
        return v.Kind switch
        {
            DateTimeKind.Utc => v,
            DateTimeKind.Local => v.ToUniversalTime(),
            _ => DateTime.SpecifyKind(v, DateTimeKind.Utc),
        };
    }

    [HttpPost("resource-reservations/{id:guid}/deposit")]
    [RequireModulePermission("PosBooking", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> CollectDeposit(
        Guid id, [FromBody] CollectDepositDto dto)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        if (dto.Amount <= 0)
            return BadRequest(AppResponse<object>.Fail("Số tiền cọc phải > 0"));

        var entity = await db.PosResourceReservations.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.Deleted == null
                && (x.StoreId == storeId || x.StoreId == Guid.Empty));
        if (entity == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy đặt bàn"));
        if (entity.Status != PosResourceReservationStatus.Booked)
            return BadRequest(AppResponse<object>.Fail("Đặt bàn không còn hiệu lực"));
        if (entity.DepositStatus is PosReservationDepositStatus.Applied
            or PosReservationDepositStatus.Refunded
            or PosReservationDepositStatus.Forfeited)
            return BadRequest(AppResponse<object>.Fail("Cọc đã xử lý — không thu thêm"));

        if (entity.StoreId == Guid.Empty) entity.StoreId = storeId;
        var now = DateTime.UtcNow;
        entity.DepositPaid += dto.Amount;
        if (entity.DepositAmount < entity.DepositPaid)
            entity.DepositAmount = entity.DepositPaid;
        entity.DepositStatus = PosReservationDepositStatus.Held;
        entity.DepositPaymentMethod = string.IsNullOrWhiteSpace(dto.PaymentMethod)
            ? (entity.DepositPaymentMethod ?? "Tiền mặt")
            : dto.PaymentMethod.Trim();
        entity.DepositPaidAt = now;
        entity.UpdatedAt = now;
        entity.UpdatedBy = CurrentUserEmail;
        await PosFinanceSyncHelper.SyncReservationDepositCollectedAsync(
            db, entity, dto.Amount, CurrentUserId);
        await db.SaveChangesAsync();

        NotifyFloorChanged(storeId, "reservationDeposit", resourceId: entity.ResourceId);

        return Ok(AppResponse<object>.Success(new
        {
            id = entity.Id,
            depositPaid = entity.DepositPaid,
            depositAmount = entity.DepositAmount,
            depositStatus = entity.DepositStatus.ToString(),
        }));
    }

    [HttpPost("resource-reservations/{id:guid}/cancel")]
    [RequireModulePermission("PosBooking", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> CancelReservation(
        Guid id, [FromBody] CancelReservationDto? dto = null)
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

        if (entity.DepositStatus == PosReservationDepositStatus.Held && entity.DepositPaid > 0)
        {
            if (dto?.RefundDeposit == true)
            {
                entity.DepositStatus = PosReservationDepositStatus.Refunded;
                await PosFinanceSyncHelper.SyncReservationDepositRefundAsync(
                    db, entity, CurrentUserId);
            }
            else if (dto?.ForfeitDeposit == true || dto == null)
                entity.DepositStatus = PosReservationDepositStatus.Forfeited;
            else
                entity.DepositStatus = PosReservationDepositStatus.Forfeited;
        }

        entity.Deleted = now;
        entity.DeletedBy = CurrentUserEmail;
        entity.UpdatedAt = now;
        entity.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync();

        NotifyFloorChanged(storeId, "reservationCancel", resourceId: entity.ResourceId);
        return Ok(AppResponse<object>.Success(new
        {
            cancelled = true,
            id = entity.Id,
            depositStatus = entity.DepositStatus.ToString(),
            depositPaid = entity.DepositPaid,
        }));
    }

    [HttpPost("resource-reservations/expire-noshow")]
    [RequireModulePermission("PosBooking", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> ExpireNoShows()
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        var n = await ExpireOverdueReservationsAsync(storeId);
        return Ok(AppResponse<object>.Success(new { expired = n }));
    }

    /// <summary>Khách đến — mở phiên, gắn món đặt trước + trừ cọc vào đơn Draft.</summary>
    [HttpPost("resource-reservations/{id:guid}/seat")]
    [RequireModulePermission("PosBooking", ModulePermissionAction.Create)]
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

            var depositNote = booking.DepositStatus == PosReservationDepositStatus.Held
                && booking.DepositPaid > 0
                ? $"Cọc đã thu: {booking.DepositPaid.ToString("#,0", System.Globalization.CultureInfo.GetCultureInfo("vi-VN"))}đ"
                : null;
            var noteParts = new[] { booking.Note, depositNote }
                .Where(s => !string.IsNullOrWhiteSpace(s));
            var orderNote = string.Join(" · ", noteParts);

            var order = new PosSaleOrder
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                OrderNo = orderNo,
                InvoiceSlot = invoiceSlot,
                Status = PosSaleOrderStatus.Draft,
                PaymentMethod = booking.DepositPaymentMethod ?? "Tiền mặt",
                CustomerId = booking.CustomerId,
                CustomerName = string.IsNullOrWhiteSpace(booking.CustomerName)
                    ? "Bán cho người tiêu dùng"
                    : booking.CustomerName,
                ServiceResourceId = resource.Id,
                ServiceStartedAt = now,
                SaleDate = now,
                SalesChannel = "Tại chỗ",
                Note = string.IsNullOrWhiteSpace(orderNote) ? null : orderNote,
                PaidAmount = booking.DepositStatus == PosReservationDepositStatus.Held
                    ? Math.Max(0, booking.DepositPaid)
                    : 0,
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

            var preCount = await ApplyPreOrderLinesAsync(
                storeId, order, booking.PreOrderJson, now,
                assignedEmployeeId: booking.AssignedEmployeeId,
                durationMinutes: booking.DurationMinutes);

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

            // Salon timed: đã có SP dịch vụ từ lịch — không auto-add SP giờ.
            if (!booking.IsTimedSlot)
                await TryAutoAddHourlyLineAsync(storeId, resource, order, now);

            booking.Status = PosResourceReservationStatus.Seated;
            booking.SeatedSessionId = session.Id;
            if (booking.DepositStatus == PosReservationDepositStatus.Held && booking.DepositPaid > 0)
            {
                booking.DepositStatus = PosReservationDepositStatus.Applied;
                booking.DepositAppliedOrderId = order.Id;
            }
            booking.UpdatedAt = now;
            booking.UpdatedBy = CurrentUserEmail;

            resource.NeedsCleaning = false;
            resource.UpdatedAt = now;

            await db.SaveChangesAsync();

            NotifyFloorChanged(storeId, "reservationSeat",
                orderId: order.Id, resourceId: resource.Id, sessionId: session.Id);

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
                customerId = order.CustomerId,
                preOrderLines = preCount,
                reservationId = booking.Id,
                paidAmount = order.PaidAmount,
                depositApplied = booking.DepositStatus == PosReservationDepositStatus.Applied
                    ? booking.DepositPaid
                    : 0m,
                defaultHourlyRate = resource.DefaultHourlyRate,
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

    /// <summary>Đánh NoShow các Booked quá ReservedUntil + grace; cọc Held → Forfeited.</summary>
    async Task<int> ExpireOverdueReservationsAsync(Guid storeId)
    {
        var cutoff = DateTime.UtcNow.AddMinutes(-ReservationNoShowGraceMinutes);
        var overdue = await db.PosResourceReservations.AsTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null
                && x.Status == PosResourceReservationStatus.Booked
                && x.ReservedUntil != null
                && x.ReservedUntil < cutoff)
            .ToListAsync();
        if (overdue.Count == 0) return 0;

        var now = DateTime.UtcNow;
        foreach (var x in overdue)
        {
            x.Status = PosResourceReservationStatus.NoShow;
            if (x.DepositStatus == PosReservationDepositStatus.Held && x.DepositPaid > 0)
                x.DepositStatus = PosReservationDepositStatus.Forfeited;
            x.UpdatedAt = now;
            x.UpdatedBy = CurrentUserEmail ?? "system";
            x.IsActive = false;
        }
        await db.SaveChangesAsync();
        if (overdue.Count > 0)
            NotifyFloorChanged(storeId, "reservationNoShow");
        return overdue.Count;
    }

    async Task<int> ApplyPreOrderLinesAsync(
        Guid storeId, PosSaleOrder order, string? preOrderJson, DateTime now,
        Guid? assignedEmployeeId = null, int? durationMinutes = null)
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
            var isService = p.ProductType == PosProductType.Service;
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
                DurationMinutes = isService ? durationMinutes : null,
                AssignedEmployeeId = isService ? assignedEmployeeId : null,
                ServiceStartedAt = isService ? now : null,
                IsActive = true,
                CreatedBy = CurrentUserEmail,
                CreatedAt = now,
            });
            added++;
        }

        order.SubTotal += subTotal;
        order.Total = Math.Max(0, order.SubTotal - order.Discount);
        return added;
    }

    static ReservationDto ToReservationDto(PosResourceReservation x)
    {
        var (preCount, preValue) = ParsePreOrder(x.PreOrderJson);

        string? empName = null;
        if (x.AssignedEmployee != null)
        {
            empName = $"{x.AssignedEmployee.LastName} {x.AssignedEmployee.FirstName}".Trim();
            if (string.IsNullOrWhiteSpace(empName))
                empName = x.AssignedEmployee.EmployeeCode;
        }

        return new ReservationDto(
            x.Id,
            x.ResourceId,
            x.Resource?.Code ?? "",
            x.Resource?.Name ?? "",
            x.Resource?.Area?.Name,
            x.CustomerName,
            x.Phone,
            x.CustomerId,
            x.GuestCount,
            x.ReservedAt,
            x.ReservedUntil,
            x.Status.ToString(),
            x.Note,
            preCount,
            x.PreOrderJson,
            x.DepositAmount,
            x.DepositPaid,
            x.DepositStatus.ToString(),
            x.DepositPaymentMethod,
            x.DepositPaidAt,
            x.DurationMinutes,
            x.ServiceProductId,
            x.ServiceProduct?.Name,
            x.AssignedEmployeeId,
            empName,
            x.IsTimedSlot,
            preValue,
            x.Resource?.ResourceKind.ToString());
    }

    static (int Count, decimal Value) ParsePreOrder(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return (0, 0);
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.ValueKind != JsonValueKind.Array)
                return (0, 0);
            decimal value = 0;
            var n = 0;
            foreach (var el in doc.RootElement.EnumerateArray())
            {
                n++;
                var qty = el.TryGetProperty("qty", out var q) ? q.GetDecimal()
                    : el.TryGetProperty("Qty", out var q2) ? q2.GetDecimal() : 1m;
                var price = el.TryGetProperty("unitPrice", out var p) ? p.GetDecimal()
                    : el.TryGetProperty("UnitPrice", out var p2) ? p2.GetDecimal() : 0m;
                value += qty * price;
            }
            return (n, value);
        }
        catch
        {
            return (0, 0);
        }
    }

    static DateTime VnCalendarDate(DateTime utc)
    {
        var u = utc.Kind == DateTimeKind.Utc ? utc : DateTime.SpecifyKind(utc, DateTimeKind.Utc);
        return u.AddHours(7).Date;
    }

    /// <summary>
    /// Chọn booking hiển thị trên sơ đồ: slot đang diễn ra → slot sắp tới → classic.
    /// </summary>
    internal static PosResourceReservation? PickFloorBooking(
        IEnumerable<PosResourceReservation> bookings, DateTime nowUtc)
    {
        var list = bookings.ToList();
        if (list.Count == 0) return null;

        var timed = list.Where(b => b.DurationMinutes is > 0).ToList();
        var classic = list.Where(b => b.DurationMinutes is null or <= 0).ToList();

        var current = timed
            .Where(b =>
            {
                var end = b.ReservedUntil ?? b.ReservedAt.AddMinutes(b.DurationMinutes ?? 60);
                return b.ReservedAt <= nowUtc && nowUtc < end;
            })
            .OrderBy(b => b.ReservedAt)
            .FirstOrDefault();
        if (current != null) return current;

        var upcoming = timed
            .Where(b => b.ReservedAt > nowUtc)
            .OrderBy(b => b.ReservedAt)
            .FirstOrDefault();
        if (upcoming != null) return upcoming;

        return classic.OrderByDescending(b => b.ReservedAt).FirstOrDefault()
            ?? timed.OrderByDescending(b => b.ReservedAt).FirstOrDefault();
    }

    /// <summary>
    /// Heal/open bàn chỉ chạm classic hoặc timed đang chồng phiên — không hủy lịch tương lai.
    /// </summary>
    internal static bool ReservationConflictsWithLiveSession(
        PosResourceReservation b, DateTime sessionStartedAt, DateTime? nowUtc = null)
    {
        var now = nowUtc ?? DateTime.UtcNow;
        if (b.DurationMinutes is null or <= 0)
            return sessionStartedAt >= b.ReservedAt.AddMinutes(-1);

        var end = b.ReservedUntil ?? b.ReservedAt.AddMinutes(b.DurationMinutes.Value);
        // Phiên mở trong khung slot, hoặc slot đang/đã bắt đầu và phiên sau lúc bắt đầu slot.
        return sessionStartedAt < end
            && sessionStartedAt >= b.ReservedAt.AddMinutes(-1)
            && (now >= b.ReservedAt.AddMinutes(-30) || sessionStartedAt >= b.ReservedAt.AddMinutes(-1));
    }
}
