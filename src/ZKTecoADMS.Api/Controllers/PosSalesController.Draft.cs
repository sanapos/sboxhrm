using ClosedXML.Excel;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System.Data;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Api.Controllers.Reports;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

public partial class PosSalesController
{
    [HttpPut("{id:guid}")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<SaleOrderDto>>> UpdateSale(Guid id, [FromBody] UpdateSaleDto dto)
    {
        if (dto.Complete)
        {
            var denied = await DenyIfCannotCompleteSaleAsync();
            if (denied != null) return denied;
        }

        var storeId = RequiredStoreId;
        // DbContext mặc định NoTracking — bắt buộc AsTracking khi sửa đơn.
        var order = await dbContext.PosSaleOrders
            .AsTracking()
            .Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId && o.Deleted == null);
        if (order == null)
            return NotFound(AppResponse<SaleOrderDto>.Fail("Không tìm thấy đơn hàng"));
        if (order.Status != PosSaleOrderStatus.Draft)
            return BadRequest(AppResponse<SaleOrderDto>.Fail("Chỉ sửa được đơn tạm"));

        var actor = CurrentLockActor(dto.DeviceId, dto.DeviceName);
        var lockErr = PosDraftLockHelper.EnsureCanMutate(order, actor, dto.ExpectedLockVersion);
        if (lockErr != null)
        {
            SaleOrderDto conflictMapped;
            try { conflictMapped = await MapOrderAsync(storeId, order, order.Lines?.ToList() ?? [], dto.DeviceId, dto.DeviceName); }
            catch { conflictMapped = MapOrder(order, order.Lines?.ToList() ?? [], viewerUserId: CurrentUserId, viewerDeviceId: dto.DeviceId, viewerDeviceName: dto.DeviceName); }
            return Conflict(AppResponse<SaleOrderDto>.Create(false, conflictMapped, [lockErr]));
        }
        PosDraftLockHelper.StampDeviceIfMissing(order, actor);
        if (PosDraftLockHelper.IsLockActive(order) && !PosDraftLockHelper.IsHeldBy(order, actor))
        {
            SaleOrderDto conflictMapped;
            try { conflictMapped = await MapOrderAsync(storeId, order, order.Lines?.ToList() ?? [], dto.DeviceId, dto.DeviceName); }
            catch { conflictMapped = MapOrder(order, order.Lines?.ToList() ?? [], viewerUserId: CurrentUserId, viewerDeviceId: dto.DeviceId, viewerDeviceName: dto.DeviceName); }
            return Conflict(AppResponse<SaleOrderDto>.Create(false, conflictMapped, [
                $"Đơn đang được mở bởi {order.LockedByDisplayName ?? "người khác"}"
            ]));
        }

        // Draft clear: cho phép lines rỗng — xóa hàng + nhả khóa (đồng bộ đa máy).
        if (!dto.Complete && (dto.Lines == null || dto.Lines.Count == 0))
        {
            dbContext.PosSaleOrderLines.RemoveRange(order.Lines);
            order.SubTotal = 0;
            order.Discount = dto.Discount;
            order.Total = 0;
            order.PaidAmount = 0;
            order.Note = dto.Note?.Trim();
            order.CustomerId = dto.CustomerId;
            order.CustomerName = string.IsNullOrWhiteSpace(dto.CustomerName)
                ? "Bán cho người tiêu dùng"
                : dto.CustomerName.Trim();
            order.PaymentMethod = string.IsNullOrWhiteSpace(dto.PaymentMethod)
                ? "Tiền mặt"
                : dto.PaymentMethod.Trim();
            order.UpdatedAt = DateTime.UtcNow;
            order.UpdatedBy = CurrentUserEmail;
            var liveClearErr = await EnsureLiveLockStillHeldAsync(order, actor, dto.ExpectedLockVersion);
            if (liveClearErr != null)
            {
                dbContext.ChangeTracker.Clear();
                var fresh = await dbContext.PosSaleOrders.AsNoTracking()
                    .Include(o => o.Lines)
                    .FirstAsync(o => o.Id == id);
                SaleOrderDto conflictMapped;
                try { conflictMapped = await MapOrderAsync(storeId, fresh, fresh.Lines?.Where(l => l.Deleted == null).ToList() ?? [], dto.DeviceId, dto.DeviceName); }
                catch { conflictMapped = MapOrder(fresh, fresh.Lines?.Where(l => l.Deleted == null).ToList() ?? [], viewerUserId: CurrentUserId, viewerDeviceId: dto.DeviceId, viewerDeviceName: dto.DeviceName); }
                return Conflict(AppResponse<SaleOrderDto>.Create(false, conflictMapped, [liveClearErr]));
            }
            PosDraftLockHelper.BumpAfterSuccessfulSave(order, actor, 0);
            await dbContext.SaveChangesAsync();
            order.Lines = [];
            SaleOrderDto cleared;
            try { cleared = await MapOrderAsync(storeId, order, [], dto.DeviceId, dto.DeviceName); }
            catch { cleared = MapOrder(order, [], viewerUserId: CurrentUserId, viewerDeviceId: dto.DeviceId, viewerDeviceName: dto.DeviceName); }
            return Ok(AppResponse<SaleOrderDto>.Success(cleared));
        }

        var slotBeforeComplete = order.InvoiceSlot;
        var createDto = new CreateSaleDto(
            dto.Lines, dto.Discount, dto.PaidAmount, dto.PaymentMethod,
            dto.CustomerName, dto.CustomerId, dto.Note, dto.Complete,
            dto.IsDelivery, dto.DeliveryAddress, dto.DeliveryPhone,
            dto.DeliveryPartner, dto.DeliveryStatus, dto.DeliveryDate,
            dto.SoldBy, dto.SoldByEmployeeId, dto.SalesChannel, dto.PriceListName,
            dto.PriceListId, dto.Payments, dto.VoucherCode, dto.PointsToRedeem,
            dto.ServiceResourceId, dto.ResourceSessionId, dto.ServiceStartedAt, dto.ServiceEndedAt,
            dto.ExpectedLockVersion, dto.DeviceId, dto.DeviceName, dto.InvoiceSlot,
            dto.VatAmount);

        // Thanh toán: RepeatableRead + retry serialization/unique (giống CreateSale) —
        // tránh 500 «lỗi hệ thống» khi autosave/máy khác tranh chấp tồn hoặc mã HD/phiếu thu.
        if (dto.Complete)
        {
            List<PosSaleOrderLine>? linesComplete = null;
            var savedComplete = false;

            for (var outerAttempt = 0; outerAttempt < 5 && !savedComplete; outerAttempt++)
            {
                if (outerAttempt > 0)
                {
                    dbContext.ChangeTracker.Clear();
                    order = await dbContext.PosSaleOrders
                        .AsTracking()
                        .Include(o => o.Lines)
                        .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId && o.Deleted == null);
                    if (order == null)
                        return NotFound(AppResponse<SaleOrderDto>.Fail("Không tìm thấy đơn hàng"));
                    if (order.Status == PosSaleOrderStatus.Completed)
                    {
                        // Request trước đã commit — trả đơn hoàn thành (idempotent).
                        var doneLines = order.Lines?.Where(l => l.Deleted == null).ToList() ?? [];
                        SaleOrderDto already;
                        try { already = await MapOrderAsync(storeId, order, doneLines, dto.DeviceId, dto.DeviceName); }
                        catch
                        {
                            already = MapOrder(order, doneLines, viewerUserId: CurrentUserId,
                                viewerDeviceId: dto.DeviceId, viewerDeviceName: dto.DeviceName);
                        }
                        return Ok(AppResponse<SaleOrderDto>.Success(already));
                    }
                    if (order.Status != PosSaleOrderStatus.Draft)
                        return BadRequest(AppResponse<SaleOrderDto>.Fail("Chỉ sửa được đơn tạm"));
                    PosDraftLockHelper.StampDeviceIfMissing(order, actor);
                }

                dbContext.PosSaleOrderLines.RemoveRange(order.Lines);

                await using var tx = await dbContext.Database.BeginTransactionAsync(IsolationLevel.RepeatableRead);
                try
                {
                    var (_, builtLines, errComplete) =
                        await BuildSaleAsync(storeId, order, createDto, complete: true,
                            allowManualPriceOverride: true);
                    if (errComplete != null)
                    {
                        await tx.RollbackAsync();
                        return BadRequest(AppResponse<SaleOrderDto>.Fail(errComplete));
                    }
                    if (builtLines == null)
                    {
                        await tx.RollbackAsync();
                        return BadRequest(AppResponse<SaleOrderDto>.Fail("Không cập nhật được đơn"));
                    }
                    dbContext.PosSaleOrderLines.AddRange(builtLines);
                    await SaveSaleChangesWithUniqueRetriesAsync(order, storeId);
                    await tx.CommitAsync();
                    linesComplete = builtLines;
                    savedComplete = true;
                }
                catch (Exception ex) when (outerAttempt < 4 && IsSerializationFailure(ex))
                {
                    await tx.RollbackAsync();
                    savedComplete = false;
                }
                catch (DbUpdateException ex) when (IsUniqueCashCodeConflict(ex) || IsUniqueOrderNoConflict(ex))
                {
                    await tx.RollbackAsync();
                    SaleOrderDto conflictMapped;
                    try
                    {
                        conflictMapped = await MapOrderAsync(
                            storeId, order, order.Lines?.ToList() ?? [], dto.DeviceId, dto.DeviceName);
                    }
                    catch
                    {
                        conflictMapped = MapOrder(order, order.Lines?.ToList() ?? [],
                            viewerUserId: CurrentUserId,
                            viewerDeviceId: dto.DeviceId, viewerDeviceName: dto.DeviceName);
                    }
                    return Conflict(AppResponse<SaleOrderDto>.Create(
                        false, conflictMapped,
                        ["Trùng mã đơn/phiếu thu do xử lý đồng thời — vui lòng bấm thanh toán lại"]));
                }
                catch
                {
                    await tx.RollbackAsync();
                    throw;
                }
            }

            if (!savedComplete || linesComplete == null)
            {
                return Conflict(AppResponse<SaleOrderDto>.Fail(
                    "Xung đột dữ liệu khi thanh toán — vui lòng bấm thanh toán lại"));
            }

            SaleOrderDto mappedComplete;
            try
            {
                mappedComplete = await MapOrderAsync(
                    storeId, order, linesComplete, dto.DeviceId, dto.DeviceName);
            }
            catch
            {
                order.Lines = linesComplete;
                mappedComplete = MapOrder(order, linesComplete, viewerUserId: CurrentUserId,
                    viewerDeviceId: dto.DeviceId, viewerDeviceName: dto.DeviceName);
            }

            if (order.Status == PosSaleOrderStatus.Completed)
            {
                await CloseResourceSessionForCompletedOrderAsync(storeId, order);
                try
                {
                    await PosNotificationHelper.NotifySaleCompletedAsync(
                        notificationService, dbContext, storeId, order.Id, order.OrderNo,
                        order.Total, order.SoldBy, CurrentUserId);
                }
                catch { }
                try { await RecreateInvoiceSlotIfNeededAsync(storeId, slotBeforeComplete); }
                catch { }
                NotifyFloorChanged(storeId, "saleCompleted",
                    orderId: order.Id, resourceId: order.ServiceResourceId);
            }
            return Ok(AppResponse<SaleOrderDto>.Success(mappedComplete));
        }

        // Đọc KitchenSentQty mới từ DB (AsNoTracking) — tránh race với kitchen-send
        // khi tracked order.Lines còn stale (kitchen=0) rồi RemoveRange ghi đè.
        // Key gồm topping + ghi chú để không gộp nhầm dòng cùng SP.
        var priorRows = await dbContext.PosSaleOrderLines.AsNoTracking()
            .Where(l => l.SaleOrderId == order.Id && l.Deleted == null)
            .Select(l => new
            {
                l.ProductId,
                l.VariantId,
                l.KitchenSentQty,
                l.KitchenSentAt,
                l.ToppingsJson,
                l.LineNote,
            })
            .ToListAsync();
        var priorKitchen = priorRows
            .GroupBy(l => KitchenMergeKey(l.ProductId, l.VariantId, l.ToppingsJson, l.LineNote))
            .ToDictionary(
                g => g.Key,
                g => (
                    Sent: g.Sum(x => x.KitchenSentQty),
                    At: g.Max(x => x.KitchenSentAt)));
        dbContext.PosSaleOrderLines.RemoveRange(order.Lines);

        var allowPrice = await HasPosSellApproveAsync();
        var (_, lines, err) = await BuildSaleAsync(
            storeId, order, createDto, dto.Complete,
            allowManualPriceOverride: allowPrice);
        if (err == PriceOverrideDeniedMessage)
        {
            var denied = await DenyIfCannotOverridePriceAsync();
            return denied ?? StatusCode(StatusCodes.Status403Forbidden,
                AppResponse<SaleOrderDto>.Fail(
                    "Tài khoản không có quyền duyệt PosSell (đổi giá / chiết khấu)."));
        }
        if (err != null) return BadRequest(AppResponse<SaleOrderDto>.Fail(err));
        if (lines == null)
            return BadRequest(AppResponse<SaleOrderDto>.Fail("Không cập nhật được đơn"));

        // Ghép KitchenSentQty: max(client, prior lúc đầu, live DB ngay trước ghi).
        // Live đọc lại để không bị race với kitchen-send (autosave xóa dòng đang gửi bếp).
        var dtoKitchenByKey = dto.Lines
            .GroupBy(l => KitchenMergeKey(l.ProductId, l.VariantId, l.ToppingsJson, l.LineNote))
            .ToDictionary(g => g.Key, g => g.Sum(x => x.KitchenSentQty ?? 0));
        var remainingPrior = priorKitchen.ToDictionary(kv => kv.Key, kv => kv.Value.Sent);
        var remainingAt = priorKitchen.ToDictionary(kv => kv.Key, kv => kv.Value.At);
        var remainingDto = dtoKitchenByKey.ToDictionary(kv => kv.Key, kv => kv.Value);

        var liveRows = await dbContext.PosSaleOrderLines.AsNoTracking()
            .Where(l => l.SaleOrderId == order.Id && l.Deleted == null)
            .Select(l => new
            {
                l.ProductId,
                l.VariantId,
                l.KitchenSentQty,
                l.KitchenSentAt,
                l.ToppingsJson,
                l.LineNote,
            })
            .ToListAsync();
        var liveKitchen = liveRows
            .GroupBy(l => KitchenMergeKey(l.ProductId, l.VariantId, l.ToppingsJson, l.LineNote))
            .ToDictionary(
                g => g.Key,
                g => (
                    Sent: g.Sum(x => x.KitchenSentQty),
                    At: g.Max(x => x.KitchenSentAt)));
        foreach (var kv in liveKitchen)
        {
            if (!remainingPrior.ContainsKey(kv.Key) || remainingPrior[kv.Key] < kv.Value.Sent)
                remainingPrior[kv.Key] = kv.Value.Sent;
            if (kv.Value.At.HasValue &&
                (!remainingAt.TryGetValue(kv.Key, out var at) || at == null || kv.Value.At > at))
                remainingAt[kv.Key] = kv.Value.At;
        }

        foreach (var line in lines)
        {
            var key = KitchenMergeKey(line.ProductId, line.VariantId, line.ToppingsJson, line.LineNote);
            remainingDto.TryGetValue(key, out var fromClient);
            remainingPrior.TryGetValue(key, out var fromPrior);
            var take = Math.Max(fromClient, fromPrior);
            take = Math.Min(take, line.Qty);
            if (take <= 0) continue;
            line.KitchenSentQty = take;
            if (remainingAt.TryGetValue(key, out var at) && at.HasValue)
                line.KitchenSentAt = at;
            else
                line.KitchenSentAt = DateTime.UtcNow;
            remainingDto[key] = Math.Max(0, fromClient - take);
            remainingPrior[key] = Math.Max(0, fromPrior - take);
        }

        // Bảo vệ lần cuối: kitchen-send có thể vừa ghi KitchenSentQty lên dòng cũ
        // ngay trước khi ta SaveChanges xóa chúng — đọc lại DB và lấy max.
        var finalLiveRows = await dbContext.PosSaleOrderLines.AsNoTracking()
            .Where(l => l.SaleOrderId == order.Id && l.Deleted == null)
            .Select(l => new
            {
                l.ProductId,
                l.VariantId,
                l.KitchenSentQty,
                l.KitchenSentAt,
                l.ToppingsJson,
                l.LineNote,
            })
            .ToListAsync();
        var finalLive = finalLiveRows
            .GroupBy(l => KitchenMergeKey(l.ProductId, l.VariantId, l.ToppingsJson, l.LineNote))
            .ToDictionary(
                g => g.Key,
                g => (
                    Sent: g.Sum(x => x.KitchenSentQty),
                    At: g.Max(x => x.KitchenSentAt)));
        foreach (var line in lines)
        {
            var key = KitchenMergeKey(line.ProductId, line.VariantId, line.ToppingsJson, line.LineNote);
            if (!finalLive.TryGetValue(key, out var live)) continue;
            if (live.Sent > line.KitchenSentQty)
            {
                line.KitchenSentQty = Math.Min(live.Sent, line.Qty);
                if (live.At.HasValue) line.KitchenSentAt = live.At;
            }
        }

        if (order.Status == PosSaleOrderStatus.Draft)
        {
            var liveErr = await EnsureLiveLockStillHeldAsync(order, actor, dto.ExpectedLockVersion);
            if (liveErr != null)
            {
                dbContext.ChangeTracker.Clear();
                var fresh = await dbContext.PosSaleOrders.AsNoTracking()
                    .Include(o => o.Lines)
                    .FirstAsync(o => o.Id == id);
                SaleOrderDto conflictMapped;
                try { conflictMapped = await MapOrderAsync(storeId, fresh, fresh.Lines?.Where(l => l.Deleted == null).ToList() ?? [], dto.DeviceId, dto.DeviceName); }
                catch { conflictMapped = MapOrder(fresh, fresh.Lines?.Where(l => l.Deleted == null).ToList() ?? [], viewerUserId: CurrentUserId, viewerDeviceId: dto.DeviceId, viewerDeviceName: dto.DeviceName); }
                return Conflict(AppResponse<SaleOrderDto>.Create(false, conflictMapped, [liveErr]));
            }
            // Đồng bộ LockVersion từ DB trước khi bump (tránh ghi đè khóa máy vừa cướp).
            PosDraftLockHelper.BumpAfterSuccessfulSave(order, actor, lines.Count);

            // Bắt đầu đếm giờ sử dụng bàn từ lúc chọn món đầu tiên (không từ lúc mở bàn trống).
            if (lines.Count > 0 && order.ResourceSessionId.HasValue && liveRows.Count <= 0)
            {
                var nowFirst = DateTime.UtcNow;
                order.ServiceStartedAt = nowFirst;
                var sess = await dbContext.PosResourceSessions.AsTracking()
                    .FirstOrDefaultAsync(s => s.Id == order.ResourceSessionId.Value
                        && s.StoreId == storeId && s.Deleted == null);
                if (sess != null)
                {
                    sess.StartedAt = nowFirst;
                    sess.AccumulatedPauseMinutes = 0;
                    sess.UpdatedAt = nowFirst;
                    sess.UpdatedBy = CurrentUserEmail;
                }
            }
        }

        dbContext.PosSaleOrderLines.AddRange(lines);
        for (var attempt = 0; ; attempt++)
        {
            try
            {
                await dbContext.SaveChangesAsync();
                break;
            }
            catch (DbUpdateException ex) when (attempt < 5 &&
                ex.InnerException?.Message.Contains("IX_CashTransactions_StoreId_TransactionCode") == true)
            {
                await PosFinanceSyncHelper.RegenerateDuplicateCodesAsync(dbContext, storeId);
            }
        }

        SaleOrderDto mapped;
        try
        {
            mapped = await MapOrderAsync(storeId, order, lines, dto.DeviceId, dto.DeviceName);
        }
        catch
        {
            order.Lines = lines;
            mapped = MapOrder(order, lines, viewerUserId: CurrentUserId, viewerDeviceId: dto.DeviceId, viewerDeviceName: dto.DeviceName);
        }

        if (order.ServiceResourceId.HasValue)
        {
            NotifyFloorChanged(storeId, "draftSaved",
                orderId: order.Id, resourceId: order.ServiceResourceId);
        }
        return Ok(AppResponse<SaleOrderDto>.Success(mapped));
    }

    static string KitchenMergeKey(
        Guid productId, Guid? variantId, string? toppingsJson, string? lineNote)
    {
        var top = string.IsNullOrWhiteSpace(toppingsJson) ? "" : toppingsJson.Trim();
        var note = string.IsNullOrWhiteSpace(lineNote) ? "" : lineNote.Trim();
        return $"{productId}|{variantId}|{top}|{note}";
    }

    /// <summary>
    /// Đọc khóa mới nhất từ DB trước khi Save — chặn autosave máy cũ ghi đè sau khi máy khác đã Lấy quyền.
    /// </summary>
    async Task<string?> EnsureLiveLockStillHeldAsync(
        PosSaleOrder tracked,
        PosDraftLockHelper.LockActor actor,
        int? expectedLockVersion)
    {
        var live = await dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.Id == tracked.Id)
            .Select(o => new
            {
                o.Status,
                o.LockVersion,
                o.LockedByUserId,
                o.LockedByDeviceId,
                o.LockedByDeviceName,
                o.LockedByDisplayName,
                o.LockExpiresAt,
            })
            .FirstOrDefaultAsync();
        if (live == null)
            return "Không tìm thấy đơn hàng";

        var err = PosDraftLockHelper.EnsureHeldByLiveSnapshot(
            live.LockedByUserId,
            live.LockedByDeviceId,
            live.LockedByDisplayName,
            live.LockedByDeviceName,
            live.LockExpiresAt,
            live.Status,
            actor,
            live.LockVersion,
            expectedLockVersion);
        if (err != null)
            return err;

        // Đồng bộ version/lock fields trên entity tracked trước bump.
        tracked.LockVersion = live.LockVersion;
        tracked.LockedByUserId = live.LockedByUserId;
        tracked.LockedByDeviceId = live.LockedByDeviceId;
        tracked.LockedByDeviceName = live.LockedByDeviceName;
        tracked.LockedByDisplayName = live.LockedByDisplayName;
        tracked.LockExpiresAt = live.LockExpiresAt;
        return null;
    }

    [HttpPost("{id:guid}/complete")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Approve)]
    public async Task<ActionResult<AppResponse<SaleOrderDto>>> CompleteSale(
        Guid id, [FromBody] CompleteSaleDto? dto = null)
    {
        var storeId = RequiredStoreId;
        // DbContext mặc định NoTracking — bắt buộc AsTracking để SaveChangesAsync thực sự ghi đơn.
        var order = await dbContext.PosSaleOrders.AsTracking()
            .Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId && o.Deleted == null);
        if (order == null)
            return NotFound(AppResponse<SaleOrderDto>.Fail("Không tìm thấy đơn hàng"));
        if (order.Status != PosSaleOrderStatus.Draft)
            return BadRequest(AppResponse<SaleOrderDto>.Fail("Đơn không ở trạng thái tạm"));
        if (order.Lines.Count == 0)
            return BadRequest(AppResponse<SaleOrderDto>.Fail("Đơn trống"));

        var actor = CurrentLockActor(dto?.DeviceId, dto?.DeviceName);
        var lockErr = PosDraftLockHelper.EnsureCanMutate(order, actor, dto?.ExpectedLockVersion);
        if (lockErr != null)
        {
            SaleOrderDto conflictMapped;
            try { conflictMapped = await MapOrderAsync(storeId, order); }
            catch { conflictMapped = MapOrder(order, order.Lines?.ToList() ?? [], viewerUserId: CurrentUserId); }
            return Conflict(AppResponse<SaleOrderDto>.Create(false, conflictMapped, [lockErr]));
        }

        var allowNegComplete = await dbContext.PosStoreSellSettings.AsNoTracking()
            .Where(s => s.StoreId == storeId && s.Deleted == null)
            .Select(s => s.AllowNegativeStock)
            .FirstOrDefaultAsync();
        // Draft cũ chỉ có UnitName — resolve UnitId để quy đổi tồn đúng.
        await PosSaleStockHelper.EnsureLineUnitIdsAsync(dbContext, order.Lines);
        var lineInputs = order.Lines
            .Select(l => (l.ProductId, l.Qty, l.VariantId, l.UnitId, l.ToppingsJson))
            .ToList();
        // Validate stock sớm (ngoài tx) để trả lỗi nhanh; prepare thật nằm trong RR tx bên dưới.
        var (_, earlyStockErr) = await PosSaleStockHelper.PrepareSaleStockAsync(
            dbContext, storeId, PosSaleStockHelper.ExpandStockInputsWithToppings(lineInputs),
            allowNegativeStock: allowNegComplete);
        if (earlyStockErr != null) return BadRequest(AppResponse<SaleOrderDto>.Fail(earlyStockErr));
        // Bỏ entity tracked từ prepare sớm — tránh OnHand cũ dính change tracker.
        dbContext.ChangeTracker.Clear();
        order = await dbContext.PosSaleOrders.AsTracking()
            .Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId && o.Deleted == null);
        if (order == null)
            return NotFound(AppResponse<SaleOrderDto>.Fail("Không tìm thấy đơn hàng"));
        if (order.Status != PosSaleOrderStatus.Draft)
            return BadRequest(AppResponse<SaleOrderDto>.Fail("Đơn không ở trạng thái tạm"));

        var productIds = order.Lines.Select(l => l.ProductId).Distinct().ToList();
        var productsPreview = await dbContext.PosProducts.AsNoTracking()
            .Where(p => productIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
            .ToDictionaryAsync(p => p.Id);

        var dtoLines = BuildCompleteSaleLineDtos(order.Lines.ToList(), dto?.Lines);
        var warrantyLines = dtoLines
            .Where(l => productsPreview.TryGetValue(l.ProductId, out var wp) &&
                        PosSaleWarrantyHelper.NeedsRegistration(wp))
            .Select(l => (l, productsPreview[l.ProductId]))
            .ToList();
        if (warrantyLines.Count > 0)
        {
            var warrantyErr = await PosSaleWarrantyHelper.ValidateSerialsAsync(
                dbContext, storeId, warrantyLines);
            if (warrantyErr != null) return BadRequest(AppResponse<SaleOrderDto>.Fail(warrantyErr));
        }

        var slotBeforeComplete = order.InvoiceSlot;
        var savedComplete = false;
        SaleStockPlan? plan = null;
        Dictionary<Guid, PosProduct> products = productsPreview;

        for (var outerAttempt = 0; outerAttempt < 5 && !savedComplete; outerAttempt++)
        {
            if (outerAttempt > 0)
            {
                dbContext.ChangeTracker.Clear();
                order = await dbContext.PosSaleOrders.AsTracking()
                    .Include(o => o.Lines)
                    .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId && o.Deleted == null);
                if (order == null)
                    return NotFound(AppResponse<SaleOrderDto>.Fail("Không tìm thấy đơn hàng"));
                if (order.Status == PosSaleOrderStatus.Completed)
                {
                    savedComplete = true;
                    break;
                }
                if (order.Status != PosSaleOrderStatus.Draft)
                    return BadRequest(AppResponse<SaleOrderDto>.Fail("Đơn không ở trạng thái tạm"));
                if (order.Lines.Count == 0)
                    return BadRequest(AppResponse<SaleOrderDto>.Fail("Đơn trống"));

                dtoLines = BuildCompleteSaleLineDtos(order.Lines.ToList(), dto?.Lines);
            }

            order.Status = PosSaleOrderStatus.Completed;
            order.SaleDate = DateTime.UtcNow;
            order.SoldBy ??= CurrentUserEmail;
            order.PaidAmount = order.PaidAmount > 0 ? order.PaidAmount : 0;
            if (PosDraftInvoiceSlots.IsTempOrderNo(order.OrderNo) || order.InvoiceSlot.HasValue
                || order.OrderNo.StartsWith("BAN", StringComparison.OrdinalIgnoreCase))
                order.OrderNo = await PosSaleStockHelper.NextOrderNoAsync(dbContext, storeId, order.SaleDate);
            order.InvoiceSlot = null;
            PosDraftLockHelper.Release(order);

            await using var tx = await dbContext.Database.BeginTransactionAsync(IsolationLevel.RepeatableRead);
            try
            {
                // Prepare tồn TRONG RepeatableRead — tránh đọc OnHand ngoài tx rồi ghi đè mất cập nhật đồng thời.
                await PosSaleStockHelper.EnsureLineUnitIdsAsync(dbContext, order.Lines);
                string? stockErr;
                (plan, stockErr) = await PosSaleStockHelper.PrepareSaleStockAsync(
                    dbContext, storeId, PosSaleStockHelper.ExpandStockInputsWithToppings(
                        order.Lines.Select(l => (l.ProductId, l.Qty, l.VariantId, l.UnitId, l.ToppingsJson)).ToList()),
                    allowNegativeStock: allowNegComplete);
                if (stockErr != null)
                {
                    await tx.RollbackAsync();
                    return BadRequest(AppResponse<SaleOrderDto>.Fail(stockErr));
                }
                products = plan!.Products;

                await PosSaleStockHelper.ApplySaleStockAsync(
                    dbContext, storeId, order, order.Lines.ToList(), plan!, CurrentUserEmail);
                await PosSaleStockHelper.UpdateCustomerOnSaleCompleteAsync(dbContext, storeId, order);
                if (order.CustomerId.HasValue)
                {
                    var saleCustomer = await dbContext.PosCustomers.AsTracking()
                        .FirstOrDefaultAsync(c => c.Id == order.CustomerId && c.StoreId == storeId && c.Deleted == null);
                    if (saleCustomer != null)
                    {
                        await PosCustomerFinanceHelper.ApplyPointsOnSaleCompleteAsync(
                            dbContext, storeId, order, saleCustomer, CurrentUserEmail);
                        if (order.VoucherId.HasValue)
                        {
                            var vch = await dbContext.PosVouchers.AsTracking()
                                .FirstOrDefaultAsync(v => v.Id == order.VoucherId && v.StoreId == storeId);
                            if (vch != null)
                            {
                                vch.UsedCount += 1;
                                vch.UpdatedAt = DateTime.UtcNow;
                            }
                        }
                    }
                }
                await PosSellIndustryController.GrantSessionPacksOnSaleCompleteAsync(
                    dbContext, storeId, order, order.Lines.ToList(), CurrentUserEmail);
                await PosSaleWarrantyHelper.RegisterOnSaleAsync(
                    dbContext, storeId, order, order.Lines.ToList(), dtoLines, products, CurrentUserEmail);
                order.UpdatedAt = DateTime.UtcNow;
                order.UpdatedBy = CurrentUserEmail;
                await PosFinanceSyncHelper.SyncSaleOnCompleteAsync(dbContext, order, CurrentUserId);
                await SaveSaleChangesWithUniqueRetriesAsync(order, storeId);
                await tx.CommitAsync();
                savedComplete = true;
            }
            catch (Exception ex) when (outerAttempt < 4 && IsSerializationFailure(ex))
            {
                await tx.RollbackAsync();
                savedComplete = false;
            }
            catch (DbUpdateException ex) when (IsUniqueCashCodeConflict(ex) || IsUniqueOrderNoConflict(ex))
            {
                await tx.RollbackAsync();
                SaleOrderDto conflictMapped;
                try { conflictMapped = await MapOrderAsync(storeId, order); }
                catch { conflictMapped = MapOrder(order, order.Lines?.ToList() ?? [], viewerUserId: CurrentUserId); }
                return Conflict(AppResponse<SaleOrderDto>.Create(
                    false, conflictMapped,
                    ["Trùng mã đơn/phiếu thu do xử lý đồng thời — vui lòng bấm hoàn thành lại"]));
            }
            catch
            {
                await tx.RollbackAsync();
                throw;
            }
        }

        if (!savedComplete)
        {
            return Conflict(AppResponse<SaleOrderDto>.Fail(
                "Xung đột dữ liệu khi hoàn thành đơn — vui lòng bấm lại"));
        }

        await CloseResourceSessionForCompletedOrderAsync(storeId, order);

        var lowStockItems = plan!.Products.Values
            .Select(p => (p.Id, p.Name, p.OnHandQty, p.MinStockQty));
        await PosNotificationHelper.NotifyLowStockAsync(
            notificationService, dbContext, storeId, lowStockItems, CurrentUserId);

        try
        {
            await PosNotificationHelper.NotifySaleCompletedAsync(
                notificationService, dbContext, storeId, order.Id, order.OrderNo,
                order.Total, order.SoldBy, CurrentUserId);
        }
        catch
        {
        }

        SaleOrderDto mapped;
        try
        {
            mapped = await MapOrderAsync(storeId, order);
        }
        catch
        {
            mapped = MapOrder(order, order.Lines?.ToList() ?? []);
        }

        try { await RecreateInvoiceSlotIfNeededAsync(storeId, slotBeforeComplete); }
        catch { }

        NotifyFloorChanged(storeId, "saleCompleted",
            orderId: order.Id, resourceId: order.ServiceResourceId);
        return Ok(AppResponse<SaleOrderDto>.Success(mapped));
    }

    private static List<SaleLineDto> BuildCompleteSaleLineDtos(
        List<PosSaleOrderLine> orderLines, List<SaleLineDto>? inputLines)
    {
        if (inputLines == null || inputLines.Count == 0)
        {
            return orderLines.Select(l => new SaleLineDto(
                l.ProductId, l.Qty, null, l.UnitPrice, l.VariantId)).ToList();
        }

        var byKey = inputLines
            .GroupBy(l => (l.ProductId, l.VariantId))
            .ToDictionary(g => g.Key, g => g.First());

        return orderLines.Select(l =>
        {
            if (byKey.TryGetValue((l.ProductId, l.VariantId), out var matched))
                return matched with { Qty = l.Qty };
            return new SaleLineDto(l.ProductId, l.Qty, null, l.UnitPrice, l.VariantId);
        }).ToList();
    }

    [HttpGet("export/excel")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Export)]
    public async Task<IActionResult> ExportExcel(
        [FromQuery] string? search,
        [FromQuery] string? statuses,
        [FromQuery] string? paymentMethod,
        [FromQuery] bool? isDelivery,
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to)
    {
        var storeId = RequiredStoreId;
        var query = dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive);

        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            query = query.Where(o => o.OrderNo.ToLower().Contains(s) ||
                                     (o.CustomerName != null && o.CustomerName.ToLower().Contains(s)));
        }
        if (!string.IsNullOrWhiteSpace(statuses))
        {
            var statusList = statuses.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Select(s => Enum.TryParse<PosSaleOrderStatus>(s, true, out var x) ? x : (PosSaleOrderStatus?)null)
                .Where(x => x.HasValue).Select(x => x!.Value).Distinct().ToList();
            if (statusList.Count > 0)
                query = query.Where(o => statusList.Contains(o.Status));
        }
        if (!string.IsNullOrWhiteSpace(paymentMethod))
            query = query.Where(o => o.PaymentMethod.Contains(paymentMethod.Trim()));
        if (isDelivery.HasValue)
            query = query.Where(o => o.IsDelivery == isDelivery.Value);
        if (from.HasValue)
            query = query.Where(o => (o.SaleDate ?? o.CreatedAt) >= from.Value.Date);
        if (to.HasValue)
            query = query.Where(o => (o.SaleDate ?? o.CreatedAt) < to.Value.Date.AddDays(1));

        var items = await query.OrderByDescending(o => o.SaleDate ?? o.CreatedAt).Take(5000).ToListAsync();

        using var workbook = new XLWorkbook();
        var ws = workbook.Worksheets.Add("Don hang");
        var headers = new[]
        {
            "Mã đơn", "Thời gian", "Trạng thái", "Khách hàng", "Giao hàng",
            "TT giao hàng", "Tạm tính", "Giảm giá", "Tổng", "Đã trả", "Còn lại", "Thanh toán", "Người bán"
        };
        var periodLabel = from.HasValue || to.HasValue
            ? $"{from?.ToString("dd/MM/yyyy") ?? "…"} – {to?.ToString("dd/MM/yyyy") ?? "…"}"
            : null;
        var meta = ReportExcelMeta.FromUser(User, "DANH SÁCH ĐƠN HÀNG", periodLabel, null,
            new[] { $"Tổng: {items.Count}" }, items.Count);
        var (headerRow, dataStartRow) = ReportExcelLayout.ApplyMeta(ws, meta, headers.Length);
        ReportExcelLayout.ApplyHeaderRow(ws, headerRow, headers);
        var row = dataStartRow;
        foreach (var o in items)
        {
            var dt = o.SaleDate ?? o.CreatedAt;
            ws.Cell(row, 1).Value = o.OrderNo;
            ws.Cell(row, 2).Value = dt.ToString("dd/MM/yyyy HH:mm");
            ws.Cell(row, 3).Value = o.Status switch
            {
                PosSaleOrderStatus.Draft => "Đang xử lý",
                PosSaleOrderStatus.Completed => "Hoàn thành",
                PosSaleOrderStatus.Cancelled => "Đã hủy",
                _ => o.Status.ToString()
            };
            ws.Cell(row, 4).Value = o.CustomerName ?? "Khách lẻ";
            ws.Cell(row, 5).Value = o.IsDelivery ? "Có" : "Không";
            ws.Cell(row, 6).Value = o.DeliveryStatus ?? "";
            ws.Cell(row, 7).Value = o.SubTotal;
            ws.Cell(row, 8).Value = o.Discount;
            ws.Cell(row, 9).Value = o.Total;
            ws.Cell(row, 10).Value = o.PaidAmount;
            ws.Cell(row, 11).Value = o.Total - o.PaidAmount;
            ws.Cell(row, 12).Value = o.PaymentMethod;
            ws.Cell(row, 13).Value = o.SoldBy ?? "";
            row++;
        }
        ws.Columns(1, headers.Length).AdjustToContents();
        using var stream = new MemoryStream();
        workbook.SaveAs(stream);
        return File(stream.ToArray(),
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            $"DonHang_{DateTime.Now:yyyyMMdd}.xlsx");
    }

    const string PriceOverrideDeniedMessage = "PRICE_OVERRIDE_REQUIRES_APPROVE";

    private async Task<(PosSaleOrder? order, List<PosSaleOrderLine>? lines, string? error)> BuildSaleAsync(
        Guid storeId,
        PosSaleOrder? existing,
        CreateSaleDto dto,
        bool complete,
        bool allowManualPriceOverride = false)
    {
        if (dto.Lines == null || dto.Lines.Count == 0)
        {
            // CreateSale / complete không cho trống; UpdateSale clear đã xử lý riêng.
            return (null, null, "Đơn hàng trống");
        }

        if (!allowManualPriceOverride)
        {
            if (dto.Discount > 0.009m)
                return (null, null, PriceOverrideDeniedMessage);
            if (dto.Lines.Any(l => l.DiscountAmount > 0.009m))
                return (null, null, PriceOverrideDeniedMessage);
        }

        if (dto.CustomerId.HasValue && !await dbContext.PosCustomers.AnyAsync(c =>
                c.Id == dto.CustomerId && c.StoreId == storeId && c.Deleted == null))
            return (null, null, "Khách hàng không hợp lệ");

        // Hồ sơ ngành yêu cầu chọn bàn/phòng trước khi giữ đơn / thanh toán.
        var sellSettings = await dbContext.PosStoreSellSettings.AsNoTracking()
            .FirstOrDefaultAsync(s => s.StoreId == storeId && s.Deleted == null);
        var resourceId = dto.ServiceResourceId ?? existing?.ServiceResourceId;
        if (sellSettings?.RequireResourceOnSale == true && !resourceId.HasValue)
            return (null, null, "Cần chọn bàn/phòng trước khi lưu đơn");

        SaleStockPlan? plan = null;
        if (complete)
        {
            var allowNeg = sellSettings?.AllowNegativeStock == true;
            var lineInputs = dto.Lines
                .Select(l => (l.ProductId, l.Qty, l.VariantId, l.UnitId, l.ToppingsJson))
                .ToList();
            var (p, stockErr) = await PosSaleStockHelper.PrepareSaleStockAsync(
                dbContext, storeId, PosSaleStockHelper.ExpandStockInputsWithToppings(lineInputs),
                allowNegativeStock: allowNeg);
            if (stockErr != null) return (null, null, stockErr);
            plan = p;
        }

        var productIds = dto.Lines.Select(l => l.ProductId).Distinct().ToList();
        var variantIds = dto.Lines.Where(l => l.VariantId.HasValue)
            .Select(l => l.VariantId!.Value).Distinct().ToList();
        var products = plan?.Products ?? await dbContext.PosProducts
            .Where(p => productIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
            .ToDictionaryAsync(p => p.Id);
        var variants = plan?.Variants ?? (variantIds.Count == 0
            ? new Dictionary<Guid, PosProductVariant>()
            : await dbContext.PosProductVariants
                .Where(v => variantIds.Contains(v.Id) && v.StoreId == storeId && v.Deleted == null && v.IsActive)
                .ToDictionaryAsync(v => v.Id));

        var now = DateTime.UtcNow;
        PosSaleOrder order;
        if (existing == null)
        {
            string orderNo;
            int? slot = null;
            if (complete)
            {
                orderNo = await PosSaleStockHelper.NextOrderNoAsync(dbContext, storeId, now);
            }
            else
            {
                slot = dto.InvoiceSlot;
                if (slot is null or < 1)
                {
                    var used = await dbContext.PosSaleOrders.AsNoTracking()
                        .Where(o => o.StoreId == storeId && o.Deleted == null
                            && o.Status == PosSaleOrderStatus.Draft && o.InvoiceSlot != null)
                        .Select(o => o.InvoiceSlot!.Value)
                        .ToListAsync();
                    slot = Enumerable.Range(1, 32).FirstOrDefault(i => !used.Contains(i));
                    if (slot <= 0) slot = used.DefaultIfEmpty(0).Max() + 1;
                }
                orderNo = PosDraftInvoiceSlots.TempOrderNo(slot.Value);
            }

            order = new PosSaleOrder
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                OrderNo = orderNo,
                InvoiceSlot = complete ? null : slot,
                IsActive = true,
                CreatedBy = CurrentUserEmail,
            };
        }
        else
        {
            order = existing;
        }

        order.Status = complete ? PosSaleOrderStatus.Completed : PosSaleOrderStatus.Draft;
        // Khóa chỉ gán sau khi biết có dòng hàng (BumpAfterSuccessfulSave / CreateSale).
        if (complete)
        {
            // Mã HDxxxx chỉ gán lúc thanh toán (Draft dùng TMP{slot}).
            if (PosDraftInvoiceSlots.IsTempOrderNo(order.OrderNo) || order.InvoiceSlot.HasValue
                || order.OrderNo.StartsWith("BAN", StringComparison.OrdinalIgnoreCase))
                order.OrderNo = await PosSaleStockHelper.NextOrderNoAsync(dbContext, storeId, now);
            order.InvoiceSlot = null;
            PosDraftLockHelper.Release(order);
        }
        else if (existing != null && dto.InvoiceSlot is > 0 && order.InvoiceSlot == null)
        {
            order.InvoiceSlot = dto.InvoiceSlot;
            if (PosDraftInvoiceSlots.IsTempOrderNo(order.OrderNo) || string.IsNullOrWhiteSpace(order.OrderNo))
                order.OrderNo = PosDraftInvoiceSlots.TempOrderNo(dto.InvoiceSlot.Value);
        }

        order.Discount = dto.Discount;
        order.PaymentMethod = string.IsNullOrWhiteSpace(dto.PaymentMethod) ? "Tiền mặt" : dto.PaymentMethod.Trim();
        order.CustomerId = dto.CustomerId;
        order.CustomerName = dto.CustomerName?.Trim();
        if (dto.CustomerId.HasValue && string.IsNullOrWhiteSpace(order.CustomerName))
        {
            var cust = await dbContext.PosCustomers.AsNoTracking()
                .FirstOrDefaultAsync(c => c.Id == dto.CustomerId && c.StoreId == storeId);
            order.CustomerName = cust?.Name;
        }
        if (string.IsNullOrWhiteSpace(order.CustomerName))
            order.CustomerName = "Bán cho người tiêu dùng";
        order.Note = dto.Note?.Trim();
        order.IsDelivery = dto.IsDelivery;
        order.DeliveryAddress = dto.DeliveryAddress?.Trim();
        order.DeliveryPhone = dto.DeliveryPhone?.Trim();
        order.DeliveryPartner = dto.DeliveryPartner?.Trim();
        order.DeliveryStatus = dto.IsDelivery
            ? (string.IsNullOrWhiteSpace(dto.DeliveryStatus) ? "Chờ giao" : dto.DeliveryStatus.Trim())
            : null;
        order.DeliveryDate = dto.DeliveryDate;
        order.SaleDate = complete ? now : order.SaleDate;
        await ResolveSoldByAsync(storeId, order, dto.SoldByEmployeeId, dto.SoldBy);
        order.SalesChannel = dto.SalesChannel?.Trim() ?? "Bán trực tiếp";
        order.ServiceResourceId = dto.ServiceResourceId ?? order.ServiceResourceId;
        order.ResourceSessionId = dto.ResourceSessionId ?? order.ResourceSessionId;
        order.ServiceStartedAt = dto.ServiceStartedAt ?? order.ServiceStartedAt;
        order.ServiceEndedAt = dto.ServiceEndedAt ?? order.ServiceEndedAt;
        if (complete && order.ServiceStartedAt.HasValue && !order.ServiceEndedAt.HasValue)
            order.ServiceEndedAt = now;
        if (dto.PriceListId.HasValue)
        {
            var pl = await dbContext.PosPriceLists.AsNoTracking()
                .FirstOrDefaultAsync(x => x.Id == dto.PriceListId && x.StoreId == storeId && x.Deleted == null);
            if (pl == null)
                return (null, null, "Bảng giá không hợp lệ");
            order.PriceListId = pl.Id;
            order.PriceListName = pl.Name;
        }
        else
        {
            var saleDay = (complete ? now : (order.SaleDate ?? now)).Date;
            var candidates = await dbContext.PosPriceLists.AsNoTracking()
                .Where(x => x.StoreId == storeId && x.Deleted == null && x.IsActive)
                .OrderByDescending(x => x.IsDefault).ThenBy(x => x.SortOrder)
                .ToListAsync();
            var defaultPl = candidates.FirstOrDefault(x =>
                x.IsDefault && PosPriceListResolver.IsApplicableOn(x, saleDay));
            defaultPl ??= candidates.FirstOrDefault(x =>
                !x.ValidFrom.HasValue && !x.ValidTo.HasValue);
            defaultPl ??= candidates.FirstOrDefault(x => PosPriceListResolver.IsApplicableOn(x, saleDay));
            if (defaultPl != null)
            {
                order.PriceListId = defaultPl.Id;
                order.PriceListName = defaultPl.Name;
            }
            else
            {
                order.PriceListName = string.IsNullOrWhiteSpace(dto.PriceListName)
                    ? "Bảng giá chung"
                    : dto.PriceListName.Trim();
            }
        }
        order.UpdatedAt = DateTime.UtcNow;
        order.UpdatedBy = CurrentUserEmail;

        Dictionary<string, decimal>? priceOverrides = null;
        if (order.PriceListId.HasValue)
        {
            priceOverrides = await PosPriceListResolver.LoadOverridesAsync(
                dbContext, storeId, order.PriceListId.Value);
        }

        var lines = new List<PosSaleOrderLine>();
        decimal subTotal = 0;
        decimal lineDiscountTotal = 0;

        // Pause phiên bàn — trừ khỏi phút tính giờ (draft + thanh toán).
        var sessionPauseAccum = 0;
        DateTime? sessionPausedAt = null;
        PosResourceSession? billingSession = null;
        if (order.ResourceSessionId.HasValue)
        {
            billingSession = await dbContext.PosResourceSessions.AsTracking()
                .FirstOrDefaultAsync(s => s.Id == order.ResourceSessionId
                    && s.StoreId == storeId && s.Deleted == null);
        }
        else if (order.ServiceResourceId.HasValue)
        {
            billingSession = await dbContext.PosResourceSessions.AsTracking()
                .Where(s => s.ResourceId == order.ServiceResourceId
                    && s.StoreId == storeId && s.Deleted == null
                    && (s.Status == PosResourceSessionStatus.Open
                        || s.Status == PosResourceSessionStatus.Paused))
                .OrderByDescending(s => s.StartedAt)
                .FirstOrDefaultAsync();
        }
        if (billingSession != null)
        {
            if (complete)
                PosServiceBillingHelper.FinalizeOpenPause(billingSession, DateTime.UtcNow);
            sessionPauseAccum = billingSession.AccumulatedPauseMinutes;
            if (!complete && billingSession.Status == PosResourceSessionStatus.Paused)
                sessionPausedAt = billingSession.PausedAt;
        }

        foreach (var line in dto.Lines)
        {
            if (!products.TryGetValue(line.ProductId, out var p))
                return (null, null, "Hàng hóa không hợp lệ hoặc đã ngừng kinh doanh");

            PosProductVariant? soldVariant = null;
            if (line.VariantId.HasValue)
            {
                if (!variants.TryGetValue(line.VariantId.Value, out soldVariant))
                    return (null, null, "Biến thể hàng hóa không hợp lệ");
            }

            var catalogPrice = soldVariant?.BasePrice ?? p.BasePrice;
            string? unitName = p.BaseUnitName;
            var lineName = soldVariant != null ? $"{p.Name} — {soldVariant.Name}" : p.Name;

            if (line.UnitId.HasValue)
            {
                var unit = await dbContext.PosProductUnits.AsNoTracking()
                    .FirstOrDefaultAsync(u => u.Id == line.UnitId && u.ProductId == p.Id && u.Deleted == null);
                if (unit != null)
                {
                    unitName = unit.UnitName;
                    catalogPrice = unit.BasePrice;
                }
            }
            else if (soldVariant?.AttributeJson != null)
            {
                try
                {
                    using var doc = System.Text.Json.JsonDocument.Parse(soldVariant.AttributeJson);
                    if (doc.RootElement.TryGetProperty("_unit", out var uEl))
                        unitName = uEl.GetString();
                }
                catch { /* ignore */ }
            }

            // Bảng giá thắng khi có override; cho phép sửa tay qua UnitPrice khi không có dòng giá.
            var listPrice = priceOverrides == null
                ? null
                : PosPriceListResolver.ResolvePrice(
                    priceOverrides, p.Id, line.VariantId, line.UnitId);
            if (!allowManualPriceOverride
                && listPrice == null
                && line.UnitPrice.HasValue
                && Math.Abs(line.UnitPrice.Value - catalogPrice) > 0.009m)
            {
                return (null, null, PriceOverrideDeniedMessage);
            }
            var unitPrice = listPrice ?? line.UnitPrice ?? catalogPrice;

            var grossLine = unitPrice * line.Qty;
            var discAmt = Math.Max(0, Math.Min(line.DiscountAmount, grossLine));
            var lineQty = line.Qty;
            decimal lineTotal;
            int? durationMinutes = line.DurationMinutes;
            int? billableMinutes = line.BillableMinutes;
            DateTime? lineStarted = line.ServiceStartedAt;
            DateTime? lineEnded = line.ServiceEndedAt;

            // Topping: cộng vào thành tiền, không gộp vào UnitPrice (tránh nhân đôi khi đọc lại).
            decimal toppingExtra = 0;
            string? toppingsJson = string.IsNullOrWhiteSpace(line.ToppingsJson)
                ? null
                : line.ToppingsJson.Trim();
            if (!string.IsNullOrWhiteSpace(toppingsJson))
            {
                try
                {
                    using var doc = System.Text.Json.JsonDocument.Parse(toppingsJson);
                    if (doc.RootElement.ValueKind == System.Text.Json.JsonValueKind.Array)
                    {
                        foreach (var el in doc.RootElement.EnumerateArray())
                        {
                            if (el.TryGetProperty("price", out var pEl) ||
                                el.TryGetProperty("Price", out pEl))
                                toppingExtra += pEl.GetDecimal();
                        }
                    }
                }
                catch { /* ignore bad json */ }
            }
            grossLine = (unitPrice + toppingExtra) * line.Qty;
            discAmt = Math.Max(0, Math.Min(line.DiscountAmount, grossLine));

            if (p.ProductType == PosProductType.Service
                && p.ServiceBillingMode is PosServiceBillingMode.PerHour or PosServiceBillingMode.PerMinute)
            {
                var started = lineStarted ?? order.ServiceStartedAt ?? DateTime.UtcNow;
                var ended = lineEnded ?? (complete ? DateTime.UtcNow : (DateTime?)null);
                var elapsed = PosServiceBillingHelper.CalcElapsedMinutes(
                    started, ended, sessionPauseAccum, sessionPausedAt);
                if (durationMinutes is null or <= 0) durationMinutes = elapsed;
                billableMinutes = PosServiceBillingHelper.CalcBillableMinutes(
                    durationMinutes ?? elapsed,
                    p.ServiceBillingMode,
                    p.MinBillMinutes,
                    p.BillRoundMinutes,
                    p.GraceMinutes,
                    p.RoundAfterMinutes);
                lineQty = PosServiceBillingHelper.CalcBillableQty(
                    p.ServiceBillingMode, billableMinutes.Value, line.Qty);
                lineStarted ??= started;
                if (complete) lineEnded ??= ended ?? DateTime.UtcNow;
                grossLine = (unitPrice + toppingExtra) * lineQty;
                discAmt = Math.Max(0, Math.Min(line.DiscountAmount, grossLine));
                lineTotal = grossLine - discAmt;
            }
            else
            {
                lineTotal = grossLine - discAmt;
            }

            subTotal += grossLine;
            lineDiscountTotal += discAmt;
            var kitchenSent = line.KitchenSentQty is > 0
                ? Math.Min(line.KitchenSentQty.Value, lineQty)
                : 0;
            lines.Add(new PosSaleOrderLine
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                SaleOrderId = order.Id,
                ProductId = p.Id,
                VariantId = soldVariant?.Id,
                ProductName = lineName,
                UnitName = unitName,
                UnitId = line.UnitId,
                Qty = lineQty,
                UnitPrice = unitPrice,
                DiscountAmount = discAmt,
                LineTotal = lineTotal,
                LineNote = string.IsNullOrWhiteSpace(line.LineNote) ? null : line.LineNote.Trim(),
                ToppingsJson = toppingsJson,
                DurationMinutes = durationMinutes,
                BillableMinutes = billableMinutes,
                ServiceStartedAt = lineStarted,
                ServiceEndedAt = lineEnded,
                AssignedEmployeeId = line.AssignedEmployeeId,
                KitchenSentQty = kitchenSent,
                KitchenSentAt = kitchenSent > 0 ? DateTime.UtcNow : null,
                IsActive = true,
                CreatedBy = CurrentUserEmail,
            });
        }

        order.SubTotal = subTotal;
        var merchandise = subTotal - lineDiscountTotal - dto.Discount;
        if (merchandise < 0) merchandise = 0;

        var voucherApply = await PosCustomerFinanceHelper.TryApplyVoucherAsync(
            dbContext, storeId, dto.VoucherCode, merchandise, dto.CustomerId);
        if (voucherApply?.Error != null)
            return (null, null, voucherApply.Error);
        decimal voucherDiscount = 0;
        PosVoucher? appliedVoucher = null;
        if (voucherApply != null)
        {
            appliedVoucher = voucherApply.Voucher;
            voucherDiscount = voucherApply.DiscountAmount;
            order.VoucherId = appliedVoucher.Id;
            order.VoucherCode = appliedVoucher.Code;
            order.VoucherDiscount = voucherDiscount;
        }
        else
        {
            order.VoucherId = null;
            order.VoucherCode = null;
            order.VoucherDiscount = 0;
        }

        var afterVoucher = merchandise - voucherDiscount;
        if (dto.PointsToRedeem > 0)
        {
            if (!dto.CustomerId.HasValue)
                return (null, null, "Cần chọn khách hàng để đổi điểm");
            var ptCust = await dbContext.PosCustomers.AsNoTracking()
                .FirstOrDefaultAsync(c => c.Id == dto.CustomerId && c.StoreId == storeId && c.Deleted == null);
            if (ptCust == null) return (null, null, "Khách hàng không hợp lệ");
            var (ptDisc, ptRedeem, ptErr) = PosCustomerFinanceHelper.CalcPointsRedeem(
                dto.PointsToRedeem, ptCust.PointBalance, afterVoucher);
            if (ptErr != null) return (null, null, ptErr);
            order.PointsRedeemed = ptRedeem;
            order.PointsDiscount = ptDisc;
        }
        else
        {
            order.PointsRedeemed = 0;
            order.PointsDiscount = 0;
        }

        order.Total = Math.Max(0, afterVoucher - order.PointsDiscount);
        if (complete)
            order.VatAmount = Math.Max(0, dto.VatAmount);
        order.PointsEarned = complete && dto.CustomerId.HasValue
            ? PosCustomerFinanceHelper.CalcPointsEarn(order.Total)
            : 0;

        var paymentInputs = dto.Payments?
            .Where(p => p.Amount > 0)
            .ToList() ?? [];
        if (paymentInputs.Count == 0 && dto.PaidAmount > 0)
        {
            paymentInputs.Add(new SalePaymentInputDto(
                dto.PaidAmount,
                string.IsNullOrWhiteSpace(dto.PaymentMethod) ? "Tiền mặt" : dto.PaymentMethod.Trim()));
        }

        if (paymentInputs.Count > 0)
        {
            order.PaidAmount = paymentInputs.Sum(p => p.Amount);
            order.PaymentMethod = string.Join(" + ", paymentInputs.Select(p => p.PaymentMethod));
        }
        else
        {
            order.PaidAmount = dto.PaidAmount;
        }

        var paymentSync = paymentInputs
            .Select(p => new PosFinanceSyncHelper.SalePaymentSync(p.Amount, p.PaymentMethod, p.BankAccountId))
            .ToList();

        if (complete && plan != null)
        {
            var warrantyLines = dto.Lines
                .Where(l => products.TryGetValue(l.ProductId, out var wp) &&
                            PosSaleWarrantyHelper.NeedsRegistration(wp))
                .Select(l => (l, products[l.ProductId]))
                .ToList();
            if (warrantyLines.Count > 0)
            {
                var warrantyErr = await PosSaleWarrantyHelper.ValidateSerialsAsync(
                    dbContext, storeId, warrantyLines);
                if (warrantyErr != null) return (null, null, warrantyErr);
            }

            await PosSaleStockHelper.ApplySaleStockAsync(
                dbContext, storeId, order, lines, plan, CurrentUserEmail);
            await PosSaleStockHelper.UpdateCustomerOnSaleCompleteAsync(dbContext, storeId, order);
            if (order.CustomerId.HasValue)
            {
                var saleCustomer = await dbContext.PosCustomers.AsTracking()
                    .FirstOrDefaultAsync(c => c.Id == order.CustomerId && c.StoreId == storeId && c.Deleted == null);
                if (saleCustomer != null)
                {
                    await PosCustomerFinanceHelper.ApplyPointsOnSaleCompleteAsync(
                        dbContext, storeId, order, saleCustomer, CurrentUserEmail);
                    if (appliedVoucher != null)
                    {
                        appliedVoucher.UsedCount += 1;
                        appliedVoucher.UpdatedAt = DateTime.UtcNow;
                    }
                }
            }
            await PosSellIndustryController.GrantSessionPacksOnSaleCompleteAsync(
                dbContext, storeId, order, lines, CurrentUserEmail);
            if (order.ResourceSessionId.HasValue)
            {
                var sess = await dbContext.PosResourceSessions.AsTracking()
                    .FirstOrDefaultAsync(s => s.Id == order.ResourceSessionId && s.StoreId == storeId
                        && s.Deleted == null);
                if (sess != null && sess.Status != PosResourceSessionStatus.Closed)
                {
                    PosServiceBillingHelper.FinalizeOpenPause(sess, DateTime.UtcNow);
                    sess.Status = PosResourceSessionStatus.Closed;
                    sess.EndedAt = DateTime.UtcNow;
                    sess.UpdatedAt = DateTime.UtcNow;
                    sess.UpdatedBy = CurrentUserEmail;

                    // Sau thanh toán → bàn cần dọn, không còn «đang dùng».
                    var table = await dbContext.PosServiceResources.AsTracking()
                        .FirstOrDefaultAsync(r => r.Id == sess.ResourceId && r.StoreId == storeId
                            && r.Deleted == null);
                    if (table != null)
                    {
                        table.NeedsCleaning = false;
                        table.UpdatedAt = DateTime.UtcNow;
                        table.UpdatedBy = CurrentUserEmail;
                    }
                }
            }
            // Phòng trường hợp ResourceSessionId null nhưng vẫn còn phiên mở trên bàn.
            else if (order.ServiceResourceId.HasValue)
            {
                var live = await dbContext.PosResourceSessions.AsTracking()
                    .Where(s => s.ResourceId == order.ServiceResourceId
                        && s.StoreId == storeId && s.Deleted == null
                        && (s.Status == PosResourceSessionStatus.Open
                            || s.Status == PosResourceSessionStatus.Paused))
                    .ToListAsync();
                foreach (var sess in live)
                {
                    PosServiceBillingHelper.FinalizeOpenPause(sess, DateTime.UtcNow);
                    sess.Status = PosResourceSessionStatus.Closed;
                    sess.EndedAt = DateTime.UtcNow;
                    sess.UpdatedAt = DateTime.UtcNow;
                    sess.UpdatedBy = CurrentUserEmail;
                }
                if (live.Count > 0)
                {
                    var table = await dbContext.PosServiceResources.AsTracking()
                        .FirstOrDefaultAsync(r => r.Id == order.ServiceResourceId && r.StoreId == storeId
                            && r.Deleted == null);
                    if (table != null)
                    {
                        table.NeedsCleaning = false;
                        table.UpdatedAt = DateTime.UtcNow;
                        table.UpdatedBy = CurrentUserEmail;
                    }
                }
            }
            await PosFinanceSyncHelper.SyncSaleOnCompleteAsync(
                dbContext, order, CurrentUserId, paymentSync);
            await PosSaleWarrantyHelper.RegisterOnSaleAsync(
                dbContext, storeId, order, lines, dto.Lines, products, CurrentUserEmail);

            var lowStockItems = plan.Products.Values
                .Select(p => (p.Id, p.Name, p.OnHandQty, p.MinStockQty));
            await PosNotificationHelper.NotifyLowStockAsync(
                notificationService, dbContext, storeId, lowStockItems, CurrentUserId);
        }

        return (order, lines, null);
    }

    /// <summary>
    /// Sau thanh toán: đóng mọi phiên trên bàn + soft-delete draft sót
    /// (tránh Occupied / «chờ bếp» ghost khi đơn đã TT).
    /// </summary>
    async Task CloseResourceSessionForCompletedOrderAsync(Guid storeId, PosSaleOrder order)
    {
        var now = DateTime.UtcNow;
        var by = CurrentUserEmail;
        Guid? tableId = order.ServiceResourceId;

        if (order.ResourceSessionId.HasValue)
        {
            var sessResId = await dbContext.PosResourceSessions.AsNoTracking()
                .Where(s => s.Id == order.ResourceSessionId && s.Deleted == null)
                .Select(s => (Guid?)s.ResourceId)
                .FirstOrDefaultAsync();
            tableId ??= sessResId;
        }

        if (!tableId.HasValue)
        {
            tableId = await dbContext.PosResourceSessions.AsNoTracking()
                .Where(s => s.SaleOrderId == order.Id && s.Deleted == null)
                .OrderByDescending(s => s.StartedAt)
                .Select(s => (Guid?)s.ResourceId)
                .FirstOrDefaultAsync();
        }

        // 1) Đóng mọi phiên Open/Paused gắn đơn này.
        await dbContext.PosResourceSessions
            .Where(s => s.SaleOrderId == order.Id && s.Deleted == null
                && (s.Status == PosResourceSessionStatus.Open
                    || s.Status == PosResourceSessionStatus.Paused))
            .ExecuteUpdateAsync(s => s
                .SetProperty(x => x.Status, PosResourceSessionStatus.Closed)
                .SetProperty(x => x.EndedAt, now)
                .SetProperty(x => x.UpdatedAt, now)
                .SetProperty(x => x.UpdatedBy, by));

        if (order.ResourceSessionId.HasValue)
        {
            await dbContext.PosResourceSessions
                .Where(s => s.Id == order.ResourceSessionId && s.Deleted == null
                    && s.Status != PosResourceSessionStatus.Closed)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(x => x.Status, PosResourceSessionStatus.Closed)
                    .SetProperty(x => x.EndedAt, now)
                    .SetProperty(x => x.UpdatedAt, now)
                    .SetProperty(x => x.UpdatedBy, by));
        }

        if (tableId.HasValue)
        {
            // 2) Đóng toàn bộ phiên còn mở trên bàn (Holding / draft khác).
            await dbContext.PosResourceSessions
                .Where(s => s.ResourceId == tableId && s.Deleted == null
                    && (s.Status == PosResourceSessionStatus.Open
                        || s.Status == PosResourceSessionStatus.Paused))
                .ExecuteUpdateAsync(s => s
                    .SetProperty(x => x.Status, PosResourceSessionStatus.Closed)
                    .SetProperty(x => x.EndedAt, now)
                    .SetProperty(x => x.UpdatedAt, now)
                    .SetProperty(x => x.UpdatedBy, by));

            // 3) Soft-delete mọi Draft còn gắn bàn (kể cả có món ghost / chờ bếp).
            // F&B: một bàn = một bill; đã TT → bàn phải Free.
            var leftoverIds = await dbContext.PosSaleOrders
                .Where(o => o.StoreId == storeId && o.Deleted == null
                    && o.Status == PosSaleOrderStatus.Draft
                    && o.ServiceResourceId == tableId
                    && o.Id != order.Id)
                .Select(o => o.Id)
                .ToListAsync();
            if (leftoverIds.Count > 0)
            {
                await dbContext.PosSaleOrders
                    .Where(o => leftoverIds.Contains(o.Id) && o.StoreId == storeId)
                    .ExecuteUpdateAsync(o => o
                        .SetProperty(x => x.Deleted, now)
                        .SetProperty(x => x.DeletedBy, by)
                        .SetProperty(x => x.UpdatedAt, now)
                        .SetProperty(x => x.UpdatedBy, by)
                        .SetProperty(x => x.ServiceEndedAt, now)
                        .SetProperty(x => x.ResourceSessionId, (Guid?)null)
                        .SetProperty(x => x.ServiceResourceId, (Guid?)null)
                        .SetProperty(x => x.LockedByUserId, (Guid?)null)
                        .SetProperty(x => x.LockedByEmployeeId, (Guid?)null)
                        .SetProperty(x => x.LockedByDeviceId, (string?)null)
                        .SetProperty(x => x.LockedByDeviceName, (string?)null)
                        .SetProperty(x => x.LockedByDisplayName, (string?)null)
                        .SetProperty(x => x.LockedAt, (DateTime?)null)
                        .SetProperty(x => x.LockExpiresAt, (DateTime?)null));
            }

            await dbContext.PosServiceResources
                .Where(r => r.Id == tableId && r.StoreId == storeId && r.Deleted == null)
                .ExecuteUpdateAsync(r => r
                    .SetProperty(x => x.NeedsCleaning, false)
                    .SetProperty(x => x.UpdatedAt, now)
                    .SetProperty(x => x.UpdatedBy, by));

            await dbContext.PosResourceReservations
                .Where(x => x.ResourceId == tableId && x.Deleted == null
                    && (x.StoreId == storeId || x.StoreId == Guid.Empty)
                    && x.Status == PosResourceReservationStatus.Booked)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(x => x.Status, PosResourceReservationStatus.Seated)
                    .SetProperty(x => x.UpdatedAt, now)
                    .SetProperty(x => x.UpdatedBy, by)
                    .SetProperty(x => x.Deleted, now));
        }

        // Đơn đã TT: nhả khóa + bỏ gắn phiên (giữ ServiceResourceId để in/báo cáo).
        order.ResourceSessionId = null;
        PosDraftLockHelper.Release(order);
        order.UpdatedAt = now;
        order.UpdatedBy = by;
        await dbContext.SaveChangesAsync();
    }

    private async Task ResolveSoldByAsync(
        Guid storeId, PosSaleOrder order, Guid? soldByEmployeeId, string? soldByFallback)
    {
        var employeeId = soldByEmployeeId ?? EmployeeId;
        if (employeeId.HasValue)
        {
            var emp = await dbContext.Employees.AsNoTracking()
                .FirstOrDefaultAsync(e => e.Id == employeeId.Value &&
                                          e.StoreId == storeId && e.Deleted == null);
            if (emp != null)
            {
                order.SoldByEmployeeId = emp.Id;
                var name = (emp.LastName + " " + emp.FirstName).Trim();
                order.SoldBy = !string.IsNullOrWhiteSpace(name)
                    ? name
                    : soldByFallback?.Trim() ?? emp.CompanyEmail ?? CurrentUserEmail;
                return;
            }
        }

        order.SoldByEmployeeId = null;
        order.SoldBy = soldByFallback?.Trim() ?? CurrentUserEmail;
    }
}
