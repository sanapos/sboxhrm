using System.Data;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Hubs;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// QR order tại bàn: khách (anonymous) gọi món; server ghi đơn bàn + (tuỳ setting) enqueue phiếu bếp Agent.
/// </summary>
[ApiController]
[Route("api/pos/qr-order")]
[Authorize]
public class PosQrTableOrderController(
    ZKTecoDbContext db,
    IPosPrintDispatchService dispatch,
    IHubContext<AttendanceHub> hub,
    IMemoryCache cache,
    IWebHostEnvironment env,
    IConfiguration config) : AuthenticatedControllerBase
{
    public class QrOrderItemDto
    {
        public Guid ProductId { get; set; }
        public Guid? VariantId { get; set; }
        public List<Guid>? ToppingIds { get; set; }
        public decimal Qty { get; set; }
        public string? Note { get; set; }
    }

    public class QrGuestLocationDto
    {
        public double? Lat { get; set; }
        public double? Lng { get; set; }
    }

    public class QrOrderSubmitDto : QrGuestLocationDto
    {
        public List<QrOrderItemDto>? Items { get; set; }
        public string? ClientRequestId { get; set; }
    }

    [HttpGet("/o/{token}")]
    [AllowAnonymous]
    [Produces("text/html")]
    public IActionResult GuestPretty(string token) => GuestPage(token);

    [HttpGet("{token}/page")]
    [AllowAnonymous]
    [Produces("text/html")]
    public IActionResult GuestPage(string token)
    {
        if (string.IsNullOrWhiteSpace(token)) return NotFound("Thiếu mã bàn");
        var html = ReadGuestHtml();
        if (html == null)
            return NotFound("Thiếu trang gọi món");
        var api = PublicBase();
        var boot =
            $"<script>window.__SBOX_API__={System.Text.Json.JsonSerializer.Serialize(api)};"
            + $"window.__SBOX_TOKEN__={System.Text.Json.JsonSerializer.Serialize(token.Trim())};</script>";
        html = html.Contains("<!--SBOX_BOOT-->")
            ? html.Replace("<!--SBOX_BOOT-->", boot)
            : html.Replace("</head>", boot + "</head>");
        return Content(html, "text/html; charset=utf-8");
    }

    [HttpGet("{token}")]
    [AllowAnonymous]
    public async Task<ActionResult<AppResponse<object>>> GetMenu(string token)
    {
        var ctx = await ResolveTableAsync(token);
        if (ctx.Error != null) return ctx.Error;
        var store = ctx.Table!.Store;
        var resource = ctx.Table.Resource;
        var settings = ctx.Table.Settings;
        var menu = await BuildMenuAsync(store, resource, settings);
        return Ok(AppResponse<object>.Success(menu));
    }

    [HttpPost("{token}/items")]
    [AllowAnonymous]
    public async Task<ActionResult<AppResponse<object>>> Submit(string token, [FromBody] QrOrderSubmitDto? dto)
    {
        var ctx = await ResolveTableAsync(token);
        if (ctx.Error != null) return ctx.Error;
        var store = ctx.Table!.Store;
        var resource = ctx.Table.Resource;
        var settings = ctx.Table.Settings;

        var lockFail = await EnforceQrGuestAsync(store.Id, settings, dto?.Lat, dto?.Lng);
        if (lockFail != null) return lockFail;
        if (QrOrderLockHelper.Parse(settings.ExtraJson).RequireOpenSession)
        {
            var openSession = await db.PosResourceSessions.AsNoTracking()
                .Where(s => s.ResourceId == resource.Id && s.Deleted == null
                    && (s.Status == PosResourceSessionStatus.Open
                        || s.Status == PosResourceSessionStatus.Paused))
                .OrderByDescending(s => s.StartedAt)
                .FirstOrDefaultAsync();
            var opened = false;
            if (openSession?.SaleOrderId is Guid openOid)
            {
                opened = await db.PosSaleOrders.AsNoTracking()
                    .AnyAsync(o => o.Id == openOid && o.Deleted == null
                        && o.Status == PosSaleOrderStatus.Draft);
            }
            if (!opened)
                return BadRequest(AppResponse<object>.Fail(
                    "Thu ngân chưa mở bàn — không gọi món từ ngoài quán"));
        }

        var rawItems = dto?.Items?
            .Where(x => x.ProductId != Guid.Empty && x.Qty > 0)
            .ToList() ?? [];
        if (rawItems.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Chọn món để đặt hàng"));
        if (rawItems.Count > 20)
            return BadRequest(AppResponse<object>.Fail("Mỗi lần gửi tối đa 20 món"));

        var rateKey = $"qr-rate:{token}";
        var n = cache.GetOrCreate(rateKey, e =>
        {
            e.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(1);
            e.Size = 1;
            return 0;
        });
        if (n >= 8)
            return BadRequest(AppResponse<object>.Fail("Gửi quá nhanh — đợi một phút rồi thử lại"));
        cache.Set(rateKey, n + 1, new MemoryCacheEntryOptions
        {
            AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(1),
            Size = 1,
        });

        var reqId = (dto?.ClientRequestId ?? "").Trim();
        if (reqId.Length is > 8 and < 80)
        {
            if (cache.TryGetValue($"qr-req:{token}:{reqId}", out object? cached) && cached != null)
                return Ok(AppResponse<object>.Success(cached));
        }

        var storeId = store.Id;
        var productIds = rawItems.Select(i => i.ProductId).Distinct().ToList();
        var products = await db.PosProducts.AsNoTracking()
            .Include(x => x.Category)
            .Where(x => productIds.Contains(x.Id) && x.StoreId == storeId && x.Deleted == null
                && x.IsActive && x.IsDirectSale && !x.IsTopping)
            .ToListAsync();
        var byId = products.ToDictionary(x => x.Id);

        var variantIds = rawItems.Where(i => i.VariantId.HasValue && i.VariantId != Guid.Empty)
            .Select(i => i.VariantId!.Value).Distinct().ToList();
        var variants = variantIds.Count == 0
            ? new Dictionary<Guid, PosProductVariant>()
            : await db.PosProductVariants.AsNoTracking()
                .Where(v => variantIds.Contains(v.Id) && v.StoreId == storeId
                    && v.Deleted == null && v.IsActive)
                .ToDictionaryAsync(v => v.Id);
        var variantCountByProduct = await db.PosProductVariants.AsNoTracking()
            .Where(v => productIds.Contains(v.ProductId) && v.StoreId == storeId
                && v.Deleted == null && v.IsActive)
            .GroupBy(v => v.ProductId)
            .ToDictionaryAsync(g => g.Key, g => g.Count());

        var toppingCatalog = await LoadToppingCatalogAsync(storeId, productIds);

        var resolved = new List<ResolvedQrLine>();
        foreach (var item in rawItems)
        {
            if (!byId.TryGetValue(item.ProductId, out var p))
                return BadRequest(AppResponse<object>.Fail("Có món không bán được trên QR"));
            if (p.RequiresSerial)
                return BadRequest(AppResponse<object>.Fail($"{p.Name} cần thu ngân nhập seri"));
            if (p.ProductType == PosProductType.Service && PosServiceBillingHelper.IsTimed(p.ServiceBillingMode))
                return BadRequest(AppResponse<object>.Fail($"{p.Name} là dịch vụ tính giờ — gọi thu ngân"));

            PosProductVariant? variant = null;
            var hasVariants = variantCountByProduct.GetValueOrDefault(p.Id) > 0;
            if (hasVariants)
            {
                if (item.VariantId is not Guid vid || vid == Guid.Empty
                    || !variants.TryGetValue(vid, out variant) || variant.ProductId != p.Id)
                    return BadRequest(AppResponse<object>.Fail($"Chọn biến thể cho {p.Name}"));
            }
            else if (item.VariantId.HasValue && item.VariantId != Guid.Empty)
                return BadRequest(AppResponse<object>.Fail($"{p.Name} không có biến thể đó"));

            var allowed = toppingCatalog.GetValueOrDefault(p.Id);
            var toppingIds = (item.ToppingIds ?? [])
                .Where(id => id != Guid.Empty)
                .Distinct()
                .Take(12)
                .ToList();
            if (toppingIds.Count > 0 && (allowed == null || allowed.Count == 0))
                return BadRequest(AppResponse<object>.Fail($"{p.Name} không chọn topping"));
            var toppings = new List<QrToppingPick>();
            foreach (var tid in toppingIds)
            {
                if (allowed == null || !allowed.TryGetValue(tid, out var t))
                    return BadRequest(AppResponse<object>.Fail($"Topping không hợp lệ cho {p.Name}"));
                toppings.Add(t);
            }

            var qty = Math.Min(20, item.Qty);
            var unitPrice = variant?.BasePrice ?? p.BasePrice;
            if (!settings.AllowNegativeStock && p.ProductType == PosProductType.Goods)
            {
                var avail = variant != null ? variant.OnHandQty : (p.OnHandQty - p.ReservedQty);
                if (avail < qty)
                    return BadRequest(AppResponse<object>.Fail($"{p.Name} tạm hết"));
            }

            var note = string.IsNullOrWhiteSpace(item.Note) ? null : item.Note.Trim();
            if (note is { Length: > 200 }) note = note[..200];
            var toppingsJson = CanonicalToppingsJson(toppings);
            var extra = toppings.Sum(t => t.Price);
            var lineName = variant != null ? $"{p.Name} — {variant.Name}" : p.Name;
            resolved.Add(new ResolvedQrLine(
                p, variant, qty, note, toppingsJson, extra, unitPrice, lineName));
        }

        var items = resolved
            .GroupBy(x => (x.Product.Id, VariantId: x.Variant?.Id, x.ToppingsJson, Note: x.Note ?? ""))
            .Select(g =>
            {
                var first = g.First();
                return first with { Qty = Math.Min(20, g.Sum(x => x.Qty)) };
            })
            .ToList();

        var autoPrint = settings.EnableQrOrderAutoPrint;
        var added = new List<(PosSaleOrderLine Line, decimal Qty, PosProduct Product)>();
        PosSaleOrder? order = null;
        PosResourceSession? session = null;
        var saved = false;
        for (var attempt = 0; attempt < 5 && !saved; attempt++)
        {
            if (attempt > 0)
                db.ChangeTracker.Clear();
            added.Clear();
            await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.RepeatableRead);
            try
            {
                var now = DateTime.UtcNow;
                session = await db.PosResourceSessions.AsTracking()
                    .FirstOrDefaultAsync(s => s.ResourceId == resource.Id && s.Deleted == null
                        && (s.Status == PosResourceSessionStatus.Open || s.Status == PosResourceSessionStatus.Paused));
                order = null;
                if (session?.SaleOrderId is Guid oid)
                {
                    order = await db.PosSaleOrders.AsTracking().Include(o => o.Lines)
                        .FirstOrDefaultAsync(o => o.Id == oid && o.StoreId == storeId && o.Deleted == null);
                    if (order != null && order.Status != PosSaleOrderStatus.Draft)
                    {
                        if (QrOrderLockHelper.Parse(settings.ExtraJson).RequireOpenSession)
                            return BadRequest(AppResponse<object>.Fail(
                                "Thu ngân chưa mở bàn — không gọi món từ ngoài quán"));
                        session.Status = PosResourceSessionStatus.Closed;
                        session.EndedAt = now;
                        session.UpdatedAt = now;
                        session = null;
                        order = null;
                    }
                }

                if (session == null || order == null)
                {
                    if (QrOrderLockHelper.Parse(settings.ExtraJson).RequireOpenSession)
                        return BadRequest(AppResponse<object>.Fail(
                            "Thu ngân chưa mở bàn — không gọi món từ ngoài quán"));
                    var orderNo = await PosSaleStockHelper.NextOrderNoAsync(db, storeId, now);
                    order = new PosSaleOrder
                    {
                        Id = Guid.NewGuid(),
                        StoreId = storeId,
                        OrderNo = orderNo,
                        Status = PosSaleOrderStatus.Draft,
                        PaymentMethod = "Tiền mặt",
                        CustomerName = "QR tại bàn",
                        ServiceResourceId = null,
                        ServiceStartedAt = now,
                        SaleDate = now,
                        SalesChannel = "QR bàn",
                        IsActive = true,
                        CreatedBy = "QR khách",
                        CreatedAt = now,
                    };
                    db.PosSaleOrders.Add(order);
                    session = new PosResourceSession
                    {
                        Id = Guid.NewGuid(),
                        StoreId = storeId,
                        ResourceId = resource.Id,
                        SaleOrderId = order.Id,
                        StartedAt = now,
                        Status = PosResourceSessionStatus.Open,
                        GuestCount = 1,
                        IsActive = true,
                        CreatedBy = "QR khách",
                        CreatedAt = now,
                    };
                    db.PosResourceSessions.Add(session);
                }

                foreach (var item in items)
                {
                    var p = item.Product;
                    var existing = order.Lines.FirstOrDefault(l => l.Deleted == null
                        && l.ProductId == p.Id
                        && l.VariantId == item.Variant?.Id
                        && string.Equals(CanonicalToppingsJsonRaw(l.ToppingsJson) ?? "", item.ToppingsJson ?? "", StringComparison.Ordinal)
                        && string.Equals((l.LineNote ?? "").Trim(), item.Note ?? "", StringComparison.Ordinal));
                    if (existing != null)
                    {
                        existing.Qty += item.Qty;
                        existing.LineTotal = Math.Round(
                            (existing.UnitPrice + item.ToppingExtra) * existing.Qty - existing.DiscountAmount,
                            0, MidpointRounding.AwayFromZero);
                        existing.UpdatedAt = now;
                        existing.UpdatedBy = "QR khách";
                        added.Add((existing, item.Qty, p));
                        continue;
                    }
                    var line = new PosSaleOrderLine
                    {
                        Id = Guid.NewGuid(),
                        StoreId = storeId,
                        SaleOrderId = order.Id,
                        ProductId = p.Id,
                        VariantId = item.Variant?.Id,
                        ProductName = item.LineName,
                        UnitName = p.BaseUnitName,
                        Qty = item.Qty,
                        UnitPrice = item.UnitPrice,
                        LineTotal = Math.Round((item.UnitPrice + item.ToppingExtra) * item.Qty, 0, MidpointRounding.AwayFromZero),
                        LineNote = item.Note,
                        ToppingsJson = item.ToppingsJson,
                        KitchenSentQty = 0,
                        IsActive = true,
                        CreatedBy = "QR khách",
                        CreatedAt = now,
                    };
                    db.PosSaleOrderLines.Add(line);
                    order.Lines.Add(line);
                    added.Add((line, item.Qty, p));
                }

                if (autoPrint)
                {
                    foreach (var row in added)
                    {
                        var pending = row.Line.Qty - row.Line.KitchenSentQty;
                        if (pending <= 0) continue;
                        row.Line.KitchenSentQty = row.Line.Qty;
                        row.Line.KitchenSentAt = now;
                        PosKitchenKdsHelper.OnSent(row.Line);
                    }
                }

                await db.SaveChangesAsync();

                var subTotal = order.Lines.Where(l => l.Deleted == null).Sum(l => l.LineTotal);
                var total = Math.Max(0, subTotal - order.Discount);
                order.SubTotal = subTotal;
                order.Total = total;
                order.ResourceSessionId = session.Id;
                order.ServiceResourceId = resource.Id;
                order.LockVersion += 1;
                order.UpdatedAt = now;
                order.UpdatedBy = "QR khách";
                await db.SaveChangesAsync();
                await tx.CommitAsync();
                saved = true;
            }
            catch (Exception ex) when (attempt < 4 && IsQrConcurrencyFailure(ex))
            {
                await tx.RollbackAsync();
            }
            catch
            {
                await tx.RollbackAsync();
                throw;
            }
        }

        if (!saved || order == null || session == null)
            return Conflict(AppResponse<object>.Fail("Bàn đang được cập nhật — gửi lại món"));

        var printJobs = 0;
        if (autoPrint)
        {
            try
            {
                printJobs = await EnqueueKitchenAsync(storeId, resource, order, added, DateTime.UtcNow);
            }
            catch
            {
                // Đơn vẫn ghi — phiếu có thể thiếu nếu chưa gán máy in bếp.
            }
        }

        var tableName = TableLabel(resource);
        PosFloorRealtimeHelper.Notify(hub, storeId, "qrOrder",
            orderId: order.Id, resourceId: resource.Id, sessionId: session.Id,
            tableName: tableName);

        var payload = new
        {
            ok = true,
            orderNo = order.OrderNo,
            addedLines = added.Count,
            printJobs,
            autoPrint,
            message = autoPrint
                ? (printJobs > 0
                    ? "Đã đặt hàng"
                    : "Đã ghi món — chưa in được phiếu (kiểm tra máy in bếp / Agent)")
                : "Đã ghi món — thu ngân sẽ in phiếu bếp",
        };
        if (reqId.Length is > 8 and < 80)
            cache.Set($"qr-req:{token}:{reqId}", payload, new MemoryCacheEntryOptions
            {
                AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(10),
                Size = 1,
            });
        return Ok(AppResponse<object>.Success(payload));
    }

    [HttpPost("{token}/call-payment")]
    [AllowAnonymous]
    public async Task<ActionResult<AppResponse<object>>> CallPayment(string token, [FromBody] QrGuestLocationDto? dto)
    {
        var ctx = await ResolveTableAsync(token);
        if (ctx.Error != null) return ctx.Error;
        var store = ctx.Table!.Store;
        var resource = ctx.Table.Resource;
        var lockFail = await EnforceQrGuestAsync(store.Id, ctx.Table.Settings, dto?.Lat, dto?.Lng);
        if (lockFail != null) return lockFail;

        var rateKey = $"qr-pay:{token}";
        var n = cache.GetOrCreate(rateKey, e =>
        {
            e.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(1);
            e.Size = 1;
            return 0;
        });
        if (n >= 4)
            return BadRequest(AppResponse<object>.Fail("Gọi thanh toán quá nhanh — đợi một phút rồi thử lại"));
        cache.Set(rateKey, n + 1, new MemoryCacheEntryOptions
        {
            AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(1),
            Size = 1,
        });

        var tableName = TableLabel(resource);
        PosFloorRealtimeHelper.Notify(hub, store.Id, "qrCallPayment",
            resourceId: resource.Id, tableName: tableName);

        return Ok(AppResponse<object>.Success(new
        {
            ok = true,
            message = "Đã gọi thu ngân thanh toán",
        }));
    }

    [HttpPost("{token}/call-staff")]
    [AllowAnonymous]
    public async Task<ActionResult<AppResponse<object>>> CallStaff(string token, [FromBody] QrGuestLocationDto? dto)
    {
        var ctx = await ResolveTableAsync(token);
        if (ctx.Error != null) return ctx.Error;
        var store = ctx.Table!.Store;
        var resource = ctx.Table.Resource;
        var lockFail = await EnforceQrGuestAsync(store.Id, ctx.Table.Settings, dto?.Lat, dto?.Lng);
        if (lockFail != null) return lockFail;

        if (!TryGuestRateLimit($"qr-staff:{token}", 4, out var fail))
            return fail!;

        var tableName = TableLabel(resource);
        PosFloorRealtimeHelper.Notify(hub, store.Id, "qrCallStaff",
            resourceId: resource.Id, tableName: tableName);

        return Ok(AppResponse<object>.Success(new
        {
            ok = true,
            message = "Đã gọi phục vụ",
        }));
    }

    [HttpPost("{token}/confirm-qr-paid")]
    [AllowAnonymous]
    public async Task<ActionResult<AppResponse<object>>> ConfirmQrPaid(string token, [FromBody] QrGuestLocationDto? dto)
    {
        var ctx = await ResolveTableAsync(token);
        if (ctx.Error != null) return ctx.Error;
        var store = ctx.Table!.Store;
        var resource = ctx.Table.Resource;
        var lockFail = await EnforceQrGuestAsync(store.Id, ctx.Table.Settings, dto?.Lat, dto?.Lng);
        if (lockFail != null) return lockFail;

        if (!TryGuestRateLimit($"qr-paid:{token}", 3, out var fail))
            return fail!;

        var session = await db.PosResourceSessions.AsNoTracking()
            .Where(s => s.ResourceId == resource.Id && s.Deleted == null
                && (s.Status == PosResourceSessionStatus.Open || s.Status == PosResourceSessionStatus.Paused))
            .OrderByDescending(s => s.StartedAt)
            .FirstOrDefaultAsync();
        PosSaleOrder? order = null;
        if (session?.SaleOrderId is Guid oid)
        {
            order = await db.PosSaleOrders.AsNoTracking()
                .FirstOrDefaultAsync(o => o.Id == oid && o.Deleted == null
                    && o.Status == PosSaleOrderStatus.Draft);
        }
        if (order == null || order.Total <= 0)
            return BadRequest(AppResponse<object>.Fail("Chưa có đơn để xác nhận thanh toán"));

        var tableName = TableLabel(resource);
        var msg = $"{tableName} xác nhận đã thanh toán QR {order.Total:0}đ — kiểm tra giao dịch";
        PosFloorRealtimeHelper.Notify(hub, store.Id, "qrPaidConfirm",
            orderId: order.Id, resourceId: resource.Id, sessionId: session?.Id,
            tableName: tableName, message: msg);

        return Ok(AppResponse<object>.Success(new
        {
            ok = true,
            orderNo = order.OrderNo,
            total = order.Total,
            message = "Đã báo thu ngân kiểm tra giao dịch QR",
        }));
    }

    [HttpGet("tables")]
    [RequireModulePermission("PosQrOrder", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> ListTables()
    {
        var storeId = RequiredStoreId;
        var settings = await db.PosStoreSellSettings.AsNoTracking()
            .FirstOrDefaultAsync(s => s.StoreId == storeId && s.Deleted == null);
        var enabled = settings?.EnableQrTableOrder == true;
        var autoPrint = settings?.EnableQrOrderAutoPrint != false;
        var lockOpt = QrOrderLockHelper.Parse(settings?.ExtraJson);
        var geoConfigured = await db.Geofences.AsNoTracking()
            .AnyAsync(g => g.StoreId == storeId && g.Deleted == null && g.IsActive);
        var resources = await db.PosServiceResources.AsTracking()
            .Include(r => r.Area)
            .Where(r => r.StoreId == storeId && r.Deleted == null && r.IsActive)
            .OrderBy(r => r.Area!.SortOrder).ThenBy(r => r.SortOrder).ThenBy(r => r.Name)
            .ToListAsync();
        var changed = false;
        foreach (var r in resources)
        {
            if (!string.IsNullOrWhiteSpace(r.QrOrderToken)) continue;
            r.QrOrderToken = NewToken();
            changed = true;
        }
        if (changed) await db.SaveChangesAsync();

        var urlBase = PublicBase();
        return Ok(AppResponse<object>.Success(new
        {
            enabled,
            autoPrintKitchen = autoPrint,
            requireOpenSession = lockOpt.RequireOpenSession,
            requireGeofence = lockOpt.RequireGeofence,
            geoConfigured,
            publicBaseUrl = urlBase,
            tables = resources.Select(r => new
            {
                id = r.Id,
                name = r.Name,
                code = r.Code,
                areaName = r.Area?.Name,
                token = r.QrOrderToken,
                url = QrUrl(urlBase, r.QrOrderToken!),
            }),
        }));
    }

    [HttpPost("tables/{id:guid}/rotate-token")]
    [RequireModulePermission("PosQrOrder", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> RotateToken(Guid id)
    {
        var storeId = RequiredStoreId;
        var r = await db.PosServiceResources.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (r == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy bàn"));
        r.QrOrderToken = NewToken();
        r.UpdatedAt = DateTime.UtcNow;
        r.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync();
        var urlBase = PublicBase();
        return Ok(AppResponse<object>.Success(new
        {
            id = r.Id,
            token = r.QrOrderToken,
            url = QrUrl(urlBase, r.QrOrderToken!),
        }));
    }

    sealed class QrTableCtx(Store Store, PosServiceResource Resource, PosStoreSellSettings Settings)
    {
        public Store Store { get; } = Store;
        public PosServiceResource Resource { get; } = Resource;
        public PosStoreSellSettings Settings { get; } = Settings;
    }

    sealed record QrToppingPick(Guid Id, string Name, decimal Price);

    sealed record ResolvedQrLine(
        PosProduct Product,
        PosProductVariant? Variant,
        decimal Qty,
        string? Note,
        string? ToppingsJson,
        decimal ToppingExtra,
        decimal UnitPrice,
        string LineName);

    async Task<(ActionResult<AppResponse<object>>? Error, QrTableCtx? Table)>
        ResolveTableAsync(string token)
    {
        token = (token ?? "").Trim();
        if (token.Length is < 8 or > 32)
            return (NotFound(AppResponse<object>.Fail("Mã QR không hợp lệ")), null);
        var resource = await db.PosServiceResources.AsNoTracking()
            .Include(r => r.Area)
            .FirstOrDefaultAsync(r => r.QrOrderToken == token && r.Deleted == null && r.IsActive);
        if (resource == null)
            return (NotFound(AppResponse<object>.Fail("Không tìm thấy bàn")), null);
        var settings = await db.PosStoreSellSettings.AsNoTracking()
            .FirstOrDefaultAsync(s => s.StoreId == resource.StoreId && s.Deleted == null);
        if (settings == null || !settings.EnableQrTableOrder || !settings.EnableResources)
            return (BadRequest(AppResponse<object>.Fail("Quán chưa bật gọi món QR tại bàn")), null);
        var store = await db.Stores.AsNoTracking().FirstOrDefaultAsync(s => s.Id == resource.StoreId);
        if (store == null)
            return (NotFound(AppResponse<object>.Fail("Không tìm thấy cửa hàng")), null);
        return (null, new QrTableCtx(store, resource, settings));
    }

    async Task<ActionResult<AppResponse<object>>?> EnforceQrGuestAsync(
        Guid storeId, PosStoreSellSettings settings, double? lat, double? lng)
    {
        var opt = QrOrderLockHelper.Parse(settings.ExtraJson);
        if (!opt.RequireGeofence) return null;
        var fences = await db.Geofences.AsNoTracking()
            .Where(g => g.StoreId == storeId && g.Deleted == null && g.IsActive)
            .Select(g => new { g.Latitude, g.Longitude, g.RadiusMeters })
            .ToListAsync();
        if (fences.Count == 0) return null;
        if (lat is not double la || lng is not double ln)
            return BadRequest(AppResponse<object>.Fail(
                "Bật vị trí trên điện thoại để gọi món trong quán"));
        var inside = QrOrderLockHelper.IsInsideAny(la, ln,
            fences.Select(f => (f.Latitude, f.Longitude, f.RadiusMeters)));
        if (!inside)
            return BadRequest(AppResponse<object>.Fail(
                "Bạn đang ngoài phạm vi quán — chỉ gọi món khi có mặt tại quán"));
        return null;
    }

    async Task<object> BuildMenuAsync(Store store, PosServiceResource resource, PosStoreSellSettings settings)
    {
        var products = await db.PosProducts.AsNoTracking()
            .Include(p => p.Category)
            .Where(p => p.StoreId == store.Id && p.Deleted == null && p.IsActive && p.IsDirectSale
                && !p.IsTopping
                && !p.RequiresSerial
                && !(p.ProductType == PosProductType.Service && p.ServiceBillingMode != PosServiceBillingMode.Flat))
            .OrderBy(p => p.SortOrder).ThenBy(p => p.Name)
            .ToListAsync();

        var productIds = products.Select(p => p.Id).ToList();
        var variants = productIds.Count == 0
            ? []
            : await db.PosProductVariants.AsNoTracking()
                .Where(v => productIds.Contains(v.ProductId) && v.StoreId == store.Id
                    && v.Deleted == null && v.IsActive)
                .OrderBy(v => v.Name)
                .ToListAsync();
        var variantsByProduct = variants.GroupBy(v => v.ProductId)
            .ToDictionary(g => g.Key, g => g.ToList());

        var toppingCatalog = await LoadToppingCatalogGroupedAsync(store.Id, productIds);

        var cats = products
            .Where(p => p.CategoryId != null)
            .GroupBy(p => p.CategoryId!.Value)
            .Select(g => new { id = g.Key, name = g.First().Category?.Name ?? "Khác" })
            .OrderBy(c => c.name)
            .ToList();

        Guid? orderId = null;
        var session = await db.PosResourceSessions.AsNoTracking()
            .Where(s => s.ResourceId == resource.Id && s.Deleted == null
                && (s.Status == PosResourceSessionStatus.Open || s.Status == PosResourceSessionStatus.Paused))
            .OrderByDescending(s => s.StartedAt)
            .FirstOrDefaultAsync();
        object? bill = null;
        PosSaleOrder? openOrder = null;
        decimal billPayable = 0;
        if (session?.SaleOrderId is Guid oid)
        {
            orderId = oid;
            openOrder = await db.PosSaleOrders.AsNoTracking().Include(o => o.Lines)
                .FirstOrDefaultAsync(o => o.Id == oid && o.Deleted == null && o.Status == PosSaleOrderStatus.Draft);
            if (openOrder != null)
            {
                var started = openOrder.ServiceStartedAt ?? openOrder.SaleDate ?? openOrder.CreatedAt;
                var vn = VnTimeHelper.UtcToVn(started);
                var vis = openOrder.Lines.Where(l => l.Deleted == null).ToList();
                var lines = vis.Select(l =>
                {
                    var qty = l.Qty;
                    var unit = qty > 0
                        ? Math.Round(l.LineTotal / qty, 0, MidpointRounding.AwayFromZero)
                        : l.UnitPrice;
                    return new
                    {
                        name = l.ProductName,
                        qty,
                        unitName = l.UnitName,
                        unitPrice = unit,
                        lineTotal = l.LineTotal,
                        note = KitchenNoteText(l.ToppingsJson, l.LineNote),
                    };
                }).ToList();
                var linesTotal = vis.Sum(l => l.LineTotal);
                var discount = Math.Max(0, openOrder.Discount);
                var net = Math.Max(0, linesTotal - discount);
                var einv = await db.PosEInvoiceSettings.AsNoTracking()
                    .FirstOrDefaultAsync(x => x.StoreId == store.Id && x.Deleted == null);
                var tax = QrOrderTaxHelper.Resolve(settings.ExtraJson, einv);
                var pids = vis.Select(l => l.ProductId).Distinct().ToList();
                var productTax = pids.Count == 0
                    ? new Dictionary<Guid, (decimal Rate, bool Exempt)>()
                    : await db.PosProducts.AsNoTracking()
                        .Where(p => pids.Contains(p.Id))
                        .ToDictionaryAsync(p => p.Id, p => (Rate: p.VatRate, Exempt: p.VatExempt));
                var taxLines = vis.Select(l =>
                {
                    productTax.TryGetValue(l.ProductId, out var pt);
                    return (l.LineTotal, pt.Rate, pt.Exempt);
                }).ToList();
                var (vat, payable) = QrOrderTaxHelper.Compute(tax, net, taxLines);
                billPayable = payable;
                bill = new
                {
                    title = "HÓA ĐƠN TẠM TÍNH",
                    unpaid = true,
                    storeName = store.Name,
                    storeAddress = store.Address,
                    storePhone = store.Phone,
                    tableName = resource.Name,
                    areaName = resource.Area?.Name,
                    orderNo = openOrder.OrderNo,
                    dateText = vn.ToString("dd/MM/yyyy"),
                    timeText = vn.ToString("HH:mm"),
                    guestCount = session.GuestCount,
                    lines,
                    subTotal = linesTotal,
                    discount,
                    vatAmount = vat,
                    vatRate = tax.VatRate,
                    taxMode = tax.Mode,
                    total = payable,
                };
            }
        }

        var lockOpt = QrOrderLockHelper.Parse(settings.ExtraJson);
        var tableOpen = openOrder != null;
        var geoConfigured = await db.Geofences.AsNoTracking()
            .AnyAsync(g => g.StoreId == store.Id && g.Deleted == null && g.IsActive);
        var canOrder = !lockOpt.RequireOpenSession || tableOpen;
        string? lockMessage = canOrder
            ? null
            : "Thu ngân chưa mở bàn — chưa gọi món được";
        var lockInfo = new
        {
            requireOpenSession = lockOpt.RequireOpenSession,
            tableOpen,
            requireGeofence = lockOpt.RequireGeofence,
            geoConfigured,
            canOrder,
            message = lockMessage,
        };

        object? payment = null;
        var bank = await db.BankAccounts.AsNoTracking()
            .Where(x => x.StoreId == store.Id && x.IsActive && x.Deleted == null)
            .OrderByDescending(x => x.IsDefault)
            .ThenBy(x => x.BankName)
            .FirstOrDefaultAsync();
        if (bank != null)
        {
            var amount = billPayable;
            var addInfo = QrAddInfo(resource.Code ?? resource.Name, openOrder?.OrderNo);
            var qrUrl = VietQRBanks.GenerateVietQRUrl(
                bank.BankCode,
                bank.AccountNumber,
                amount > 0 ? amount : null,
                addInfo,
                string.IsNullOrWhiteSpace(bank.VietQRTemplate) ? "compact2" : bank.VietQRTemplate);
            payment = new
            {
                qrUrl,
                amount,
                addInfo,
                bankName = bank.BankShortName ?? bank.BankName,
                accountName = bank.AccountName,
                accountNumber = bank.AccountNumber,
                orderNo = openOrder?.OrderNo,
            };
        }

        return new
        {
            storeName = store.Name,
            tableName = resource.Name,
            areaName = resource.Area?.Name,
            tableCode = resource.Code,
            autoPrintKitchen = settings.EnableQrOrderAutoPrint,
            categories = cats,
            products = products.Select(p =>
            {
                var pVars = variantsByProduct.GetValueOrDefault(p.Id) ?? [];
                toppingCatalog.TryGetValue(p.Id, out var tops);
                var soldOut = !settings.AllowNegativeStock
                    && p.ProductType == PosProductType.Goods
                    && pVars.Count == 0
                    && (p.OnHandQty - p.ReservedQty) <= 0;
                return new
                {
                    id = p.Id,
                    name = p.Name,
                    price = p.BasePrice,
                    imageUrl = p.ImageUrl,
                    categoryId = p.CategoryId,
                    soldOut,
                    variants = pVars.Select(v => new
                    {
                        id = v.Id,
                        name = v.Name,
                        price = v.BasePrice,
                        soldOut = !settings.AllowNegativeStock && v.OnHandQty <= 0,
                    }),
                    toppings = (tops?.Direct ?? []).Select(t => new { id = t.Id, name = t.Name, price = t.Price }),
                    toppingGroups = (tops?.Groups ?? []).Select(g => new
                    {
                        name = g.Name,
                        items = g.Items.Select(t => new { id = t.Id, name = t.Name, price = t.Price }),
                    }),
                };
            }),
            bill,
            orderId,
            payment,
            orderLock = lockInfo,
        };
    }

    async Task<int> EnqueueKitchenAsync(
        Guid storeId,
        PosServiceResource resource,
        PosSaleOrder order,
        List<(PosSaleOrderLine Line, decimal Qty, PosProduct Product)> added,
        DateTime now)
    {
        var fallback = await dispatch.ResolvePrinterAsync(storeId, PosPrintDocumentType.KitchenSlip);
        var groups = new Dictionary<Guid, List<(string Name, decimal Qty, string? Unit, string? Note)>>();
        foreach (var row in added)
        {
            var printerId = row.Product.DefaultPrinterId
                ?? row.Product.Category?.DefaultPrinterId
                ?? fallback?.Id;
            if (printerId == null) continue;
            if (!groups.TryGetValue(printerId.Value, out var list))
            {
                list = [];
                groups[printerId.Value] = list;
            }
            list.Add((row.Line.ProductName, row.Qty, row.Line.UnitName,
                KitchenNoteText(row.Line.ToppingsJson, row.Line.LineNote)));
        }
        if (groups.Count == 0 && fallback != null)
        {
            groups[fallback.Id] = added.Select(r =>
                (r.Line.ProductName, r.Qty, r.Line.UnitName,
                    KitchenNoteText(r.Line.ToppingsJson, r.Line.LineNote))).ToList();
        }

        var tableName = TableLabel(resource);
        var jobs = 0;
        var stamp = now.ToString("HHmmss");
        foreach (var g in groups)
        {
            var payload = JsonSerializer.Serialize(new
            {
                tableName,
                isCancel = false,
                senderName = "QR khách",
                orderNo = order.OrderNo ?? "",
                sentAt = now.ToUniversalTime().ToString("o"),
                lines = g.Value.Select(l => new
                {
                    productName = l.Name,
                    qty = l.Qty,
                    unitName = l.Unit,
                    note = l.Note,
                }),
            });
            var refNo = $"QR|{order.OrderNo}|{stamp}|{g.Key.ToString("N")[..6]}";
            await dispatch.EnqueueJobAsync(new EnqueuePrintJobRequest(
                storeId,
                PosPrintDocumentType.KitchenSlip,
                PosPrintPayloadFormat.KitchenSlipJson,
                payload,
                1,
                refNo,
                order.Id,
                null,
                "QR khách",
                g.Key));
            jobs++;
        }
        return jobs;
    }

    async Task<Dictionary<Guid, Dictionary<Guid, QrToppingPick>>> LoadToppingCatalogAsync(
        Guid storeId, List<Guid> productIds)
    {
        var grouped = await LoadToppingCatalogGroupedAsync(storeId, productIds);
        var map = new Dictionary<Guid, Dictionary<Guid, QrToppingPick>>();
        foreach (var (pid, bag) in grouped)
        {
            var byId = new Dictionary<Guid, QrToppingPick>();
            foreach (var t in bag.Direct) byId[t.Id] = t;
            foreach (var g in bag.Groups)
                foreach (var t in g.Items)
                    byId[t.Id] = t;
            map[pid] = byId;
        }
        return map;
    }

    sealed class ToppingBag
    {
        public List<QrToppingPick> Direct { get; init; } = [];
        public List<(string Name, List<QrToppingPick> Items)> Groups { get; init; } = [];
    }

    async Task<Dictionary<Guid, ToppingBag>> LoadToppingCatalogGroupedAsync(
        Guid storeId, List<Guid> productIds)
    {
        var result = new Dictionary<Guid, ToppingBag>();
        if (productIds.Count == 0) return result;

        var direct = await db.PosProductToppingOptions.AsNoTracking()
            .Include(t => t.ToppingProduct)
            .Where(t => productIds.Contains(t.ProductId) && t.StoreId == storeId
                && t.Deleted == null && t.IsActive)
            .OrderBy(t => t.SortOrder)
            .ToListAsync();
        var directByProduct = direct.GroupBy(t => t.ProductId)
            .ToDictionary(g => g.Key, g => g
                .Where(t => t.ToppingProduct != null && t.ToppingProduct.Deleted == null && t.ToppingProduct.IsActive)
                .Select(t => new QrToppingPick(
                    t.ToppingProductId,
                    t.ToppingProduct!.Name,
                    t.ExtraPrice ?? t.ToppingProduct.BasePrice))
                .ToList());

        var links = await db.PosProductToppingGroupLinks.AsNoTracking()
            .Where(l => productIds.Contains(l.ProductId) && l.StoreId == storeId
                && l.Deleted == null && l.IsActive)
            .OrderBy(l => l.SortOrder)
            .ToListAsync();
        var groupIds = links.Select(l => l.GroupId).Distinct().ToList();
        var groups = groupIds.Count == 0
            ? new Dictionary<Guid, PosToppingGroup>()
            : await db.PosToppingGroups.AsNoTracking()
                .Where(g => groupIds.Contains(g.Id) && g.StoreId == storeId
                    && g.Deleted == null && g.IsActive)
                .ToDictionaryAsync(g => g.Id);
        var groupItems = groupIds.Count == 0
            ? []
            : await db.PosToppingGroupItems.AsNoTracking()
                .Include(i => i.ToppingProduct)
                .Where(i => groupIds.Contains(i.GroupId) && i.StoreId == storeId
                    && i.Deleted == null && i.IsActive)
                .OrderBy(i => i.SortOrder)
                .ToListAsync();
        var itemsByGroup = groupItems.GroupBy(i => i.GroupId)
            .ToDictionary(g => g.Key, g => g
                .Where(i => i.ToppingProduct != null && i.ToppingProduct.Deleted == null && i.ToppingProduct.IsActive)
                .Select(i => new QrToppingPick(
                    i.ToppingProductId,
                    i.ToppingProduct!.Name,
                    i.ExtraPrice ?? i.ToppingProduct.BasePrice))
                .ToList());

        foreach (var pid in productIds)
        {
            var groupList = new List<(string Name, List<QrToppingPick> Items)>();
            foreach (var link in links.Where(l => l.ProductId == pid))
            {
                if (!groups.TryGetValue(link.GroupId, out var grp)) continue;
                if (!itemsByGroup.TryGetValue(grp.Id, out var gItems) || gItems.Count == 0)
                    continue;
                groupList.Add((grp.Name, gItems));
            }
            var bag = new ToppingBag
            {
                Direct = directByProduct.GetValueOrDefault(pid) ?? [],
                Groups = groupList,
            };
            if (bag.Direct.Count > 0 || bag.Groups.Count > 0)
                result[pid] = bag;
        }
        return result;
    }

    static string TableLabel(PosServiceResource resource) =>
        string.IsNullOrWhiteSpace(resource.Area?.Name)
            ? resource.Name
            : $"{resource.Area!.Name} · {resource.Name}";

    bool TryGuestRateLimit(string key, int maxPerMinute, out ActionResult<AppResponse<object>>? fail)
    {
        var n = cache.GetOrCreate(key, e =>
        {
            e.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(1);
            e.Size = 1;
            return 0;
        });
        if (n >= maxPerMinute)
        {
            fail = BadRequest(AppResponse<object>.Fail("Thao tác quá nhanh — đợi một phút rồi thử lại"));
            return false;
        }
        cache.Set(key, n + 1, new MemoryCacheEntryOptions
        {
            AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(1),
            Size = 1,
        });
        fail = null;
        return true;
    }

    static string QrAddInfo(string? table, string? orderNo)
    {
        var raw = $"{table} {orderNo}".Trim();
        var chars = raw.Where(c => char.IsLetterOrDigit(c) || c is ' ' or '-').ToArray();
        var s = new string(chars).Trim();
        if (s.Length > 25) s = s[..25];
        return string.IsNullOrWhiteSpace(s) ? "QR ORDER" : s;
    }

    static string? CanonicalToppingsJson(IReadOnlyList<QrToppingPick> toppings)
    {
        if (toppings.Count == 0) return null;
        return JsonSerializer.Serialize(
            toppings.OrderBy(t => t.Id).Select(t => new { id = t.Id, name = t.Name, price = t.Price }));
    }

    static string? CanonicalToppingsJsonRaw(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.ValueKind != JsonValueKind.Array) return json.Trim();
            var picks = new List<QrToppingPick>();
            foreach (var el in doc.RootElement.EnumerateArray())
            {
                if (el.ValueKind != JsonValueKind.Object) continue;
                if (!el.TryGetProperty("id", out var idEl) && !el.TryGetProperty("Id", out idEl))
                    continue;
                var idStr = idEl.ValueKind == JsonValueKind.String ? idEl.GetString() : idEl.GetRawText();
                if (!Guid.TryParse(idStr?.Trim('"'), out var id)) continue;
                var name = "";
                if (el.TryGetProperty("name", out var nEl) || el.TryGetProperty("Name", out nEl))
                    name = nEl.GetString() ?? "";
                decimal price = 0;
                if (el.TryGetProperty("price", out var pEl) || el.TryGetProperty("Price", out pEl))
                    pEl.TryGetDecimal(out price);
                picks.Add(new QrToppingPick(id, name, price));
            }
            return CanonicalToppingsJson(picks);
        }
        catch
        {
            return json.Trim();
        }
    }

    static string? KitchenNoteText(string? toppingsJson, string? lineNote)
    {
        var parts = new List<string>();
        if (!string.IsNullOrWhiteSpace(toppingsJson))
        {
            try
            {
                using var doc = JsonDocument.Parse(toppingsJson);
                if (doc.RootElement.ValueKind == JsonValueKind.Array)
                {
                    var names = new List<string>();
                    foreach (var el in doc.RootElement.EnumerateArray())
                    {
                        if (el.ValueKind != JsonValueKind.Object) continue;
                        if (!el.TryGetProperty("name", out var nameEl) &&
                            !el.TryGetProperty("Name", out nameEl))
                            continue;
                        var n = nameEl.GetString();
                        if (!string.IsNullOrWhiteSpace(n)) names.Add(n.Trim());
                    }
                    if (names.Count > 0) parts.Add(string.Join(", ", names));
                }
            }
            catch { /* ignore */ }
        }
        if (!string.IsNullOrWhiteSpace(lineNote)) parts.Add(lineNote.Trim());
        return parts.Count == 0 ? null : string.Join(" · ", parts);
    }

    static bool IsQrConcurrencyFailure(Exception ex)
    {
        for (var e = ex; e != null; e = e.InnerException)
        {
            if (e is Npgsql.PostgresException { SqlState: "40001" or "40P01" or "23505" })
                return true;
            if (e.Message.Contains("IX_PosSaleOrders_StoreId_OrderNo", StringComparison.Ordinal))
                return true;
        }
        return false;
    }

    string? ReadGuestHtml()
    {
        foreach (var path in new[]
        {
            Path.Combine(AppContext.BaseDirectory, "guest", "qr-order.html"),
            Path.Combine(env.ContentRootPath, "guest", "qr-order.html"),
            Path.Combine(env.WebRootPath ?? "wwwroot", "qr-order.html"),
            Path.Combine(env.ContentRootPath, "wwwroot", "qr-order.html"),
        })
        {
            if (System.IO.File.Exists(path))
                return System.IO.File.ReadAllText(path);
        }

        var asm = typeof(PosQrTableOrderController).Assembly;
        using var stream = asm.GetManifestResourceStream("Sbox.QrOrder.html");
        if (stream == null) return null;
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }

    string PublicBase()
    {
        var cfg = (config["PublicWebBaseUrl"] ?? "").Trim().TrimEnd('/');
        if (!string.IsNullOrWhiteSpace(cfg)) return cfg;
        var proto = Request.Headers["X-Forwarded-Proto"].FirstOrDefault() ?? Request.Scheme;
        var host = Request.Headers["X-Forwarded-Host"].FirstOrDefault() ?? Request.Host.Value;
        return $"{proto}://{host}".TrimEnd('/');
    }

    string QrUrl(string publicBase, string token)
    {
        var root = string.IsNullOrWhiteSpace(publicBase) ? PublicBase() : publicBase.TrimEnd('/');
        return $"{root}/o/{token}";
    }

    static string NewToken() => Guid.NewGuid().ToString("N")[..12];
}
