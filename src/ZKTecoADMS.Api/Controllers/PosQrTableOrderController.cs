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
using ZKTecoADMS.Api.Services.Shipping;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

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
    IConfiguration config,
    ISystemNotificationService notificationService,
    PosShippingService shipping,
    PosQrMenuService qrMenu) : AuthenticatedControllerBase
{
    public class QrOrderItemDto
    {
        public Guid ProductId { get; set; }
        public Guid? VariantId { get; set; }
        public Guid? UnitId { get; set; }
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
        /// <summary>Đặt online ngoài quán: tên / SĐT / địa chỉ — quán gọi lại.</summary>
        public string? GuestName { get; set; }
        public string? GuestPhone { get; set; }
        public string? GuestAddress { get; set; }
        public string? GuestProvince { get; set; }
        public string? GuestWard { get; set; }
        public string? GuestAddressDetail { get; set; }
        public string? GuestNote { get; set; }
    }

    [HttpGet("/o/{token}")]
    [AllowAnonymous]
    [Produces("text/html")]
    public IActionResult GuestPretty(string token) => GuestPage(token);

    [HttpGet("brand/default-logo")]
    [AllowAnonymous]
    public IActionResult DefaultBrandLogo()
    {
        var path = ResolveDefaultLogoPath();
        if (path == null) return NotFound();
        return PhysicalFile(path, "image/png");
    }

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
        var ctx = await ResolveAnyAsync(token);
        if (ctx.Error != null) return ctx.Error;
        var store = ctx.Ctx!.Store;
        var settings = ctx.Ctx.Settings;
        var menu = await BuildMenuAsync(store, ctx.Ctx.Resource, settings, ctx.Ctx.IsOnline);
        return Ok(AppResponse<object>.Success(menu));
    }

    [HttpPost("{token}/items")]
    [AllowAnonymous]
    public async Task<ActionResult<AppResponse<object>>> Submit(string token, [FromBody] QrOrderSubmitDto? dto)
    {
        var ctx = await ResolveAnyAsync(token);
        if (ctx.Error != null) return ctx.Error;
        var store = ctx.Ctx!.Store;
        var resource = ctx.Ctx.Resource;
        var settings = ctx.Ctx.Settings;
        var isOnline = ctx.Ctx.IsOnline;

        if (!isOnline)
        {
            var lockFail = await EnforceQrGuestAsync(store.Id, settings, dto?.Lat, dto?.Lng);
            if (lockFail != null) return lockFail;
            if (QrOrderLockHelper.Parse(settings.ExtraJson).RequireOpenSession)
            {
                var openSession = await db.PosResourceSessions.AsNoTracking()
                    .Where(s => s.ResourceId == resource!.Id && s.Deleted == null
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
        var useCustomMenu = PosQrMenuService.UseCustomMenu(settings.ExtraJson);
        var menuMap = await qrMenu.LoadMapAsync(storeId);
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

        var unitIds = rawItems.Where(i => i.UnitId.HasValue && i.UnitId != Guid.Empty)
            .Select(i => i.UnitId!.Value).Distinct().ToList();
        var allProductUnits = await db.PosProductUnits.AsNoTracking()
            .Where(u => productIds.Contains(u.ProductId) && u.StoreId == storeId
                && u.Deleted == null && u.IsDirectSale)
            .ToListAsync();
        var units = unitIds.Count == 0
            ? new Dictionary<Guid, PosProductUnit>()
            : allProductUnits.Where(u => unitIds.Contains(u.Id))
                .ToDictionary(u => u.Id);
        var unitsByProduct = allProductUnits.GroupBy(u => u.ProductId)
            .ToDictionary(g => g.Key, g => g.ToList());

        var toppingCatalog = await LoadToppingCatalogAsync(storeId, productIds);

        var resolved = new List<ResolvedQrLine>();
        foreach (var item in rawItems)
        {
            if (!byId.TryGetValue(item.ProductId, out var p))
                return BadRequest(AppResponse<object>.Fail("Có món không bán được trên QR"));
            if (!PosQrMenuService.IsProductAllowed(p.Id, menuMap, useCustomMenu, isOnline))
                return BadRequest(AppResponse<object>.Fail($"{p.Name} không có trong menu QR/online"));
            menuMap.TryGetValue(p.Id, out var menuItem);
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

            PosProductUnit? unit = null;
            var productUnits = unitsByProduct.GetValueOrDefault(p.Id) ?? [];
            var pickUnits = !hasVariants && productUnits.Count > 0
                ? (productUnits.Count > 1
                    ? productUnits
                    : productUnits.Where(u => !u.IsBaseUnit).ToList())
                : [];
            var hasUnits = pickUnits.Count > 0;
            if (hasUnits)
            {
                if (item.UnitId is not Guid uid || uid == Guid.Empty
                    || !units.TryGetValue(uid, out unit) || unit.ProductId != p.Id)
                    return BadRequest(AppResponse<object>.Fail($"Chọn size / đơn vị cho {p.Name}"));
            }
            else if (item.UnitId.HasValue && item.UnitId != Guid.Empty)
                return BadRequest(AppResponse<object>.Fail($"{p.Name} không có đơn vị đó"));

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
            var unitPrice = variant != null
                ? PosQrMenuService.ResolveVariantPrice(p, variant, menuItem)
                : unit != null
                    ? PosQrMenuService.ResolveUnitPrice(p, unit, menuItem)
                    : PosQrMenuService.ResolveProductPrice(p, menuItem);
            if (!settings.AllowNegativeStock && p.ProductType == PosProductType.Goods)
            {
                var avail = variant != null
                    ? variant.OnHandQty
                    : unit != null
                        ? QrUnitAvailQty(p, unit)
                        : (p.OnHandQty - p.ReservedQty);
                if (avail < qty)
                    return BadRequest(AppResponse<object>.Fail($"{p.Name} tạm hết"));
            }

            var note = string.IsNullOrWhiteSpace(item.Note) ? null : item.Note.Trim();
            if (note is { Length: > 200 }) note = note[..200];
            var toppingsJson = CanonicalToppingsJson(toppings);
            var extra = toppings.Sum(t => t.Price);
            var lineName = variant != null
                ? $"{p.Name} — {variant.Name}"
                : unit != null
                    ? $"{p.Name} — {unit.UnitName}"
                    : p.Name;
            resolved.Add(new ResolvedQrLine(
                p, variant, unit, qty, note, toppingsJson, extra, unitPrice, lineName));
        }

        var items = resolved
            .GroupBy(x => (x.Product.Id, VariantId: x.Variant?.Id, UnitId: x.Unit?.Id, x.ToppingsJson, Note: x.Note ?? ""))
            .Select(g =>
            {
                var first = g.First();
                return first with { Qty = Math.Min(20, g.Sum(x => x.Qty)) };
            })
            .ToList();

        if (isOnline)
            return await SubmitOnlineAsync(store, settings, items, dto, token, reqId);

        var lockOpts = QrOrderLockHelper.Parse(settings.ExtraJson);
        // Xác nhận đơn (mặc định tắt): ghi món nhưng không tự in / đánh dấu bếp.
        var needsConfirm = lockOpts.RequireOrderConfirmation;
        var autoPrint = settings.EnableQrOrderAutoPrint && !needsConfirm;
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
                    .FirstOrDefaultAsync(s => s.ResourceId == resource!.Id && s.Deleted == null
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
                        ResourceId = resource!.Id,
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
                        UnitId = item.Unit?.Id,
                        ProductName = item.LineName,
                        UnitName = item.Unit?.UnitName ?? p.BaseUnitName,
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

                // Giữ chỗ tồn cho món QR vừa thêm (cùng ReservedQty với draft thu ngân).
                if (added.Count > 0)
                {
                    var deltaInputs = added
                        .Select(a => (a.Product.Id, a.Qty, a.Line.VariantId, a.Line.UnitId, a.Line.ToppingsJson))
                        .ToList();
                    var reserveErr = await PosSaleStockHelper.SyncDraftStockReservationAsync(
                        db, storeId, [], deltaInputs, settings.AllowNegativeStock);
                    if (reserveErr != null)
                    {
                        await tx.RollbackAsync();
                        return BadRequest(AppResponse<object>.Fail(reserveErr));
                    }
                }

                await db.SaveChangesAsync();

                var subTotal = order.Lines.Where(l => l.Deleted == null).Sum(l => l.LineTotal);
                var total = Math.Max(0, subTotal - order.Discount);
                order.SubTotal = subTotal;
                order.Total = total;
                order.ResourceSessionId = session.Id;
                        order.ServiceResourceId = resource!.Id;
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
                printJobs = await EnqueueKitchenAsync(storeId, resource!, order, added, DateTime.UtcNow);
            }
            catch
            {
                // Đơn vẫn ghi — phiếu có thể thiếu nếu chưa gán máy in bếp.
            }
        }

        var tableName = TableLabel(resource!);
        PosFloorRealtimeHelper.Notify(hub, storeId, "qrOrder",
            orderId: order.Id, resourceId: resource!.Id, sessionId: session.Id,
            tableName: tableName,
            message: needsConfirm ? "needsConfirm" : null);

        var payload = new
        {
            ok = true,
            orderNo = order.OrderNo,
            addedLines = added.Count,
            printJobs,
            autoPrint,
            needsConfirm,
            message = needsConfirm
                ? "Đã gửi — chờ thu ngân xác nhận trước khi in bếp"
                : autoPrint
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
        var ctx = await RequireDineInAsync(token);
        if (ctx.Error != null) return ctx.Error;
        var store = ctx.Ctx!.Store;
        var resource = ctx.Ctx.Resource!;
        var lockFail = await EnforceQrGuestAsync(store.Id, ctx.Ctx.Settings, dto?.Lat, dto?.Lng);
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
        var ctx = await RequireDineInAsync(token);
        if (ctx.Error != null) return ctx.Error;
        var store = ctx.Ctx!.Store;
        var resource = ctx.Ctx.Resource!;
        var lockFail = await EnforceQrGuestAsync(store.Id, ctx.Ctx.Settings, dto?.Lat, dto?.Lng);
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
        var ctx = await RequireDineInAsync(token);
        if (ctx.Error != null) return ctx.Error;
        var store = ctx.Ctx!.Store;
        var resource = ctx.Ctx.Resource!;
        var lockFail = await EnforceQrGuestAsync(store.Id, ctx.Ctx.Settings, dto?.Lat, dto?.Lng);
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

    public class QrMenuSaveDto
    {
        public bool UseCustomMenu { get; set; }
        public List<QrMenuSaveItemDto>? Items { get; set; }
    }

    public class QrMenuSaveItemDto
    {
        public Guid ProductId { get; set; }
        public decimal? QrPrice { get; set; }
        public bool ShowOnTable { get; set; } = true;
        public bool ShowOnOnline { get; set; } = true;
        public int SortOrder { get; set; }
    }

    [HttpGet("menu")]
    [RequireModulePermission("PosQrOrder", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetMenuConfig(CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var settings = await db.PosStoreSellSettings.AsNoTracking()
            .FirstOrDefaultAsync(s => s.StoreId == storeId && s.Deleted == null, ct);
        var (useCustom, items, catalog) = await qrMenu.LoadAdminAsync(storeId, settings?.ExtraJson, ct);
        return Ok(AppResponse<object>.Success(new
        {
            useCustomMenu = useCustom,
            items,
            catalog,
        }));
    }

    [HttpPut("menu")]
    [RequireModulePermission("PosQrOrder", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> SaveMenuConfig(
        [FromBody] QrMenuSaveDto? dto, CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var settings = await db.PosStoreSellSettings.AsTracking()
            .FirstOrDefaultAsync(s => s.StoreId == storeId && s.Deleted == null, ct);
        if (settings == null)
            return BadRequest(AppResponse<object>.Fail("Chưa có thiết lập bán hàng POS"));
        var rawItems = dto?.Items ?? [];
        if (dto?.UseCustomMenu == true && rawItems.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Thêm ít nhất một món vào menu QR/online"));
        var saveItems = rawItems
            .Where(x => x.ProductId != Guid.Empty)
            .Select((x, i) => new PosQrMenuSaveItem(
                x.ProductId,
                x.QrPrice,
                x.ShowOnTable,
                x.ShowOnOnline,
                x.SortOrder > 0 ? x.SortOrder : i + 1))
            .ToList();
        await qrMenu.SaveAsync(storeId, settings, dto?.UseCustomMenu == true, saveItems,
            CurrentUserEmail, ct);
        var (useCustom, items, catalog) = await qrMenu.LoadAdminAsync(storeId, settings.ExtraJson, ct);
        return Ok(AppResponse<object>.Success(new
        {
            useCustomMenu = useCustom,
            items,
            catalog,
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

        var onlineToken = (lockOpt.OnlineToken ?? "").Trim();
        if (lockOpt.EnableOnline && onlineToken.Length < 8 && settings != null)
        {
            var tracked = await db.PosStoreSellSettings.AsTracking()
                .FirstOrDefaultAsync(s => s.Id == settings.Id);
            if (tracked != null)
            {
                onlineToken = NewToken();
                tracked.ExtraJson = QrOrderLockHelper.MergeOnline(tracked.ExtraJson, true, onlineToken);
                tracked.UpdatedAt = DateTime.UtcNow;
                await db.SaveChangesAsync();
            }
        }

        var urlBase = PublicBase();
        var store = await db.Stores.AsNoTracking()
            .FirstOrDefaultAsync(s => s.Id == storeId);
        var brand = QrOrderLockHelper.ParseBrand(settings?.ExtraJson);
        return Ok(AppResponse<object>.Success(new
        {
            enabled,
            autoPrintKitchen = autoPrint,
            requireOpenSession = lockOpt.RequireOpenSession,
            requireGeofence = lockOpt.RequireGeofence,
            requireOrderConfirmation = lockOpt.RequireOrderConfirmation,
            geoConfigured,
            publicBaseUrl = urlBase,
            storeName = store?.Name ?? "",
            storePhone = store?.Phone ?? "",
            storeAddress = store?.Address ?? "",
            storeProvince = store?.Province ?? "",
            logoUrl = PublicMediaUrl(urlBase, brand.LogoUrl),
            defaultLogoUrl = $"{urlBase.TrimEnd('/')}/api/pos/qr-order/brand/default-logo",
            banners = brand.Banners.Select(b => PublicMediaUrl(urlBase, b)).Where(x => x != null),
            enableOnline = lockOpt.EnableOnline,
            onlineToken = onlineToken,
            onlineUrl = string.IsNullOrWhiteSpace(onlineToken) ? null : QrUrl(urlBase, onlineToken),
            onlineAutoConfirm = lockOpt.OnlineAutoConfirm,
            onlineAutoPrintKitchen = lockOpt.OnlineAutoPrintKitchen,
            onlineAutoPay = lockOpt.OnlineAutoPay,
            onlineAutoPrintProvisional = lockOpt.OnlineAutoPrintProvisional,
            onlineAutoCreateShipment = lockOpt.OnlineAutoCreateShipment,
            onlineDefaultCarrierCode = lockOpt.OnlineDefaultCarrierCode ?? "",
            storeZalo = lockOpt.StoreZalo ?? store?.Phone ?? "",
            useCustomMenu = lockOpt.UseCustomMenu,
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

    [HttpPost("online")]
    [RequireModulePermission("PosQrOrder", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> SetOnline([FromBody] QrOnlineToggleDto? dto)
    {
        var storeId = RequiredStoreId;
        var s = await db.PosStoreSellSettings.AsTracking()
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.Deleted == null);
        if (s == null)
            return BadRequest(AppResponse<object>.Fail("Thiếu thiết lập POS"));
        var enable = dto?.Enabled != false;
        var opt = QrOrderLockHelper.Parse(s.ExtraJson);
        var token = (opt.OnlineToken ?? "").Trim();
        if (enable && token.Length < 8)
            token = NewToken();
        if (dto?.Rotate == true)
            token = NewToken();
        s.ExtraJson = QrOrderLockHelper.MergeOnline(s.ExtraJson, enable, token);
        s.UpdatedAt = DateTime.UtcNow;
        s.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync();
        var urlBase = PublicBase();
        return Ok(AppResponse<object>.Success(new
        {
            enableOnline = enable,
            onlineToken = token,
            onlineUrl = enable && !string.IsNullOrWhiteSpace(token) ? QrUrl(urlBase, token) : null,
        }));
    }

    public class QrOnlineToggleDto
    {
        public bool? Enabled { get; set; }
        public bool? Rotate { get; set; }
    }

    public class QrOnlineStatusDto
    {
        public string? Status { get; set; }
        /// <summary>Giao nội bộ thay vì tạo AWB hãng (khi chuyển shipping).</summary>
        public bool? InternalDelivery { get; set; }
    }

    public class QrOnlineCompleteDto
    {
        public string? PaymentMethod { get; set; }
        public decimal? PaidAmount { get; set; }
    }

    public class QrOnlineShipmentDto
    {
        public string? CarrierCode { get; set; }
        public int? WeightGrams { get; set; }
        public int? LengthCm { get; set; }
        public int? WidthCm { get; set; }
        public int? HeightCm { get; set; }
        public decimal? CodAmount { get; set; }
        public string? ServiceCode { get; set; }
        public string? Note { get; set; }
        public string? ShipFeePayer { get; set; }
        public decimal? FixedShipFee { get; set; }
    }

    public class QrOnlineLookupDto
    {
        public string? Phone { get; set; }
    }

    [HttpGet("online-orders")]
    [RequireModulePermission("PosQrOrder", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> ListOnlineOrders(
        [FromQuery] string? status = null,
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null,
        [FromQuery] string? q = null,
        [FromQuery] Guid? productId = null)
    {
        var storeId = RequiredStoreId;
        var statusFilter = string.IsNullOrWhiteSpace(status)
            ? null
            : QrOnlineOrderStatuses.Normalize(status);
        var since = from ?? DateTime.UtcNow.AddDays(-45);
        var until = (to ?? DateTime.UtcNow).Date.AddDays(1).AddTicks(-1);
        if (until < since) until = since.AddDays(1);

        var query = db.PosSaleOrders.AsNoTracking()
            .Include(o => o.Lines)
            .Where(o => o.StoreId == storeId && o.Deleted == null
                && o.SalesChannel == QrOnlineOrderStatuses.Channel
                && o.CreatedAt >= since && o.CreatedAt <= until);
        if (statusFilter == QrOnlineOrderStatuses.Pending)
        {
            query = query.Where(o => o.Status != PosSaleOrderStatus.Cancelled
                && (o.DeliveryStatus == null
                    || o.DeliveryStatus == ""
                    || o.DeliveryStatus == QrOnlineOrderStatuses.Pending));
        }
        else if (statusFilter != null)
        {
            query = query.Where(o => o.DeliveryStatus == statusFilter);
        }

        if (productId.HasValue && productId != Guid.Empty)
        {
            query = query.Where(o => o.Lines.Any(l => l.Deleted == null && l.ProductId == productId));
        }

        if (!string.IsNullOrWhiteSpace(q))
        {
            var s = q.Trim().ToLower();
            query = query.Where(o => o.OrderNo.ToLower().Contains(s)
                || (o.CustomerName ?? "").ToLower().Contains(s)
                || (o.DeliveryPhone ?? "").Contains(s)
                || (o.DeliveryAddress ?? "").ToLower().Contains(s)
                || o.Lines.Any(l => l.Deleted == null && l.ProductName.ToLower().Contains(s)));
        }

        var list = await query.OrderByDescending(o => o.CreatedAt).Take(200).ToListAsync();
        var productFilters = list
            .SelectMany(o => o.Lines.Where(l => l.Deleted == null))
            .GroupBy(l => l.ProductId)
            .Select(g =>
            {
                var raw = g.First().ProductName;
                var dash = raw.IndexOf(" — ", StringComparison.Ordinal);
                var name = dash > 0 ? raw[..dash].Trim() : raw.Trim();
                return new { id = g.Key, name };
            })
            .OrderBy(p => p.name)
            .ToList();

        return Ok(AppResponse<object>.Success(new
        {
            statuses = QrOnlineOrderStatuses.All.Select(c => new
            {
                code = c,
                label = QrOnlineOrderStatuses.Label(c),
            }),
            productFilters,
            from = since,
            to = until,
            orders = list.Select(MapOnlineOrder),
        }));
    }

    [HttpPost("online-orders/{id:guid}/status")]
    [RequireModulePermission("PosQrOrder", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> SetOnlineOrderStatus(
        Guid id, [FromBody] QrOnlineStatusDto? dto)
    {
        var storeId = RequiredStoreId;
        var next = QrOnlineOrderStatuses.Normalize(dto?.Status);
        if (!QrOnlineOrderStatuses.IsValid(next))
            return BadRequest(AppResponse<object>.Fail("Trạng thái không hợp lệ"));

        var order = await db.PosSaleOrders.AsTracking()
            .Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId && o.Deleted == null
                && o.SalesChannel == QrOnlineOrderStatuses.Channel);
        if (order == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy đơn online"));

        var prev = QrOnlineOrderStatuses.Normalize(order.DeliveryStatus);
        if (prev == next)
            return Ok(AppResponse<object>.Success(MapOnlineOrder(order)));

        if (QrOnlineOrderStatuses.IsTerminal(prev) && next != prev)
            return BadRequest(AppResponse<object>.Fail(
                "Đơn đã kết thúc — không đổi trạng thái nữa"));

        var now = DateTime.UtcNow;
        order.DeliveryStatus = next;
        order.UpdatedAt = now;
        order.UpdatedBy = CurrentUserEmail;

        if (next == QrOnlineOrderStatuses.Cancelled)
        {
            if (order.Status == PosSaleOrderStatus.Draft)
            {
                var prior = order.Lines.Where(l => l.Deleted == null)
                    .Select(l => (l.ProductId, l.Qty, l.VariantId, l.UnitId, l.ToppingsJson))
                    .ToList();
                if (prior.Count > 0)
                {
                    var settings = await db.PosStoreSellSettings.AsNoTracking()
                        .FirstOrDefaultAsync(s => s.StoreId == storeId && s.Deleted == null);
                    await PosSaleStockHelper.SyncDraftStockReservationAsync(
                        db, storeId, prior, [], settings?.AllowNegativeStock == true);
                }
                order.Status = PosSaleOrderStatus.Cancelled;
            }
            else if (order.Status == PosSaleOrderStatus.Completed)
            {
                // Đã thanh toán / trừ kho — hủy online phải hoàn kho + gỡ DT như Hủy hóa đơn.
                var stockFullyReversed =
                    await PosSaleStockHelper.IsSaleStockFullyReversedAsync(db, storeId, order);
                if (!stockFullyReversed)
                {
                    var reversed = await PosSaleStockHelper.ReverseSaleOrderAsync(
                        db, storeId, order, CurrentUserEmail);
                    if (!reversed)
                    {
                        stockFullyReversed =
                            await PosSaleStockHelper.IsSaleStockFullyReversedAsync(db, storeId, order);
                        if (!stockFullyReversed)
                            return BadRequest(AppResponse<object>.Fail(
                                "Không hoàn được kho khi hủy đơn đã thanh toán"));
                    }
                }

                await PosSaleStockHelper.ReverseCustomerOnSaleCancelAsync(db, storeId, order);
                await PosCustomerFinanceHelper.ReversePointsOnSaleCancelAsync(
                    db, storeId, order, CurrentUserEmail);
                if (order.VoucherId.HasValue)
                {
                    var vch = await db.PosVouchers.AsTracking()
                        .FirstOrDefaultAsync(v => v.Id == order.VoucherId && v.StoreId == storeId);
                    if (vch != null && vch.UsedCount > 0)
                    {
                        vch.UsedCount -= 1;
                        vch.UpdatedAt = now;
                    }
                }
                await PosFinanceSyncHelper.ReverseSaleOnCancelAsync(db, order);
                await PosSaleWarrantyHelper.VoidOrderAsync(db, storeId, order.Id, CurrentUserEmail);
                order.Status = PosSaleOrderStatus.Cancelled;
            }
        }

        if (next == QrOnlineOrderStatuses.Delivered)
            order.DeliveryDate ??= now;

        var printJobs = 0;
        // Luồng mới: pending → preparing (= «Xác nhận đơn»). Giữ pending → confirmed (cũ).
        if (prev == QrOnlineOrderStatuses.Pending
            && (next == QrOnlineOrderStatuses.Confirmed || next == QrOnlineOrderStatuses.Preparing))
        {
            var settings = await db.PosStoreSellSettings.AsNoTracking()
                .FirstOrDefaultAsync(s => s.StoreId == storeId && s.Deleted == null);
            var opt = QrOrderLockHelper.Parse(settings?.ExtraJson);
            if (opt.OnlineAutoPrintKitchen)
            {
                try
                {
                    printJobs = await TryEnqueueOnlineKitchenAsync(storeId, order.Id, DateTime.UtcNow);
                }
                catch
                {
                    // Đơn vẫn cập nhật — phiếu bếp có thể in lại thủ công.
                }
            }
            await ApplyOnlineConfirmSideEffectsAsync(
                storeId, order, opt, HttpContext.RequestAborted);
        }

        if (next == QrOnlineOrderStatuses.Shipping && prev != QrOnlineOrderStatuses.Shipping)
        {
            var settings = await db.PosStoreSellSettings.AsNoTracking()
                .FirstOrDefaultAsync(s => s.StoreId == storeId && s.Deleted == null);
            var opt = QrOrderLockHelper.Parse(settings?.ExtraJson);
            var useInternal = dto?.InternalDelivery == true
                || PosOnlineOrderHelper.IsInternalCarrier(opt.OnlineDefaultCarrierCode);
            if (useInternal)
            {
                PosOnlineOrderHelper.MarkInternalDelivery(order, CurrentUserEmail);
            }
            else if (opt.OnlineAutoCreateShipment
                     && !string.IsNullOrWhiteSpace(opt.OnlineDefaultCarrierCode)
                     && string.IsNullOrWhiteSpace(order.DeliveryTrackingCode))
            {
                try
                {
                    var (ok, tracking, msg) = await PosOnlineOrderHelper.TryCreateShipmentAsync(
                        shipping, db, storeId, order, opt.OnlineDefaultCarrierCode!,
                        CurrentUserEmail, HttpContext.RequestAborted);
                    if (!ok && !string.IsNullOrWhiteSpace(msg))
                    { /* vận đơn thất bại — tạo lại thủ công */ }
                    else if (ok && !string.IsNullOrWhiteSpace(tracking))
                    { /* đã tạo vận đơn */ }
                }
                catch
                {
                    // Trạng thái vẫn cập nhật — tạo vận đơn lại thủ công.
                }
            }
        }

        await db.SaveChangesAsync();
        PosFloorRealtimeHelper.Notify(hub, storeId, "qrOnlineStatus",
            orderId: order.Id, tableName: "Online",
            message: $"{order.OrderNo} · {QrOnlineOrderStatuses.Label(next)}");

        return Ok(AppResponse<object>.Success(MapOnlineOrder(order)));
    }

    [HttpPost("online-orders/{id:guid}/complete")]
    [RequireModulePermission("PosQrOrder", ModulePermissionAction.Approve)]
    public async Task<ActionResult<AppResponse<object>>> CompleteOnlineOrder(
        Guid id, [FromBody] QrOnlineCompleteDto? dto)
    {
        var storeId = RequiredStoreId;
        var order = await db.PosSaleOrders.AsTracking()
            .Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId && o.Deleted == null
                && o.SalesChannel == QrOnlineOrderStatuses.Channel);
        if (order == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy đơn online"));

        var (ok, err) = await PosOnlineOrderHelper.TryCompleteAsCodAsync(
            db, storeId, order, CurrentUserEmail, HttpContext.RequestAborted);
        if (!ok)
            return BadRequest(AppResponse<object>.Fail(err ?? "Không hoàn thành được đơn"));

        if (dto?.PaidAmount is > 0)
            order.PaidAmount = dto.PaidAmount.Value;
        if (!string.IsNullOrWhiteSpace(dto?.PaymentMethod))
            order.PaymentMethod = dto.PaymentMethod!.Trim();
        await db.SaveChangesAsync();

        PosFloorRealtimeHelper.Notify(hub, storeId, "saleCompleted",
            orderId: order.Id, tableName: "Online", message: order.OrderNo);

        return Ok(AppResponse<object>.Success(MapOnlineOrder(order)));
    }

    [HttpPost("online-orders/{id:guid}/shipment")]
    [RequireModulePermission("PosQrOrder", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> CreateOnlineShipment(
        Guid id, [FromBody] QrOnlineShipmentDto? dto)
    {
        var storeId = RequiredStoreId;
        var order = await db.PosSaleOrders.AsTracking()
            .Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId && o.Deleted == null
                && o.SalesChannel == QrOnlineOrderStatuses.Channel);
        if (order == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy đơn online"));

        var code = (dto?.CarrierCode ?? "").Trim();
        if (code.Length == 0)
            return BadRequest(AppResponse<object>.Fail("Chọn đơn vị vận chuyển"));

        var (ok, tracking, msg) = await PosOnlineOrderHelper.TryCreateShipmentAsync(
            shipping, db, storeId, order, code, CurrentUserEmail, HttpContext.RequestAborted,
            weightGrams: dto?.WeightGrams,
            lengthCm: dto?.LengthCm,
            widthCm: dto?.WidthCm,
            heightCm: dto?.HeightCm,
            codAmount: dto?.CodAmount,
            serviceCode: dto?.ServiceCode,
            note: dto?.Note,
            shipFeePayer: dto?.ShipFeePayer,
            fixedShipFee: dto?.FixedShipFee);
        if (!ok)
            return BadRequest(AppResponse<object>.Fail(msg ?? "Không tạo được vận đơn"));

        await db.Entry(order).ReloadAsync();

        if (QrOnlineOrderStatuses.Normalize(order.DeliveryStatus) is var st
            && st != QrOnlineOrderStatuses.Shipping
            && st != QrOnlineOrderStatuses.Delivered
            && !QrOnlineOrderStatuses.IsTerminal(st))
        {
            order.DeliveryStatus = QrOnlineOrderStatuses.Shipping;
        }
        await db.SaveChangesAsync();

        PosFloorRealtimeHelper.Notify(hub, storeId, "qrOnlineStatus",
            orderId: order.Id, tableName: "Online",
            message: $"{order.OrderNo} · vận đơn {(tracking ?? code)}");

        return Ok(AppResponse<object>.Success(new
        {
            order = MapOnlineOrder(order),
            trackingCode = tracking,
            message = msg,
        }));
    }

    /// <summary>
    /// Xóa mềm đơn online đã hủy (không còn hiện danh sách). Chỉ khi DeliveryStatus/Status = cancelled.
    /// Nếu còn Status=Completed (bug cũ: hủy giao nhưng chưa hoàn kho) → hoàn kho/DT rồi mới xóa.
    /// </summary>
    [HttpDelete("online-orders/{id:guid}")]
    [RequireModulePermission("PosQrOrder", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> DeleteCancelledOnlineOrder(Guid id)
    {
        var storeId = RequiredStoreId;
        var order = await db.PosSaleOrders.AsTracking()
            .Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId && o.Deleted == null
                && o.SalesChannel == QrOnlineOrderStatuses.Channel);
        if (order == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy đơn online"));

        var delivery = QrOnlineOrderStatuses.Normalize(order.DeliveryStatus);
        var cancelled = order.Status == PosSaleOrderStatus.Cancelled
            || delivery == QrOnlineOrderStatuses.Cancelled;
        if (!cancelled)
            return BadRequest(AppResponse<object>.Fail(
                "Chỉ xóa được đơn online đã hủy"));

        var now = DateTime.UtcNow;

        // Hybrid: DeliveryStatus=cancelled nhưng Status vẫn Completed → hoàn kho/DT trước.
        if (order.Status == PosSaleOrderStatus.Completed)
        {
            var stockFullyReversed =
                await PosSaleStockHelper.IsSaleStockFullyReversedAsync(db, storeId, order);
            if (!stockFullyReversed)
            {
                var reversed = await PosSaleStockHelper.ReverseSaleOrderAsync(
                    db, storeId, order, CurrentUserEmail);
                if (!reversed)
                {
                    stockFullyReversed =
                        await PosSaleStockHelper.IsSaleStockFullyReversedAsync(db, storeId, order);
                    if (!stockFullyReversed)
                        return BadRequest(AppResponse<object>.Fail(
                            "Không hoàn được kho — không xóa đơn đã thanh toán"));
                }
            }

            await PosSaleStockHelper.ReverseCustomerOnSaleCancelAsync(db, storeId, order);
            await PosCustomerFinanceHelper.ReversePointsOnSaleCancelAsync(
                db, storeId, order, CurrentUserEmail);
            if (order.VoucherId.HasValue)
            {
                var vch = await db.PosVouchers.AsTracking()
                    .FirstOrDefaultAsync(v => v.Id == order.VoucherId && v.StoreId == storeId);
                if (vch != null && vch.UsedCount > 0)
                {
                    vch.UsedCount -= 1;
                    vch.UpdatedAt = now;
                }
            }
            await PosFinanceSyncHelper.ReverseSaleOnCancelAsync(db, order);
            await PosSaleWarrantyHelper.VoidOrderAsync(db, storeId, order.Id, CurrentUserEmail);
            order.Status = PosSaleOrderStatus.Cancelled;
            order.DeliveryStatus = QrOnlineOrderStatuses.Cancelled;
            order.UpdatedAt = now;
            order.UpdatedBy = CurrentUserEmail;
            await db.SaveChangesAsync();
        }

        var deleted = await db.PosSaleOrders
            .Where(o => o.Id == id && o.StoreId == storeId && o.Deleted == null
                && o.SalesChannel == QrOnlineOrderStatuses.Channel)
            .ExecuteUpdateAsync(setters => setters
                .SetProperty(o => o.Deleted, now)
                .SetProperty(o => o.UpdatedAt, now)
                .SetProperty(o => o.UpdatedBy, CurrentUserEmail));

        if (deleted == 0)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy đơn hoặc đã xóa"));

        PosFloorRealtimeHelper.Notify(hub, storeId, "qrOnlineDeleted",
            orderId: id, tableName: "Online", message: order.OrderNo);

        return Ok(AppResponse<object>.Success(new { deleted = true, orderNo = order.OrderNo }));
    }

    [HttpGet("vn-address/units")]
    [AllowAnonymous]
    public IActionResult VnAddressUnits()
    {
        var asm = typeof(PosQrTableOrderController).Assembly;
        using var stream = asm.GetManifestResourceStream("Sbox.VnAdminUnits.json");
        if (stream != null)
        {
            using var ms = new MemoryStream();
            stream.CopyTo(ms);
            var bytes = ms.ToArray();
            return File(bytes, "application/json; charset=utf-8");
        }
        var path = Path.Combine(env.WebRootPath, "data", "vn-admin-units.json");
        if (System.IO.File.Exists(path))
            return PhysicalFile(path, "application/json; charset=utf-8");
        return NotFound(AppResponse<object>.Fail("Thiếu dữ liệu địa chỉ"));
    }

    [HttpPost("{token}/my-orders")]
    [AllowAnonymous]
    public async Task<ActionResult<AppResponse<object>>> GuestMyOrders(
        string token, [FromBody] QrOnlineLookupDto? dto)
    {
        var ctx = await ResolveAnyAsync(token);
        if (ctx.Error != null) return ctx.Error;
        if (!ctx.Ctx!.IsOnline)
            return BadRequest(AppResponse<object>.Fail(
                "Chỉ tra cứu đơn trên link đặt hàng online"));

        var digits = new string((dto?.Phone ?? "").Where(char.IsDigit).ToArray());
        if (digits.Length is < 8 or > 15)
            return BadRequest(AppResponse<object>.Fail("Nhập số điện thoại đã đặt hàng"));

        var rateKey = $"qr-lookup:{token}:{digits}";
        var n = cache.GetOrCreate(rateKey, e =>
        {
            e.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(1);
            e.Size = 1;
            return 0;
        });
        if (n >= 12)
            return BadRequest(AppResponse<object>.Fail("Tra cứu quá nhanh — đợi một phút"));
        cache.Set(rateKey, n + 1, new MemoryCacheEntryOptions
        {
            AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(1),
            Size = 1,
        });

        var storeId = ctx.Ctx.Store.Id;
        var since = DateTime.UtcNow.AddDays(-30);
        var orders = await db.PosSaleOrders.AsNoTracking()
            .Include(o => o.Lines)
            .Where(o => o.StoreId == storeId && o.Deleted == null
                && o.SalesChannel == QrOnlineOrderStatuses.Channel
                && o.CreatedAt >= since
                && o.DeliveryPhone == digits)
            .OrderByDescending(o => o.CreatedAt)
            .Take(20)
            .ToListAsync();

        return Ok(AppResponse<object>.Success(new
        {
            phone = digits,
            orders = orders.Select(MapOnlineOrder),
        }));
    }

    static object MapOnlineOrder(PosSaleOrder o)
    {
        var status = QrOnlineOrderStatuses.Normalize(o.DeliveryStatus);
        if (o.Status == PosSaleOrderStatus.Cancelled)
            status = QrOnlineOrderStatuses.Cancelled;
        var lines = o.Lines.Where(l => l.Deleted == null)
            .Select(l => new
            {
                productId = l.ProductId,
                name = l.ProductName,
                qty = l.Qty,
                unitPrice = l.UnitPrice,
                lineTotal = l.LineTotal,
                note = l.LineNote,
            })
            .ToList();
        var isPaid = o.Status == PosSaleOrderStatus.Completed;
        return new
        {
            id = o.Id,
            orderNo = o.OrderNo,
            status,
            statusLabel = QrOnlineOrderStatuses.Label(status),
            customerName = o.CustomerName,
            phone = o.DeliveryPhone,
            address = o.DeliveryAddress,
            note = o.Note,
            subTotal = o.SubTotal,
            total = o.Total,
            paidAmount = o.PaidAmount,
            isPaid,
            canPay = !isPaid && o.Status == PosSaleOrderStatus.Draft,
            canPrintProvisional = o.Status == PosSaleOrderStatus.Draft,
            createdAt = o.CreatedAt,
            updatedAt = o.UpdatedAt,
            saleStatus = o.Status.ToString(),
            trackingCode = o.DeliveryTrackingCode,
            deliveryPartner = o.DeliveryPartner,
            deliveryCarrierCode = o.DeliveryCarrierCode,
            lines,
        };
    }

    async Task<string?> ApplyOnlineConfirmSideEffectsAsync(
        Guid storeId,
        PosSaleOrder order,
        QrOrderLockHelper.Options opt,
        CancellationToken ct)
    {
        string? msg = null;
        if (opt.OnlineAutoPay && order.Status == PosSaleOrderStatus.Draft)
        {
            var (ok, err) = await PosOnlineOrderHelper.TryCompleteAsCodAsync(
                db, storeId, order, CurrentUserEmail, ct);
            if (ok)
                msg = "Đã tự hoàn thành đơn (COD)";
            else if (!string.IsNullOrWhiteSpace(err))
                msg = err;
        }
        return msg;
    }

    sealed class QrTableCtx(Store Store, PosStoreSellSettings Settings, PosServiceResource? Resource)
    {
        public Store Store { get; } = Store;
        public PosStoreSellSettings Settings { get; } = Settings;
        public PosServiceResource? Resource { get; } = Resource;
        public bool IsOnline => Resource == null;
    }

    sealed record QrToppingPick(Guid Id, string Name, decimal Price);

    sealed record ResolvedQrLine(
        PosProduct Product,
        PosProductVariant? Variant,
        PosProductUnit? Unit,
        decimal Qty,
        string? Note,
        string? ToppingsJson,
        decimal ToppingExtra,
        decimal UnitPrice,
        string LineName);

    async Task<ActionResult<AppResponse<object>>> SubmitOnlineAsync(
        Store store,
        PosStoreSellSettings settings,
        List<ResolvedQrLine> items,
        QrOrderSubmitDto? dto,
        string token,
        string reqId)
    {
        var name = (dto?.GuestName ?? "").Trim();
        var phone = (dto?.GuestPhone ?? "").Trim();
        var province = (dto?.GuestProvince ?? "").Trim();
        var ward = (dto?.GuestWard ?? "").Trim();
        var detail = (dto?.GuestAddressDetail ?? "").Trim();
        var address = (dto?.GuestAddress ?? "").Trim();
        if (address.Length < 5)
        {
            address = string.Join(", ",
                new[] { detail, ward, province }.Where(x => x.Length > 0));
        }
        var extraNote = (dto?.GuestNote ?? "").Trim();
        if (name.Length is < 2 or > 80)
            return BadRequest(AppResponse<object>.Fail("Nhập họ tên người nhận (2–80 ký tự)"));
        var digits = new string(phone.Where(char.IsDigit).ToArray());
        if (digits.Length is < 8 or > 15)
            return BadRequest(AppResponse<object>.Fail("Nhập số điện thoại liên hệ"));
        if (province.Length < 2)
            return BadRequest(AppResponse<object>.Fail("Chọn tỉnh / thành phố"));
        if (ward.Length < 2)
            return BadRequest(AppResponse<object>.Fail("Chọn phường / xã"));
        if (detail.Length is < 3 or > 300)
            return BadRequest(AppResponse<object>.Fail("Nhập địa chỉ chi tiết (số nhà, ngõ, tên đường)"));
        if (address.Length is < 8 or > 400)
            address = string.Join(", ", new[] { detail, ward, province });
        if (dto?.Lat is double glat && dto.Lng is double glng
            && glat is >= -90 and <= 90 && glng is >= -180 and <= 180)
        {
            var geo = $"GPS {glat:F5},{glng:F5}";
            extraNote = string.IsNullOrWhiteSpace(extraNote) ? geo : $"{extraNote} · {geo}";
        }
        if (extraNote.Length > 200) extraNote = extraNote[..200];

        var storeId = store.Id;
        var lockOpt = QrOrderLockHelper.Parse(settings.ExtraJson);
        var autoConfirm = lockOpt.OnlineAutoConfirm;
        var autoPrintKitchen = lockOpt.OnlineAutoPrintKitchen;
        var added = new List<(PosSaleOrderLine Line, decimal Qty, PosProduct Product)>();
        PosSaleOrder? order = null;
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
                var orderNo = await PosSaleStockHelper.NextOrderNoAsync(db, storeId, now);
                var note = "QR online — quán gọi lại xác nhận.";
                if (!string.IsNullOrWhiteSpace(extraNote))
                    note = $"{note} {extraNote}";
                order = new PosSaleOrder
                {
                    Id = Guid.NewGuid(),
                    StoreId = storeId,
                    OrderNo = orderNo,
                    Status = PosSaleOrderStatus.Draft,
                    PaymentMethod = "Liên hệ",
                    CustomerName = name,
                    IsDelivery = true,
                    DeliveryAddress = address,
                    DeliveryProvince = province,
                    DeliveryWard = ward,
                    DeliveryPhone = digits,
                    DeliveryStatus = autoConfirm
                        ? QrOnlineOrderStatuses.Confirmed
                        : QrOnlineOrderStatuses.Pending,
                    Note = note,
                    SaleDate = now,
                    SalesChannel = "QR online",
                    IsActive = true,
                    CreatedBy = "QR online",
                    CreatedAt = now,
                };
                db.PosSaleOrders.Add(order);
                foreach (var item in items)
                {
                    var p = item.Product;
                    var line = new PosSaleOrderLine
                    {
                        Id = Guid.NewGuid(),
                        StoreId = storeId,
                        SaleOrderId = order.Id,
                        ProductId = p.Id,
                        ProductName = item.LineName,
                        UnitName = item.Unit?.UnitName ?? p.BaseUnitName,
                        VariantId = item.Variant?.Id,
                        UnitId = item.Unit?.Id,
                        Qty = item.Qty,
                        UnitPrice = item.UnitPrice,
                        LineTotal = Math.Round((item.UnitPrice + item.ToppingExtra) * item.Qty, 0, MidpointRounding.AwayFromZero),
                        LineNote = item.Note,
                        ToppingsJson = item.ToppingsJson,
                        KitchenSentQty = 0,
                        IsActive = true,
                        CreatedBy = "QR online",
                        CreatedAt = now,
                    };
                    db.PosSaleOrderLines.Add(line);
                    order.Lines.Add(line);
                    added.Add((line, item.Qty, p));
                }

                if (added.Count > 0)
                {
                    var deltaInputs = added
                        .Select(a => (a.Product.Id, a.Qty, a.Line.VariantId, a.Line.UnitId, a.Line.ToppingsJson))
                        .ToList();
                    var reserveErr = await PosSaleStockHelper.SyncDraftStockReservationAsync(
                        db, storeId, [], deltaInputs, settings.AllowNegativeStock);
                    if (reserveErr != null)
                    {
                        await tx.RollbackAsync();
                        return BadRequest(AppResponse<object>.Fail(reserveErr));
                    }
                }

                await db.SaveChangesAsync();
                var subTotal = order.Lines.Where(l => l.Deleted == null).Sum(l => l.LineTotal);
                order.SubTotal = subTotal;
                order.Total = Math.Max(0, subTotal - order.Discount);
                order.LockVersion = 1;
                order.UpdatedAt = now;
                order.UpdatedBy = "QR online";
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

        if (!saved || order == null)
            return Conflict(AppResponse<object>.Fail("Không tạo được đơn — gửi lại"));

        var printJobs = 0;
        if (autoPrintKitchen && autoConfirm)
        {
            try
            {
                printJobs = await TryEnqueueOnlineKitchenAsync(storeId, order.Id, DateTime.UtcNow);
            }
            catch
            {
                // Đơn vẫn lưu — kiểm tra máy in / Agent.
            }
        }

        if (autoConfirm)
        {
            try
            {
                await ApplyOnlineConfirmSideEffectsAsync(
                    storeId, order, lockOpt, HttpContext.RequestAborted);
                await db.SaveChangesAsync();
            }
            catch
            {
                // Đơn vẫn lưu — thanh toán thủ công trên POS.
            }
        }

        PosFloorRealtimeHelper.Notify(hub, storeId, "qrOnlineOrder",
            orderId: order.Id, tableName: "Online",
            message: $"{name} · {digits}");

        var orderTotal = added.Sum(x => x.Line.LineTotal);
        await PosNotificationHelper.NotifyQrOnlineOrderAsync(
            notificationService,
            db,
            storeId,
            order.Id,
            order.OrderNo,
            name,
            digits,
            orderTotal,
            HttpContext.RequestAborted);

        var finalStatus = QrOnlineOrderStatuses.Normalize(order.DeliveryStatus);
        var payload = new
        {
            ok = true,
            orderNo = order.OrderNo,
            addedLines = added.Count,
            printJobs,
            autoPrint = autoPrintKitchen && autoConfirm,
            needsConfirm = !autoConfirm,
            channel = "online",
            orderId = order.Id,
            onlineStatus = finalStatus,
            onlineStatusLabel = QrOnlineOrderStatuses.Label(finalStatus),
            message = autoConfirm
                ? (printJobs > 0
                    ? "Đã xác nhận đơn — phiếu bếp đã gửi in"
                    : autoPrintKitchen
                        ? "Đã xác nhận đơn — chưa in được phiếu bếp (kiểm tra máy in)"
                        : "Đã xác nhận đơn")
                : "Đã gửi đơn. Quán sẽ gọi lại để xác nhận.",
        };
        if (reqId.Length is > 8 and < 80)
            cache.Set($"qr-req:{token}:{reqId}", payload, new MemoryCacheEntryOptions
            {
                AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(10),
                Size = 1,
            });
        return Ok(AppResponse<object>.Success(payload));
    }

    async Task<(ActionResult<AppResponse<object>>? Error, QrTableCtx? Ctx)>
        RequireDineInAsync(string token)
    {
        var any = await ResolveAnyAsync(token);
        if (any.Error != null) return any;
        if (any.Ctx!.IsOnline)
            return (BadRequest(AppResponse<object>.Fail(
                "Đơn online — quán sẽ gọi lại, không dùng chức năng tại bàn")), null);
        return any;
    }

    async Task<(ActionResult<AppResponse<object>>? Error, QrTableCtx? Ctx)>
        ResolveAnyAsync(string token)
    {
        token = (token ?? "").Trim();
        if (token.Length is < 8 or > 32)
            return (NotFound(AppResponse<object>.Fail("Mã QR không hợp lệ")), null);

        var table = await ResolveTableAsync(token);
        if (table.Error == null && table.Ctx != null)
            return table;

        var hits = await db.PosStoreSellSettings.AsNoTracking()
            .Where(s => s.Deleted == null && s.ExtraJson != null && s.ExtraJson.Contains(token))
            .ToListAsync();
        foreach (var s in hits)
        {
            var opt = QrOrderLockHelper.Parse(s.ExtraJson);
            if (!opt.EnableOnline) continue;
            if (!string.Equals((opt.OnlineToken ?? "").Trim(), token, StringComparison.Ordinal))
                continue;
            var store = await db.Stores.AsNoTracking().FirstOrDefaultAsync(x => x.Id == s.StoreId);
            if (store == null) continue;
            return (null, new QrTableCtx(store, s, null));
        }

        return table.Error != null
            ? table
            : (NotFound(AppResponse<object>.Fail("Không tìm thấy mã QR")), null);
    }

    async Task<(ActionResult<AppResponse<object>>? Error, QrTableCtx? Ctx)>
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
        return (null, new QrTableCtx(store, settings, resource));
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

    async Task<object> BuildMenuAsync(Store store, PosServiceResource? resource, PosStoreSellSettings settings, bool online = false)
    {
        var useCustomMenu = PosQrMenuService.UseCustomMenu(settings.ExtraJson);
        var menuMap = await qrMenu.LoadMapAsync(store.Id);

        var products = await db.PosProducts.AsNoTracking()
            .Include(p => p.Category)
            .Where(p => p.StoreId == store.Id && p.Deleted == null && p.IsActive && p.IsDirectSale
                && !p.IsTopping
                && !p.RequiresSerial
                && !(p.ProductType == PosProductType.Service && p.ServiceBillingMode != PosServiceBillingMode.Flat))
            .OrderBy(p => p.SortOrder).ThenBy(p => p.Name)
            .ToListAsync();

        products = PosQrMenuService.FilterProducts(products, menuMap, useCustomMenu, online);

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

        var saleUnits = productIds.Count == 0
            ? []
            : await db.PosProductUnits.AsNoTracking()
                .Where(u => productIds.Contains(u.ProductId) && u.StoreId == store.Id
                    && u.Deleted == null && u.IsDirectSale)
                .OrderByDescending(u => u.IsBaseUnit)
                .ThenBy(u => u.ConversionRate)
                .ToListAsync();
        var unitsByProduct = saleUnits.GroupBy(u => u.ProductId)
            .ToDictionary(g => g.Key, g => g.ToList());

        var toppingCatalog = await LoadToppingCatalogGroupedAsync(store.Id, productIds);

        var cats = products
            .Where(p => p.CategoryId != null)
            .GroupBy(p => p.CategoryId!.Value)
            .Select(g => new { id = g.Key, name = g.First().Category?.Name ?? "Khác" })
            .OrderBy(c => c.name)
            .ToList();

        Guid? orderId = null;
        object? bill = null;
        PosSaleOrder? openOrder = null;
        decimal billPayable = 0;
        if (!online && resource != null)
        {
            var session = await db.PosResourceSessions.AsNoTracking()
                .Where(s => s.ResourceId == resource.Id && s.Deleted == null
                    && (s.Status == PosResourceSessionStatus.Open || s.Status == PosResourceSessionStatus.Paused))
                .OrderByDescending(s => s.StartedAt)
                .FirstOrDefaultAsync();
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
        }

        var lockOpt = QrOrderLockHelper.Parse(settings.ExtraJson);
        var tableOpen = openOrder != null;
        var geoConfigured = !online && await db.Geofences.AsNoTracking()
            .AnyAsync(g => g.StoreId == store.Id && g.Deleted == null && g.IsActive);
        var canOrder = online || !lockOpt.RequireOpenSession || tableOpen;
        string? lockMessage = canOrder
            ? null
            : "Thu ngân chưa mở bàn — chưa gọi món được";
        var lockInfo = new
        {
            requireOpenSession = online ? false : lockOpt.RequireOpenSession,
            tableOpen,
            requireGeofence = online ? false : lockOpt.RequireGeofence,
            geoConfigured,
            canOrder,
            message = lockMessage,
        };

        object? payment = null;
        if (!online && resource != null)
        {
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
        }

        var brand = QrOrderLockHelper.ParseBrand(settings.ExtraJson);
        var qrOpt = QrOrderLockHelper.Parse(settings.ExtraJson);
        var urlBase = PublicBase();
        return new
        {
            channel = online ? "online" : "table",
            storeName = store.Name,
            storePhone = store.Phone,
            storeZalo = qrOpt.StoreZalo ?? store.Phone,
            storeAddress = store.Address,
            storeProvince = store.Province,
            logoUrl = PublicMediaUrl(urlBase, brand.LogoUrl),
            defaultLogoUrl = $"{urlBase.TrimEnd('/')}/api/pos/qr-order/brand/default-logo",
            banners = brand.Banners.Select(b => PublicMediaUrl(urlBase, b)).Where(x => x != null),
            tableName = online ? "Đặt online" : resource?.Name,
            areaName = online ? null : resource?.Area?.Name,
            tableCode = online ? null : resource?.Code,
            autoPrintKitchen = settings.EnableQrOrderAutoPrint,
            useCustomMenu,
            categories = cats,
            products = products.Select(p =>
            {
                menuMap.TryGetValue(p.Id, out var menuItem);
                var pVars = variantsByProduct.GetValueOrDefault(p.Id) ?? [];
                var pUnits = unitsByProduct.GetValueOrDefault(p.Id) ?? [];
                toppingCatalog.TryGetValue(p.Id, out var tops);
                var exposeUnits = pVars.Count == 0 && pUnits.Count > 0
                    ? (pUnits.Count > 1 ? pUnits : pUnits.Where(u => !u.IsBaseUnit).ToList())
                    : [];
                var soldOut = !settings.AllowNegativeStock
                    && p.ProductType == PosProductType.Goods
                    && pVars.Count == 0
                    && exposeUnits.Count == 0
                    && (p.OnHandQty - p.ReservedQty) <= 0;
                var storePrice = p.BasePrice;
                var displayPrice = PosQrMenuService.ResolveProductPrice(p, menuItem);
                return new
                {
                    id = p.Id,
                    name = p.Name,
                    price = displayPrice,
                    storePrice,
                    customPrice = menuItem?.QrPrice,
                    imageUrl = PublicMediaUrl(urlBase, p.ImageUrl),
                    categoryId = p.CategoryId,
                    soldOut,
                    variants = pVars.Select(v => new
                    {
                        id = v.Id,
                        name = v.Name,
                        price = PosQrMenuService.ResolveVariantPrice(p, v, menuItem),
                        soldOut = !settings.AllowNegativeStock && v.OnHandQty <= 0,
                    }),
                    units = exposeUnits.Select(u => new
                    {
                        id = u.Id,
                        name = u.UnitName,
                        price = PosQrMenuService.ResolveUnitPrice(p, u, menuItem),
                        soldOut = !settings.AllowNegativeStock
                            && p.ProductType == PosProductType.Goods
                            && QrUnitAvailQty(p, u) <= 0,
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
        => await EnqueueKitchenSlipAsync(
            storeId, order, TableLabel(resource), added, now);

    async Task<int> TryEnqueueOnlineKitchenAsync(
        Guid storeId,
        Guid orderId,
        DateTime now)
    {
        var order = await db.PosSaleOrders.AsTracking()
            .Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == orderId && o.StoreId == storeId && o.Deleted == null);
        if (order == null) return 0;
        var lines = order.Lines.Where(l => l.Deleted == null).ToList();
        if (lines.Count == 0) return 0;
        var productIds = lines.Select(l => l.ProductId).Distinct().ToList();
        var products = await db.PosProducts.AsNoTracking()
            .Include(p => p.Category)
            .Where(p => productIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
            .ToDictionaryAsync(p => p.Id);
        var added = new List<(PosSaleOrderLine Line, decimal Qty, PosProduct Product)>();
        foreach (var line in lines)
        {
            if (!products.TryGetValue(line.ProductId, out var p)) continue;
            var pending = line.Qty - line.KitchenSentQty;
            if (pending <= 0) continue;
            line.KitchenSentQty = line.Qty;
            line.KitchenSentAt = now;
            PosKitchenKdsHelper.OnSent(line);
            added.Add((line, pending, p));
        }
        if (added.Count == 0) return 0;
        await db.SaveChangesAsync();
        var label = string.IsNullOrWhiteSpace(order.CustomerName)
            ? "Đơn online"
            : $"Online · {order.CustomerName}";
        return await EnqueueKitchenSlipAsync(storeId, order, label, added, now, "Đơn online");
    }

    async Task<int> EnqueueKitchenSlipAsync(
        Guid storeId,
        PosSaleOrder order,
        string tableName,
        List<(PosSaleOrderLine Line, decimal Qty, PosProduct Product)> added,
        DateTime now,
        string senderName = "QR khách")
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

        var tbl = tableName.Trim();
        if (tbl.Length == 0) tbl = "QR";
        var jobs = 0;
        var stamp = now.ToString("HHmmss");
        foreach (var g in groups)
        {
            var payload = JsonSerializer.Serialize(new
            {
                tableName = tbl,
                isCancel = false,
                senderName,
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
                senderName,
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

    static string? KitchenNoteText(string? toppingsJson, string? lineNote) =>
        PosSaleStockHelper.FormatToppingKitchenNote(toppingsJson, lineNote);

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

    string? ResolveDefaultLogoPath()
    {
        foreach (var path in new[]
        {
            Path.Combine(AppContext.BaseDirectory, "guest", "sbox-pos-logo.png"),
            Path.Combine(env.ContentRootPath, "guest", "sbox-pos-logo.png"),
            Path.Combine(env.WebRootPath ?? "wwwroot", "assets", "sbox-pos-logo.png"),
            Path.Combine(env.ContentRootPath, "wwwroot", "assets", "sbox-pos-logo.png"),
        })
        {
            if (System.IO.File.Exists(path))
                return path;
        }
        return null;
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

    string? PublicMediaUrl(string publicBase, string? path)
    {
        var p = (path ?? "").Trim();
        if (p.Length == 0) return null;
        if (p.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
            || p.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
        {
            if (p.Contains("/api/upload/serve", StringComparison.OrdinalIgnoreCase))
                return p.Replace("/api/upload/serve", "/api/upload/public-serve",
                    StringComparison.OrdinalIgnoreCase);
            return p;
        }
        p = p.TrimStart('/');
        var root = string.IsNullOrWhiteSpace(publicBase) ? PublicBase() : publicBase.TrimEnd('/');
        return $"{root}/api/upload/public-serve?path={Uri.EscapeDataString(p)}";
    }

    static decimal ResolveQrUnitPrice(PosProduct product, PosProductUnit unit)
    {
        var rate = unit.ConversionRate > 0 ? unit.ConversionRate : 1;
        var configured = unit.BasePrice;
        var basePrice = product.BasePrice;
        if (rate > 1 && basePrice > 0
            && (configured <= 0 || Math.Abs(configured - basePrice) < 0.01m))
            return Math.Round(basePrice * rate, 0, MidpointRounding.AwayFromZero);
        if (configured > 0) return configured;
        return Math.Round(basePrice * rate, 0, MidpointRounding.AwayFromZero);
    }

    static decimal QrUnitAvailQty(PosProduct product, PosProductUnit unit)
    {
        var rate = unit.ConversionRate > 0 ? unit.ConversionRate : 1;
        return (product.OnHandQty - product.ReservedQty) / rate;
    }

    static string NewToken() => Guid.NewGuid().ToString("N")[..12];
}
