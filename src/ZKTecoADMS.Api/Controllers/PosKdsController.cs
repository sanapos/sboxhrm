using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Hubs;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>KDS — màn hình bếp: ticket theo bàn, trạng thái chế biến, bump.</summary>
[ApiController]
[Route("api/pos/kds")]
[Authorize]
public class PosKdsController(
    ZKTecoDbContext db,
    IHubContext<AttendanceHub> hub) : AuthenticatedControllerBase
{
    public class PrepDto
    {
        public string? Status { get; set; }
    }

    public class PrepBatchDto
    {
        public List<Guid>? Ids { get; set; }
        public string? Status { get; set; }
    }

    [HttpGet("stations")]
    [RequireModulePermission("PosKds", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Stations()
    {
        var storeId = RequiredStoreId;
        var kitchenTypes = new[] { PosPrintDocumentType.KitchenSlip, PosPrintDocumentType.KitchenLabel };
        var printerIds = await db.PosPrinterDocumentRoutes.AsNoTracking()
            .Where(r => r.StoreId == storeId && r.Deleted == null && kitchenTypes.Contains(r.DocumentType))
            .Select(r => r.PrinterId)
            .Distinct()
            .ToListAsync();
        var printers = await db.PosStorePrinters.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.IsActive
                && (printerIds.Count == 0 || printerIds.Contains(p.Id)))
            .OrderBy(p => p.SortOrder).ThenBy(p => p.Name)
            .Select(p => new { p.Id, p.Name, p.IsDeviceLocal, p.SortOrder })
            .ToListAsync();
        if (printers.Count == 0)
        {
            printers = await db.PosStorePrinters.AsNoTracking()
                .Where(p => p.StoreId == storeId && p.Deleted == null && p.IsActive)
                .OrderBy(p => p.SortOrder).ThenBy(p => p.Name)
                .Select(p => new { p.Id, p.Name, p.IsDeviceLocal, p.SortOrder })
                .ToListAsync();
        }
        // Cloud + deviceLocal cùng tên (USB/WiFi) — 1 chip trạm bếp.
        var stations = printers
            .GroupBy(p => (p.Name ?? "").Trim(), StringComparer.OrdinalIgnoreCase)
            .Where(g => !string.IsNullOrWhiteSpace(g.Key))
            .Select(g =>
            {
                var primary = g.OrderBy(x => x.IsDeviceLocal).ThenBy(x => x.SortOrder).First();
                return new
                {
                    id = primary.Id,
                    name = primary.Name,
                    printerIds = g.Select(x => x.Id).ToList(),
                };
            })
            .OrderBy(s => s.name)
            .ToList();
        return Ok(AppResponse<object>.Success(new { stations }));
    }

    [HttpGet("tickets")]
    [RequireModulePermission("PosKds", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Tickets(
        [FromQuery] Guid? printerId = null,
        [FromQuery] bool includeDone = false)
    {
        var storeId = RequiredStoreId;
        var since = DateTime.UtcNow.AddHours(-12);
        var rows = await (
            from line in db.PosSaleOrderLines.AsNoTracking()
            join order in db.PosSaleOrders.AsNoTracking() on line.SaleOrderId equals order.Id
            join product in db.PosProducts.AsNoTracking() on line.ProductId equals product.Id
            join cat in db.PosProductCategories.AsNoTracking() on product.CategoryId equals cat.Id into cats
            from cat in cats.DefaultIfEmpty()
            where line.StoreId == storeId && line.Deleted == null && order.Deleted == null
                && line.KitchenSentQty > 0
                && (includeDone || line.KitchenSentQty > line.KitchenDoneQty)
                && (order.Status == PosSaleOrderStatus.Draft
                    || (order.Status == PosSaleOrderStatus.Completed && (order.SaleDate ?? order.CreatedAt) >= since)
                    || (includeDone && (order.SaleDate ?? order.CreatedAt) >= since))
            select new
            {
                line.Id,
                line.SaleOrderId,
                line.ProductId,
                line.ProductName,
                line.Qty,
                line.UnitName,
                line.LineNote,
                line.ToppingsJson,
                line.KitchenSentQty,
                line.KitchenSentAt,
                line.KitchenDoneQty,
                line.KitchenPrepStatus,
                order.OrderNo,
                order.Status,
                order.SalesChannel,
                order.ServiceResourceId,
                order.CustomerName,
                PrinterId = product.DefaultPrinterId ?? cat.DefaultPrinterId,
            }).ToListAsync();

        if (printerId.HasValue && printerId != Guid.Empty)
        {
            var selectedName = await db.PosStorePrinters.AsNoTracking()
                .Where(p => p.Id == printerId && p.StoreId == storeId)
                .Select(p => p.Name)
                .FirstOrDefaultAsync();
            var siblingIds = string.IsNullOrWhiteSpace(selectedName)
                ? new List<Guid> { printerId.Value }
                : await db.PosStorePrinters.AsNoTracking()
                    .Where(p => p.StoreId == storeId && p.Deleted == null
                        && p.Name == selectedName)
                    .Select(p => p.Id)
                    .ToListAsync();
            rows = rows.Where(r => r.PrinterId != null && siblingIds.Contains(r.PrinterId.Value)).ToList();
        }

        var resourceIds = rows.Where(r => r.ServiceResourceId != null)
            .Select(r => r.ServiceResourceId!.Value).Distinct().ToList();
        var resources = resourceIds.Count == 0
            ? new Dictionary<Guid, (string Name, string? Area)>()
            : await db.PosServiceResources.AsNoTracking()
                .Include(r => r.Area)
                .Where(r => resourceIds.Contains(r.Id))
                .ToDictionaryAsync(r => r.Id, r => (Name: r.Name, Area: r.Area != null ? r.Area.Name : (string?)null));

        var tickets = new List<object>();
        foreach (var g in rows.GroupBy(r => r.SaleOrderId).OrderBy(g => g.Min(x => x.KitchenSentAt)))
        {
            var first = g.First();
            string? tableName = null;
            string? areaName = null;
            if (first.ServiceResourceId is Guid rid && resources.TryGetValue(rid, out var res))
            {
                tableName = res.Name;
                areaName = res.Area;
            }
            var items = g.Select(r =>
            {
                var open = Math.Max(0, r.KitchenSentQty - r.KitchenDoneQty);
                var status = PosKitchenKdsHelper.Normalize(r.KitchenPrepStatus);
                if (open <= 0) status = PosKitchenKdsHelper.Done;
                else if (status is PosKitchenKdsHelper.None or PosKitchenKdsHelper.Done)
                    status = PosKitchenKdsHelper.Queued;
                return new
                {
                    id = r.Id,
                    productName = r.ProductName,
                    qty = open > 0 ? open : r.KitchenSentQty,
                    sentQty = r.KitchenSentQty,
                    doneQty = r.KitchenDoneQty,
                    unitName = r.UnitName,
                    note = KitchenNote(r.ToppingsJson, r.LineNote),
                    status,
                    sentAt = UtcIso(r.KitchenSentAt),
                    printerId = r.PrinterId,
                };
            }).OrderBy(x => x.sentAt).ThenBy(x => x.productName).ToList();
            var openItems = items.Where(i => i.status != PosKitchenKdsHelper.Done).ToList();
            var show = includeDone ? items : openItems;
            if (show.Count == 0) continue;
            var sentAt = show
                .Select(i => i.sentAt)
                .Where(s => !string.IsNullOrEmpty(s))
                .OrderBy(s => s)
                .FirstOrDefault() ?? UtcIso(DateTime.UtcNow);
            var ticketStatus = PosKitchenKdsHelper.MergeStatus(
                show.Select(i => i.status), openItems.Count > 0);
            tickets.Add(new
            {
                orderId = g.Key,
                orderNo = first.OrderNo,
                tableName,
                areaName,
                channel = first.SalesChannel,
                customerName = first.CustomerName,
                resourceId = first.ServiceResourceId,
                sentAt,
                status = ticketStatus,
                items = show,
            });
        }

        return Ok(AppResponse<object>.Success(new { tickets, at = UtcIso(DateTime.UtcNow) }));
    }

    [HttpPost("lines/prep-batch")]
    [RequireModulePermission("PosKds", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> PrepBatch([FromBody] PrepBatchDto? dto)
    {
        var storeId = RequiredStoreId;
        var status = PosKitchenKdsHelper.Normalize(dto?.Status);
        if (status is not (PosKitchenKdsHelper.Queued or PosKitchenKdsHelper.Cooking
            or PosKitchenKdsHelper.Ready or PosKitchenKdsHelper.Done))
            return BadRequest(AppResponse<object>.Fail("Trạng thái không hợp lệ"));
        var ids = (dto?.Ids ?? [])
            .Where(x => x != Guid.Empty)
            .Distinct()
            .Take(400)
            .ToList();
        if (ids.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Chưa chọn món"));

        var lines = await db.PosSaleOrderLines.AsTracking()
            .Where(l => l.StoreId == storeId && l.Deleted == null && ids.Contains(l.Id))
            .ToListAsync();
        if (lines.Count == 0)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy món"));

        foreach (var line in lines)
        {
            if (line.KitchenSentQty <= 0) continue;
            PosKitchenKdsHelper.ApplyStatus(line, status);
            line.UpdatedAt = DateTime.UtcNow;
            line.UpdatedBy = CurrentUserEmail;
        }
        await db.SaveChangesAsync();
        PosFloorRealtimeHelper.Notify(hub, storeId, "kds");
        return Ok(AppResponse<object>.Success(new { updated = lines.Count, status }));
    }

    [HttpPost("lines/{id:guid}/prep")]
    [RequireModulePermission("PosKds", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> PrepLine(Guid id, [FromBody] PrepDto? dto)
    {
        var storeId = RequiredStoreId;
        var status = PosKitchenKdsHelper.Normalize(dto?.Status);
        if (status is not (PosKitchenKdsHelper.Queued or PosKitchenKdsHelper.Cooking
            or PosKitchenKdsHelper.Ready or PosKitchenKdsHelper.Done))
            return BadRequest(AppResponse<object>.Fail("Trạng thái không hợp lệ"));

        var line = await db.PosSaleOrderLines.AsTracking()
            .FirstOrDefaultAsync(l => l.Id == id && l.StoreId == storeId && l.Deleted == null);
        if (line == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy món"));
        if (line.KitchenSentQty <= 0)
            return BadRequest(AppResponse<object>.Fail("Món chưa báo bếp"));

        PosKitchenKdsHelper.ApplyStatus(line, status);
        line.UpdatedAt = DateTime.UtcNow;
        line.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync();
        PosFloorRealtimeHelper.Notify(hub, storeId, "kds", orderId: line.SaleOrderId);
        return Ok(AppResponse<object>.Success(new
        {
            id = line.Id,
            status = line.KitchenPrepStatus,
            doneQty = line.KitchenDoneQty,
            sentQty = line.KitchenSentQty,
        }));
    }

    [HttpPost("tickets/{orderId:guid}/bump")]
    [RequireModulePermission("PosKds", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> Bump(Guid orderId)
    {
        var storeId = RequiredStoreId;
        var lines = await db.PosSaleOrderLines.AsTracking()
            .Where(l => l.SaleOrderId == orderId && l.StoreId == storeId && l.Deleted == null
                && l.KitchenSentQty > l.KitchenDoneQty)
            .ToListAsync();
        if (lines.Count == 0)
            return Ok(AppResponse<object>.Success(new { bumped = 0 }));
        foreach (var line in lines)
        {
            PosKitchenKdsHelper.Bump(line);
            line.UpdatedAt = DateTime.UtcNow;
            line.UpdatedBy = CurrentUserEmail;
        }
        await db.SaveChangesAsync();
        PosFloorRealtimeHelper.Notify(hub, storeId, "kds", orderId: orderId);
        return Ok(AppResponse<object>.Success(new { bumped = lines.Count }));
    }

    [HttpPost("tickets/{orderId:guid}/recall")]
    [RequireModulePermission("PosKds", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> Recall(Guid orderId)
    {
        var storeId = RequiredStoreId;
        var since = DateTime.UtcNow.AddMinutes(-45);
        var lines = await db.PosSaleOrderLines.AsTracking()
            .Where(l => l.SaleOrderId == orderId && l.StoreId == storeId && l.Deleted == null
                && l.KitchenSentQty > 0
                && (l.KitchenPrepStatus == PosKitchenKdsHelper.Done || l.KitchenDoneQty >= l.KitchenSentQty)
                && (l.UpdatedAt ?? l.KitchenSentAt ?? l.CreatedAt) >= since)
            .ToListAsync();
        if (lines.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Không có món để gọi lại"));
        foreach (var line in lines)
        {
            PosKitchenKdsHelper.Recall(line);
            line.UpdatedAt = DateTime.UtcNow;
            line.UpdatedBy = CurrentUserEmail;
        }
        await db.SaveChangesAsync();
        PosFloorRealtimeHelper.Notify(hub, storeId, "kds", orderId: orderId);
        return Ok(AppResponse<object>.Success(new { recalled = lines.Count }));
    }

    /// KitchenSentAt lưu UTC trên cột timestamp without time zone — trả ISO có Z để client không +7 giờ.
    static string? UtcIso(DateTime? value)
    {
        if (value == null) return null;
        var utc = DateTime.SpecifyKind(value.Value, DateTimeKind.Utc);
        return utc.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'");
    }

    static string? KitchenNote(string? toppingsJson, string? lineNote) =>
        PosSaleStockHelper.FormatToppingKitchenNote(toppingsJson, lineNote);
}
