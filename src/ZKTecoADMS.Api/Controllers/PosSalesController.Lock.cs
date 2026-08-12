using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

public partial class PosSalesController
{
    public record DraftLockRequestDto(
        string? DeviceId = null,
        string? DeviceName = null,
        bool Force = false);

    public record DraftLockStateDto(
        Guid OrderId,
        string OrderNo,
        int LockVersion,
        bool IsLocked,
        bool IsLockedByMe,
        Guid? LockedByUserId,
        Guid? LockedByEmployeeId,
        string? LockedByDisplayName,
        string? LockedByDeviceId,
        string? LockedByDeviceName,
        DateTime? LockedAt,
        DateTime? LockExpiresAt);

    PosDraftLockHelper.LockActor CurrentLockActor(string? deviceId, string? deviceName)
    {
        var display = CurrentUserEmail;
        if (string.IsNullOrWhiteSpace(display))
            display = CurrentUserId.ToString("N")[..8];
        return new PosDraftLockHelper.LockActor(
            CurrentUserId,
            EmployeeId,
            display!,
            deviceId,
            deviceName);
    }

    async Task<int> CountActiveLinesAsync(Guid orderId)
        => await dbContext.PosSaleOrderLines.AsNoTracking()
            .CountAsync(l => l.SaleOrderId == orderId && l.Deleted == null);

    DraftLockStateDto MapLockState(
        Domain.Entities.PosSaleOrder order,
        PosDraftLockHelper.LockActor actor,
        int lineCount)
    {
        var snap = PosDraftLockHelper.Snapshot(order, actor, lineCount);
        return new(
            order.Id, order.OrderNo, snap.LockVersion, snap.IsLocked, snap.IsLockedByMe,
            snap.LockedByUserId, snap.LockedByEmployeeId, snap.LockedByDisplayName,
            snap.LockedByDeviceId, snap.LockedByDeviceName, snap.LockedAt, snap.LockExpiresAt);
    }

    async Task<bool> IsMultiDeviceDraftLockEnabledAsync(Guid storeId)
    {
        // Khóa draft luôn bật (1 máy hay nhiều máy) — đồng bộ bàn/đơn.
        // Cột EnableMultiDeviceDraftLock giữ tương thích schema, không còn cổng tắt.
        _ = storeId;
        return true;
    }

    /// <summary>
    /// Claim / force-take. HĐ trống: nhả chỗ cũ (nếu có) — không chiếm chỗ / không bump version.
    /// </summary>
    [HttpPost("{id:guid}/lock")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<DraftLockStateDto>>> LockDraft(
        Guid id, [FromBody] DraftLockRequestDto? dto = null)
    {
        var storeId = RequiredStoreId;
        // DbContext mặc định NoTracking — bắt buộc AsTracking để SaveChangesAsync thực sự ghi lock.
        var order = await dbContext.PosSaleOrders.AsTracking()
            .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId && o.Deleted == null);
        if (order == null)
            return NotFound(AppResponse<DraftLockStateDto>.Fail("Không tìm thấy đơn hàng"));
        if (order.Status != PosSaleOrderStatus.Draft)
            return BadRequest(AppResponse<DraftLockStateDto>.Fail("Chỉ khóa được đơn tạm"));

        var lineCount = await CountActiveLinesAsync(id);
        var actor = CurrentLockActor(dto?.DeviceId, dto?.DeviceName);

        // 1 máy / tắt khóa đa máy: không chiếm chỗ — luôn cho sửa.
        if (!await IsMultiDeviceDraftLockEnabledAsync(storeId))
        {
            if (PosDraftLockHelper.IsLockActive(order))
            {
                PosDraftLockHelper.Release(order);
                await dbContext.SaveChangesAsync();
            }
            return Ok(AppResponse<DraftLockStateDto>.Success(MapLockState(order, actor, lineCount)));
        }

        // HĐ trống thường (TMP): không khóa — dọn seat cũ.
        // Đơn gắn bàn (ServiceResourceId): vẫn khóa kể cả Holding chưa có món.
        var tableBound = order.ServiceResourceId.HasValue;
        if (lineCount <= 0 && !tableBound)
        {
            if (PosDraftLockHelper.IsLockActive(order))
            {
                PosDraftLockHelper.Release(order);
                await dbContext.SaveChangesAsync();
            }
            return Ok(AppResponse<DraftLockStateDto>.Success(MapLockState(order, actor, lineCount)));
        }

        var force = dto?.Force == true;
        // Chỉ bump khi cướp khóa từ máy/user khác — force trên chính mình không đụng LockVersion.
        var stealing = PosDraftLockHelper.IsLockActive(order)
            && !PosDraftLockHelper.IsHeldBy(order, actor);
        // Máy đang mở đơn (heartbeat gần đây): không cho cướp.
        // Máy đã về sơ đồ (không renew) → LockedAt cũ → cho «Lấy quyền».
        if (stealing && force)
        {
            // Bắt buộc deviceId khi cướp khóa — chống spoof body trống.
            if (string.IsNullOrWhiteSpace(dto?.DeviceId))
            {
                return BadRequest(AppResponse<DraftLockStateDto>.Fail(
                    "Thiếu deviceId khi lấy quyền khóa đơn."));
            }

            var lockedAt = order.LockedAt ?? order.UpdatedAt ?? DateTime.UtcNow;
            var ageSec = (DateTime.UtcNow - lockedAt).TotalSeconds;
            var activelyHeld = ageSec < 45;
            if (activelyHeld)
            {
                var who = string.IsNullOrWhiteSpace(order.LockedByDisplayName)
                    ? "máy khác"
                    : order.LockedByDisplayName!;
                var device = string.IsNullOrWhiteSpace(order.LockedByDeviceName)
                    ? ""
                    : $" · {order.LockedByDeviceName}";
                var conflict = MapLockState(order, actor, lineCount);
                return Conflict(AppResponse<DraftLockStateDto>.Create(
                    false,
                    conflict,
                    [$"Bàn đang mở bởi {who}{device} — nhờ máy đó thoát về sơ đồ rồi bấm Lấy quyền"]));
            }

            // Cùng tài khoản chuyển máy sau khi «tạm rời» (>45s): không cần Approve.
            // User khác force-take vẫn cần Approve — tránh Waiter cướp bàn người khác.
            var sameUser = order.LockedByUserId == actor.UserId;
            if (!sameUser && !await HasPosSellApproveAsync())
            {
                return StatusCode(StatusCodes.Status403Forbidden,
                    AppResponse<DraftLockStateDto>.Fail(
                        "Cần quyền duyệt PosSell để lấy quyền đơn đang khóa trên máy khác."));
            }
        }

        var err = PosDraftLockHelper.TryAcquire(
            order, actor, force, bumpVersion: stealing, lineCount: lineCount);
        if (err != null)
        {
            var conflict = MapLockState(order, actor, lineCount);
            return Conflict(AppResponse<DraftLockStateDto>.Create(false, conflict, [err]));
        }

        await dbContext.SaveChangesAsync();
        NotifyFloorChanged(storeId, "draftLocked",
            orderId: order.Id, resourceId: order.ServiceResourceId);
        return Ok(AppResponse<DraftLockStateDto>.Success(MapLockState(order, actor, lineCount)));
    }

    /// <summary>Gia hạn TTL — HĐ trống: no-op (không chiếm chỗ).</summary>
    [HttpPost("{id:guid}/lock/heartbeat")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<DraftLockStateDto>>> HeartbeatDraftLock(
        Guid id, [FromBody] DraftLockRequestDto? dto = null)
    {
        var storeId = RequiredStoreId;
        // DbContext mặc định NoTracking — bắt buộc AsTracking để SaveChangesAsync thực sự ghi lock.
        var order = await dbContext.PosSaleOrders.AsTracking()
            .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId && o.Deleted == null);
        if (order == null)
            return NotFound(AppResponse<DraftLockStateDto>.Fail("Không tìm thấy đơn hàng"));

        var lineCount = await CountActiveLinesAsync(id);
        var actor = CurrentLockActor(dto?.DeviceId, dto?.DeviceName);

        if (!await IsMultiDeviceDraftLockEnabledAsync(storeId))
        {
            if (PosDraftLockHelper.IsLockActive(order))
            {
                PosDraftLockHelper.Release(order);
                await dbContext.SaveChangesAsync();
            }
            return Ok(AppResponse<DraftLockStateDto>.Success(MapLockState(order, actor, lineCount)));
        }

        var tableBound = order.ServiceResourceId.HasValue;
        if (lineCount <= 0 && !tableBound)
        {
            if (PosDraftLockHelper.IsLockActive(order))
            {
                PosDraftLockHelper.Release(order);
                await dbContext.SaveChangesAsync();
            }
            return Ok(AppResponse<DraftLockStateDto>.Success(MapLockState(order, actor, lineCount)));
        }

        var err = PosDraftLockHelper.TryRenew(order, actor, lineCount: lineCount);
        if (err != null)
            return Conflict(AppResponse<DraftLockStateDto>.Create(
                false, MapLockState(order, actor, lineCount), [err]));

        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<DraftLockStateDto>.Success(MapLockState(order, actor, lineCount)));
    }

    /// <summary>Nhả khóa / nhả chỗ ngồi (đổi tab trống, đóng HĐ).</summary>
    [HttpPost("{id:guid}/unlock")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<DraftLockStateDto>>> UnlockDraft(
        Guid id, [FromBody] DraftLockRequestDto? dto = null)
    {
        var storeId = RequiredStoreId;
        // DbContext mặc định NoTracking — bắt buộc AsTracking để SaveChangesAsync thực sự ghi lock.
        var order = await dbContext.PosSaleOrders.AsTracking()
            .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId && o.Deleted == null);
        if (order == null)
            return NotFound(AppResponse<DraftLockStateDto>.Fail("Không tìm thấy đơn hàng"));

        var lineCount = await CountActiveLinesAsync(id);
        var actor = CurrentLockActor(dto?.DeviceId, dto?.DeviceName);

        // Tắt khóa đa máy: luôn nhả được.
        if (!await IsMultiDeviceDraftLockEnabledAsync(storeId))
        {
            PosDraftLockHelper.Release(order);
            await dbContext.SaveChangesAsync();
            NotifyFloorChanged(storeId, "draftUnlocked",
                orderId: order.Id, resourceId: order.ServiceResourceId);
            return Ok(AppResponse<DraftLockStateDto>.Success(MapLockState(order, actor, lineCount)));
        }

        // Chỉ máy đang giữ khóa mới được nhả.
        // Không nhả theo cùng user — điện thoại chỉ xem rồi thoát sẽ xóa «Máy khác» của máy đang sửa.
        if (PosDraftLockHelper.IsLockActive(order)
            && !PosDraftLockHelper.IsHeldBy(order, actor))
        {
            return Conflict(AppResponse<DraftLockStateDto>.Create(
                false, MapLockState(order, actor, lineCount), ["Bạn không đang giữ đơn này"]));
        }

        var resourceId = order.ServiceResourceId;
        PosDraftLockHelper.Release(order);
        await dbContext.SaveChangesAsync();
        NotifyFloorChanged(storeId, "draftUnlocked",
            orderId: order.Id, resourceId: resourceId);
        return Ok(AppResponse<DraftLockStateDto>.Success(MapLockState(order, actor, lineCount)));
    }
}
