using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

public partial class PosSalesController
{
    /// <summary>
    /// Danh sách Draft theo slot hiện có. Đảm bảo tối thiểu DefaultCount (3).
    /// Luôn thu gọn HĐ trống thừa (vd. cũ 8) xuống max(DefaultCount, số HĐ còn hàng).
    /// HĐ trống vừa tạo (&lt; 2 phút) được giữ để nút + không bị poll xóa ngay.
    /// </summary>
    [HttpGet("invoice-slots")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetInvoiceSlots(
        [FromQuery] int? count = null,
        [FromQuery] bool pruneEmpty = false,
        [FromQuery] string? deviceId = null,
        [FromQuery] string? deviceName = null)
    {
        var storeId = RequiredStoreId;
        // Poll 4s chỉ đọc — không prune/ensure nặng mỗi lần.
        // pruneEmpty=true lúc mở màn bán / thêm slot: thu gọn HĐ trống thừa.
        if (pruneEmpty)
        {
            await EnsureInvoiceSlotsAsync(storeId, PosDraftInvoiceSlots.DefaultCount);
            await PruneEmptySurplusSlotsAsync(storeId, PosDraftInvoiceSlots.DefaultCount);
        }
        else
        {
            var hasSlot = await dbContext.PosSaleOrders.AsNoTracking()
                .AnyAsync(o => o.StoreId == storeId && o.Deleted == null
                    && o.Status == PosSaleOrderStatus.Draft && o.InvoiceSlot != null);
            if (!hasSlot)
                await EnsureInvoiceSlotsAsync(storeId, PosDraftInvoiceSlots.DefaultCount);
        }

        return Ok(AppResponse<object>.Success(await BuildInvoiceSlotsPayloadAsync(storeId, deviceId, deviceName)));
    }

    /// <summary>Thêm 1 hóa đơn trống (slot kế tiếp trống).</summary>
    [HttpPost("invoice-slots")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> AddInvoiceSlot(
        [FromQuery] string? deviceId = null,
        [FromQuery] string? deviceName = null)
    {
        var storeId = RequiredStoreId;
        var used = await dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null
                && o.Status == PosSaleOrderStatus.Draft && o.InvoiceSlot != null)
            .Select(o => o.InvoiceSlot!.Value)
            .ToListAsync();
        if (used.Count >= PosDraftInvoiceSlots.MaxCount)
            return BadRequest(AppResponse<object>.Fail($"Tối đa {PosDraftInvoiceSlots.MaxCount} hóa đơn"));

        var slot = Enumerable.Range(1, PosDraftInvoiceSlots.MaxCount).FirstOrDefault(i => !used.Contains(i));
        if (slot <= 0)
            return BadRequest(AppResponse<object>.Fail("Không còn slot trống"));

        var now = DateTime.UtcNow;
        var order = new PosSaleOrder
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            OrderNo = PosDraftInvoiceSlots.TempOrderNo(slot),
            InvoiceSlot = slot,
            Status = PosSaleOrderStatus.Draft,
            IsActive = true,
            CustomerName = "Bán cho người tiêu dùng",
            PaymentMethod = "Tiền mặt",
            CreatedBy = CurrentUserEmail,
            CreatedAt = now,
            SaleDate = now,
        };
        dbContext.PosSaleOrders.Add(order);
        try
        {
            await dbContext.SaveChangesAsync();
        }
        catch (DbUpdateException)
        {
            return Ok(AppResponse<object>.Success(await BuildInvoiceSlotsPayloadAsync(storeId, deviceId, deviceName)));
        }

        var payload = await BuildInvoiceSlotsPayloadDictAsync(storeId, deviceId, deviceName);
        payload["addedSlot"] = slot;
        payload["addedId"] = order.Id;
        return Ok(AppResponse<object>.Success(payload));
    }

    /// <summary>Xóa 1 slot hóa đơn (soft-delete Draft). Từ chối nếu còn hàng và force=false.</summary>
    [HttpDelete("invoice-slots/{slot:int}")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> RemoveInvoiceSlot(
        int slot,
        [FromQuery] bool force = false,
        [FromQuery] string? deviceId = null,
        [FromQuery] string? deviceName = null)
    {
        var storeId = RequiredStoreId;
        if (slot < 1)
            return BadRequest(AppResponse<object>.Fail("Slot không hợp lệ"));

        // DbContext mặc định NoTracking — bắt buộc AsTracking để SaveChangesAsync thực sự xóa slot.
        var drafts = await dbContext.PosSaleOrders.AsTracking()
            .Include(o => o.Lines)
            .Where(o => o.StoreId == storeId && o.Deleted == null
                && o.Status == PosSaleOrderStatus.Draft && o.InvoiceSlot != null)
            .ToListAsync();

        if (drafts.Count <= PosDraftInvoiceSlots.MinCount)
            return BadRequest(AppResponse<object>.Fail("Phải giữ ít nhất 1 hóa đơn"));

        var order = drafts.FirstOrDefault(o => o.InvoiceSlot == slot);
        if (order == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy hóa đơn"));

        var lineCount = order.Lines?.Count(l => l.Deleted == null) ?? 0;
        if (lineCount > 0 && !force)
            return Conflict(AppResponse<object>.Fail("Hóa đơn còn hàng — xác nhận xóa hết rồi đóng"));

        var priorLines = (order.Lines ?? [])
            .Where(l => l.Deleted == null)
            .Select(l => (l.ProductId, l.Qty, l.VariantId, l.UnitId, l.ToppingsJson))
            .ToList();
        if (priorLines.Count > 0)
        {
            var releaseErr = await PosSaleStockHelper.SyncDraftStockReservationAsync(
                dbContext, storeId, priorLines, [], allowNegativeStock: true);
            if (releaseErr != null)
                return BadRequest(AppResponse<object>.Fail(releaseErr));
        }

        if (order.Lines != null && order.Lines.Count > 0)
            dbContext.PosSaleOrderLines.RemoveRange(order.Lines.Where(l => l.Deleted == null));

        PosDraftLockHelper.Release(order);
        order.InvoiceSlot = null;
        order.Deleted = DateTime.UtcNow;
        order.UpdatedAt = DateTime.UtcNow;
        order.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<object>.Success(await BuildInvoiceSlotsPayloadAsync(storeId, deviceId, deviceName)));
    }

    async Task<object> BuildInvoiceSlotsPayloadAsync(Guid storeId, string? deviceId, string? deviceName)
        => await BuildInvoiceSlotsPayloadDictAsync(storeId, deviceId, deviceName);

    async Task<Dictionary<string, object?>> BuildInvoiceSlotsPayloadDictAsync(
        Guid storeId, string? deviceId, string? deviceName)
    {
        var drafts = await dbContext.PosSaleOrders
            .AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null
                && o.Status == PosSaleOrderStatus.Draft
                && o.InvoiceSlot != null)
            .OrderBy(o => o.InvoiceSlot)
            .ToListAsync();

        var ids = drafts.Select(d => d.Id).ToList();
        var lineCounts = await dbContext.PosSaleOrderLines.AsNoTracking()
            .Where(l => ids.Contains(l.SaleOrderId) && l.Deleted == null)
            .GroupBy(l => l.SaleOrderId)
            .Select(g => new { SaleOrderId = g.Key, Count = g.Count() })
            .ToDictionaryAsync(x => x.SaleOrderId, x => x.Count);

        var actor = CurrentLockActor(deviceId, deviceName);
        var items = drafts.Select(o =>
        {
            var snap = PosDraftLockHelper.Snapshot(o, actor, lineCounts.GetValueOrDefault(o.Id));
            return new
            {
                o.Id,
                o.OrderNo,
                Status = o.Status.ToString(),
                InvoiceSlot = o.InvoiceSlot,
                DisplayLabel = $"Hóa đơn {o.InvoiceSlot}",
                o.SubTotal,
                o.Discount,
                o.Total,
                o.CustomerName,
                LineCount = lineCounts.GetValueOrDefault(o.Id),
                snap.LockVersion,
                snap.IsLocked,
                snap.IsLockedByMe,
                snap.LockedByDisplayName,
                snap.LockedByDeviceId,
                snap.LockedByDeviceName,
                snap.LockedAt,
                snap.LockExpiresAt,
            };
        }).ToList();

        return new Dictionary<string, object?>
        {
            ["count"] = items.Count,
            ["items"] = items,
        };
    }

    /// <summary>
    /// Bổ sung Draft trống tới tối thiểu <paramref name="minCount"/>.
    /// Chỉ tạo thêm khi tổng số slot &lt; minCount — không lấp số slot đã xóa
    /// (tránh xóa HĐ 5 rồi GET tạo lại slot 5).
    /// </summary>
    async Task EnsureInvoiceSlotsAsync(Guid storeId, int minCount)
    {
        var existing = await dbContext.PosSaleOrders
            .Where(o => o.StoreId == storeId && o.Deleted == null
                && o.Status == PosSaleOrderStatus.Draft && o.InvoiceSlot != null)
            .Select(o => o.InvoiceSlot!.Value)
            .ToListAsync();
        var used = existing.ToHashSet();
        var target = Math.Min(Math.Max(minCount, PosDraftInvoiceSlots.MinCount), PosDraftInvoiceSlots.MaxCount);
        if (used.Count >= target) return;

        var need = target - used.Count;
        var now = DateTime.UtcNow;
        for (var slot = 1; need > 0 && slot <= PosDraftInvoiceSlots.MaxCount; slot++)
        {
            if (used.Contains(slot)) continue;
            dbContext.PosSaleOrders.Add(new PosSaleOrder
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                OrderNo = PosDraftInvoiceSlots.TempOrderNo(slot),
                InvoiceSlot = slot,
                Status = PosSaleOrderStatus.Draft,
                IsActive = true,
                CustomerName = "Bán cho người tiêu dùng",
                PaymentMethod = "Tiền mặt",
                CreatedBy = CurrentUserEmail,
                CreatedAt = now,
                SaleDate = now,
            });
            used.Add(slot);
            need--;
        }
        if (dbContext.ChangeTracker.HasChanges())
        {
            try { await dbContext.SaveChangesAsync(); }
            catch (DbUpdateException) { /* unique race — ok */ }
        }
    }

    /// <summary>
    /// Xóa mềm slot trống thừa xuống max(keepAtLeast, số draft còn hàng).
    /// Không đụng HĐ còn dòng. Ưu tiên xóa HĐ trống cũ; HĐ mới &lt; 2 phút chỉ xóa nếu vẫn thừa.
    /// </summary>
    async Task PruneEmptySurplusSlotsAsync(Guid storeId, int keepAtLeast)
    {
        keepAtLeast = Math.Max(PosDraftInvoiceSlots.MinCount, keepAtLeast);
        // DbContext mặc định NoTracking — bắt buộc AsTracking để SaveChangesAsync thực sự prune.
        var drafts = await dbContext.PosSaleOrders.AsTracking()
            .Include(o => o.Lines)
            .Where(o => o.StoreId == storeId && o.Deleted == null
                && o.Status == PosSaleOrderStatus.Draft && o.InvoiceSlot != null)
            .OrderBy(o => o.InvoiceSlot)
            .ToListAsync();

        var nonEmptyCount = drafts.Count(o => (o.Lines?.Count(l => l.Deleted == null) ?? 0) > 0);
        keepAtLeast = Math.Max(keepAtLeast, nonEmptyCount);
        if (drafts.Count <= keepAtLeast) return;

        var surplus = drafts.Count - keepAtLeast;
        var now = DateTime.UtcNow;
        var freshCutoff = now.AddMinutes(-2);
        var empties = drafts
            .Where(o => (o.Lines?.Count(l => l.Deleted == null) ?? 0) == 0)
            .ToList();
        var stale = empties
            .Where(o => o.CreatedAt < freshCutoff)
            .OrderByDescending(o => o.InvoiceSlot)
            .ToList();
        var fresh = empties
            .Where(o => o.CreatedAt >= freshCutoff)
            .OrderByDescending(o => o.InvoiceSlot)
            .ToList();
        var toPrune = stale.Take(surplus).ToList();
        if (toPrune.Count < surplus)
            toPrune.AddRange(fresh.Take(surplus - toPrune.Count));
        if (toPrune.Count == 0) return;

        foreach (var o in toPrune)
        {
            if (drafts.Count <= PosDraftInvoiceSlots.MinCount) break;
            PosDraftLockHelper.Release(o, now);
            o.InvoiceSlot = null;
            o.Deleted = now;
            o.UpdatedAt = now;
            o.UpdatedBy = CurrentUserEmail;
            drafts.Remove(o);
        }
        if (dbContext.ChangeTracker.HasChanges())
            await dbContext.SaveChangesAsync();
    }

    /// <summary>Sau khi TT slot — tạo lại Draft trống cho cùng số hóa đơn (giữ tab).</summary>
    async Task RecreateInvoiceSlotIfNeededAsync(Guid storeId, int? slot)
    {
        if (slot is null or < 1) return;
        var exists = await dbContext.PosSaleOrders.AnyAsync(o =>
            o.StoreId == storeId && o.Deleted == null
            && o.Status == PosSaleOrderStatus.Draft && o.InvoiceSlot == slot);
        if (exists) return;
        var now = DateTime.UtcNow;
        // LockVersion >= 1 để máy khác poll thấy version đổi / id mới và hydrate giỏ trống.
        dbContext.PosSaleOrders.Add(new PosSaleOrder
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            OrderNo = PosDraftInvoiceSlots.TempOrderNo(slot.Value),
            InvoiceSlot = slot,
            Status = PosSaleOrderStatus.Draft,
            IsActive = true,
            CustomerName = "Bán cho người tiêu dùng",
            PaymentMethod = "Tiền mặt",
            LockVersion = 1,
            CreatedBy = CurrentUserEmail,
            CreatedAt = now,
            SaleDate = now,
        });
        try { await dbContext.SaveChangesAsync(); }
        catch (DbUpdateException) { }
    }
}
