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

    public class AckVoidsDto
    {
        public List<Guid>? Ids { get; set; }
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

        List<Guid>? siblingIds = null;
        if (printerId.HasValue && printerId != Guid.Empty)
        {
            var selectedName = await db.PosStorePrinters.AsNoTracking()
                .Where(p => p.Id == printerId && p.StoreId == storeId)
                .Select(p => p.Name)
                .FirstOrDefaultAsync();
            siblingIds = string.IsNullOrWhiteSpace(selectedName)
                ? new List<Guid> { printerId.Value }
                : await db.PosStorePrinters.AsNoTracking()
                    .Where(p => p.StoreId == storeId && p.Deleted == null
                        && p.Name == selectedName)
                    .Select(p => p.Id)
                    .ToListAsync();
            rows = rows.Where(r => r.PrinterId != null && siblingIds.Contains(r.PrinterId.Value)).ToList();
        }

        var draftOrderIds = await db.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null
                && o.Status == PosSaleOrderStatus.Draft)
            .Select(o => o.Id)
            .ToListAsync();
        var draftSet = draftOrderIds.ToHashSet();
        var liveOrderIds = rows.Select(r => r.SaleOrderId).ToHashSet();

        var voidRaw = await db.PosKitchenVoidSlips.AsNoTracking()
            .Where(v => v.StoreId == storeId && v.Deleted == null
                && v.VoidedAt >= since && v.KdsAckedAt == null)
            .Select(v => new
            {
                v.Id,
                v.SaleOrderId,
                v.OrderNo,
                v.ServiceResourceId,
                v.ResourceName,
                v.ProductId,
                v.ProductName,
                v.Qty,
                v.UnitName,
                v.LineNote,
                v.Reason,
                v.VoidedAt,
            })
            .ToListAsync();

        var voidOrderIds = voidRaw.Where(v => v.SaleOrderId != null)
            .Select(v => v.SaleOrderId!.Value).Distinct().ToList();
        var voidOrders = voidOrderIds.Count == 0
            ? new Dictionary<Guid, (PosSaleOrderStatus Status, string? Channel, string? Customer, Guid? ResourceId)>()
            : await db.PosSaleOrders.AsNoTracking()
                .Where(o => voidOrderIds.Contains(o.Id))
                .ToDictionaryAsync(o => o.Id, o => (
                    Status: o.Status,
                    Channel: o.SalesChannel,
                    Customer: o.CustomerName,
                    ResourceId: o.ServiceResourceId));

        var voidProductIds = voidRaw.Where(v => v.ProductId != null)
            .Select(v => v.ProductId!.Value).Distinct().ToList();
        var voidPrinterByProduct = new Dictionary<Guid, Guid?>();
        if (voidProductIds.Count > 0)
        {
            var prodRows = await (
                from p in db.PosProducts.AsNoTracking()
                join cat in db.PosProductCategories.AsNoTracking() on p.CategoryId equals cat.Id into cats
                from cat in cats.DefaultIfEmpty()
                where voidProductIds.Contains(p.Id)
                select new { p.Id, PrinterId = p.DefaultPrinterId ?? cat.DefaultPrinterId }
            ).ToListAsync();
            foreach (var p in prodRows)
                voidPrinterByProduct[p.Id] = p.PrinterId;
        }

        var voidRows = voidRaw.Select(v =>
        {
            voidOrders.TryGetValue(v.SaleOrderId ?? Guid.Empty, out var ord);
            Guid? printerId = null;
            if (v.ProductId is Guid pid)
                voidPrinterByProduct.TryGetValue(pid, out printerId);
            return new
            {
                v.Id,
                v.SaleOrderId,
                v.OrderNo,
                v.ServiceResourceId,
                v.ResourceName,
                v.ProductId,
                v.ProductName,
                v.Qty,
                v.UnitName,
                v.LineNote,
                v.Reason,
                v.VoidedAt,
                OrderStatus = v.SaleOrderId == null ? (PosSaleOrderStatus?)null : ord.Status,
                SalesChannel = ord.Channel,
                CustomerName = ord.Customer,
                OrderResourceId = ord.ResourceId,
                PrinterId = printerId,
            };
        }).Where(v =>
            (v.SaleOrderId is Guid oid && (draftSet.Contains(oid) || liveOrderIds.Contains(oid)))
            || v.SaleOrderId == null).ToList();
        if (siblingIds != null)
        {
            voidRows = voidRows.Where(v =>
                v.PrinterId == null || siblingIds.Contains(v.PrinterId.Value)).ToList();
        }

        var resourceIds = rows.Where(r => r.ServiceResourceId != null)
            .Select(r => r.ServiceResourceId!.Value)
            .Concat(voidRows.Where(v => v.ServiceResourceId != null).Select(v => v.ServiceResourceId!.Value))
            .Concat(voidRows.Where(v => v.OrderResourceId != null).Select(v => v.OrderResourceId!.Value))
            .Distinct()
            .ToList();
        var resources = resourceIds.Count == 0
            ? new Dictionary<Guid, (string Name, string? Area)>()
            : await db.PosServiceResources.AsNoTracking()
                .Include(r => r.Area)
                .Where(r => resourceIds.Contains(r.Id))
                .ToDictionaryAsync(r => r.Id, r => (Name: r.Name, Area: r.Area != null ? r.Area.Name : (string?)null));

        var acc = new Dictionary<Guid, KdsTicketAcc>();
        foreach (var g in rows.GroupBy(r => r.SaleOrderId))
        {
            var first = g.First();
            string? tableName = null;
            string? areaName = null;
            if (first.ServiceResourceId is Guid rid && resources.TryGetValue(rid, out var res))
            {
                tableName = res.Name;
                areaName = res.Area;
            }
            var t = new KdsTicketAcc
            {
                OrderId = g.Key,
                OrderNo = first.OrderNo,
                TableName = tableName,
                AreaName = areaName,
                Channel = first.SalesChannel,
                CustomerName = first.CustomerName,
                ResourceId = first.ServiceResourceId,
            };
            foreach (var r in g)
            {
                var open = Math.Max(0, r.KitchenSentQty - r.KitchenDoneQty);
                var status = PosKitchenKdsHelper.Normalize(r.KitchenPrepStatus);
                if (open <= 0) status = PosKitchenKdsHelper.Done;
                else if (status is PosKitchenKdsHelper.None or PosKitchenKdsHelper.Done)
                    status = PosKitchenKdsHelper.Queued;
                if (!includeDone && status == PosKitchenKdsHelper.Done) continue;
                t.Items.Add(new KdsItemAcc
                {
                    Id = r.Id,
                    ProductId = r.ProductId,
                    ProductName = r.ProductName,
                    Qty = open > 0 ? open : r.KitchenSentQty,
                    SentQty = r.KitchenSentQty,
                    DoneQty = r.KitchenDoneQty,
                    UnitName = r.UnitName,
                    Note = KitchenNote(r.ToppingsJson, r.LineNote),
                    Status = status,
                    SentAt = UtcIso(r.KitchenSentAt),
                    PrinterId = r.PrinterId,
                    SortAt = r.KitchenSentAt,
                });
            }
            acc[g.Key] = t;
        }

        foreach (var v in voidRows)
        {
            var key = v.SaleOrderId ?? v.Id;
            if (!acc.TryGetValue(key, out var t))
            {
                Guid? rid = v.ServiceResourceId ?? v.OrderResourceId;
                string? tableName = string.IsNullOrWhiteSpace(v.ResourceName) ? null : v.ResourceName.Trim();
                string? areaName = null;
                if (rid is Guid id && resources.TryGetValue(id, out var res))
                {
                    tableName ??= res.Name;
                    areaName = res.Area;
                }
                t = new KdsTicketAcc
                {
                    OrderId = key,
                    OrderNo = v.OrderNo,
                    TableName = tableName,
                    AreaName = areaName,
                    Channel = v.SalesChannel,
                    CustomerName = v.CustomerName,
                    ResourceId = rid,
                };
                acc[key] = t;
            }
            var reason = (v.Reason ?? "").Trim();
            var lineNote = (v.LineNote ?? "").Trim();
            var noteParts = new List<string>();
            if (lineNote.Length > 0) noteParts.Add(lineNote);
            if (reason.Length > 0) noteParts.Add($"Lý do: {reason}");
            var note = noteParts.Count == 0 ? "Hủy" : string.Join(" — ", noteParts);
            t.Items.Add(new KdsItemAcc
            {
                Id = v.Id,
                ProductId = v.ProductId,
                ProductName = v.ProductName,
                Qty = v.Qty,
                SentQty = v.Qty,
                DoneQty = 0,
                UnitName = v.UnitName,
                Note = note,
                Status = PosKitchenKdsHelper.Voided,
                SentAt = UtcIso(v.VoidedAt),
                PrinterId = v.PrinterId,
                SortAt = v.VoidedAt,
            });
        }

        var tickets = new List<object>();
        foreach (var t in acc.Values
            .Where(x => x.Items.Count > 0)
            .OrderBy(x => x.Items.Min(i => i.SortAt ?? DateTime.MaxValue)))
        {
            var show = t.Items
                .OrderBy(i => i.Status == PosKitchenKdsHelper.Voided)
                .ThenBy(i => i.SortAt)
                .ThenBy(i => i.ProductName)
                .Select(i => new
                {
                    id = i.Id,
                    productId = i.ProductId,
                    productName = i.ProductName,
                    qty = i.Qty,
                    sentQty = i.SentQty,
                    doneQty = i.DoneQty,
                    unitName = i.UnitName,
                    note = i.Note,
                    status = i.Status,
                    sentAt = i.SentAt,
                    printerId = i.PrinterId,
                })
                .ToList();
            var openLive = t.Items.Count(i =>
                i.Status is not (PosKitchenKdsHelper.Done or PosKitchenKdsHelper.Voided));
            var allVoided = t.Items.All(i => i.Status == PosKitchenKdsHelper.Voided);
            var sentAt = show
                .Select(i => i.sentAt)
                .Where(s => !string.IsNullOrEmpty(s))
                .OrderBy(s => s)
                .FirstOrDefault() ?? UtcIso(DateTime.UtcNow);
            var ticketStatus = allVoided
                ? PosKitchenKdsHelper.Voided
                : PosKitchenKdsHelper.MergeStatus(show.Select(i => i.status), openLive > 0);
            tickets.Add(new
            {
                orderId = t.OrderId,
                orderNo = t.OrderNo,
                tableName = t.TableName,
                areaName = t.AreaName,
                channel = t.Channel,
                customerName = t.CustomerName,
                resourceId = t.ResourceId,
                sentAt,
                status = ticketStatus,
                items = show,
            });
        }

        return Ok(AppResponse<object>.Success(new { tickets, at = UtcIso(DateTime.UtcNow) }));
    }

    sealed class KdsTicketAcc
    {
        public Guid OrderId { get; set; }
        public string? OrderNo { get; set; }
        public string? TableName { get; set; }
        public string? AreaName { get; set; }
        public string? Channel { get; set; }
        public string? CustomerName { get; set; }
        public Guid? ResourceId { get; set; }
        public List<KdsItemAcc> Items { get; } = [];
    }

    sealed class KdsItemAcc
    {
        public Guid Id { get; set; }
        public Guid? ProductId { get; set; }
        public string ProductName { get; set; } = "";
        public decimal Qty { get; set; }
        public decimal SentQty { get; set; }
        public decimal DoneQty { get; set; }
        public string? UnitName { get; set; }
        public string? Note { get; set; }
        public string Status { get; set; } = PosKitchenKdsHelper.Queued;
        public string? SentAt { get; set; }
        public Guid? PrinterId { get; set; }
        public DateTime? SortAt { get; set; }
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

    [HttpPost("voids/ack")]
    [RequireModulePermission("PosKds", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> AckVoids([FromBody] AckVoidsDto? dto)
    {
        var storeId = RequiredStoreId;
        var ids = (dto?.Ids ?? [])
            .Where(x => x != Guid.Empty)
            .Distinct()
            .Take(400)
            .ToList();
        if (ids.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Chưa chọn phiếu hủy"));
        var n = await MarkVoidsAcked(storeId, ids: ids);
        await db.SaveChangesAsync();
        PosFloorRealtimeHelper.Notify(hub, storeId, "kds");
        return Ok(AppResponse<object>.Success(new { acked = n }));
    }

    async Task<int> MarkVoidsAcked(
        Guid storeId,
        List<Guid>? ids = null,
        Guid? saleOrderId = null)
    {
        var q = db.PosKitchenVoidSlips.AsTracking()
            .Where(v => v.StoreId == storeId && v.Deleted == null && v.KdsAckedAt == null);
        if (ids is { Count: > 0 })
            q = q.Where(v => ids.Contains(v.Id));
        else if (saleOrderId is Guid oid && oid != Guid.Empty)
            q = q.Where(v => v.SaleOrderId == oid || v.Id == oid);
        else
            return 0;
        var rows = await q.ToListAsync();
        var now = DateTime.UtcNow;
        foreach (var v in rows)
        {
            v.KdsAckedAt = now;
            v.UpdatedAt = now;
            v.UpdatedBy = CurrentUserEmail;
        }
        return rows.Count;
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
