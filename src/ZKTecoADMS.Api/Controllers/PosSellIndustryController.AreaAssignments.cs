using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

public partial class PosSellIndustryController
{
    public record AreaAssignmentDto(Guid AreaId, string AreaName, string? AreaCode, bool CanView, bool CanOperate);

    public class SetAreaAssignmentsRequest
    {
        /// <summary>Danh sách AreaId được phép. Rỗng = xóa hết gán → xem tất cả khu.</summary>
        public List<Guid> AreaIds { get; set; } = [];
    }

    /// <summary>
    /// Admin/Manager/Cashier xem &amp; thao tác mọi khu. User khác: không có dòng gán → tất cả;
    /// có ≥1 dòng → chỉ các khu đó (view theo CanView, thao tác theo CanOperate).
    /// </summary>
    bool SeesAllPosServiceAreas() =>
        IsManager
        || CurrentUserRole.Equals(nameof(Roles.Cashier), StringComparison.OrdinalIgnoreCase);

    /// <returns>null = không giới hạn; HashSet = chỉ các AreaId này (CanView).</returns>
    async Task<HashSet<Guid>?> GetRestrictedAreaIdsAsync(Guid storeId, CancellationToken ct = default)
    {
        if (SeesAllPosServiceAreas()) return null;
        var ids = await db.PosServiceAreaAssignments.AsNoTracking()
            .Where(a => a.StoreId == storeId
                && a.UserId == CurrentUserId
                && a.IsActive
                && a.CanView)
            .Select(a => a.AreaId)
            .ToListAsync(ct);
        if (ids.Count == 0) return null;
        return ids.ToHashSet();
    }

    /// <returns>null = không giới hạn; HashSet = khu được thao tác (CanOperate).</returns>
    async Task<HashSet<Guid>?> GetRestrictedOperateAreaIdsAsync(Guid storeId, CancellationToken ct = default)
    {
        if (SeesAllPosServiceAreas()) return null;
        var ids = await db.PosServiceAreaAssignments.AsNoTracking()
            .Where(a => a.StoreId == storeId
                && a.UserId == CurrentUserId
                && a.IsActive
                && a.CanOperate)
            .Select(a => a.AreaId)
            .ToListAsync(ct);
        if (ids.Count == 0)
        {
            // Không có dòng gán → xem tất cả; có gán nhưng không CanOperate → cấm hết thao tác.
            var anyAssign = await db.PosServiceAreaAssignments.AsNoTracking()
                .AnyAsync(a => a.StoreId == storeId
                    && a.UserId == CurrentUserId
                    && a.IsActive, ct);
            return anyAssign ? new HashSet<Guid>() : null;
        }
        return ids.ToHashSet();
    }

    async Task<bool> CanAccessAreaAsync(Guid storeId, Guid areaId, CancellationToken ct = default)
    {
        var restricted = await GetRestrictedAreaIdsAsync(storeId, ct);
        return restricted == null || restricted.Contains(areaId);
    }

    async Task<bool> CanAccessResourceAsync(Guid storeId, Guid resourceId, CancellationToken ct = default)
    {
        var restricted = await GetRestrictedAreaIdsAsync(storeId, ct);
        if (restricted == null) return true;
        var areaId = await db.PosServiceResources.AsNoTracking()
            .Where(r => r.Id == resourceId && r.StoreId == storeId && r.Deleted == null)
            .Select(r => (Guid?)r.AreaId)
            .FirstOrDefaultAsync(ct);
        return areaId != null && restricted.Contains(areaId.Value);
    }

    async Task<bool> CanOperateAreaAsync(Guid storeId, Guid areaId, CancellationToken ct = default)
    {
        var restricted = await GetRestrictedOperateAreaIdsAsync(storeId, ct);
        return restricted == null || restricted.Contains(areaId);
    }

    async Task<bool> CanOperateResourceAsync(Guid storeId, Guid resourceId, CancellationToken ct = default)
    {
        var restricted = await GetRestrictedOperateAreaIdsAsync(storeId, ct);
        if (restricted == null) return true;
        var areaId = await db.PosServiceResources.AsNoTracking()
            .Where(r => r.Id == resourceId && r.StoreId == storeId && r.Deleted == null)
            .Select(r => (Guid?)r.AreaId)
            .FirstOrDefaultAsync(ct);
        return areaId != null && restricted.Contains(areaId.Value);
    }

    /// <summary>Khu vực được gán cho một tài khoản (manager cấu hình).</summary>
    [HttpGet("users/{userId:guid}/service-areas")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetUserServiceAreas(Guid userId)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));

        var userOk = await db.Users.AsNoTracking()
            .AnyAsync(u => u.Id == userId && u.StoreId == storeId);
        if (!userOk)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy tài khoản"));

        var rows = await (
            from a in db.PosServiceAreaAssignments.AsNoTracking()
            join area in db.PosServiceAreas.AsNoTracking() on a.AreaId equals area.Id
            where a.StoreId == storeId && a.UserId == userId && a.IsActive
                && area.Deleted == null && area.StoreId == storeId
            orderby area.SortOrder, area.Name
            select new AreaAssignmentDto(a.AreaId, area.Name, area.Code, a.CanView, a.CanOperate)
        ).ToListAsync();

        return Ok(AppResponse<object>.Success(new
        {
            userId,
            seeAll = rows.Count == 0,
            areas = rows,
            areaIds = rows.Select(r => r.AreaId).ToList(),
        }));
    }

    /// <summary>Gán / ghi đè khu vực cho tài khoản. areaIds rỗng = xem tất cả.</summary>
    [HttpPut("users/{userId:guid}/service-areas")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> SetUserServiceAreas(
        Guid userId, [FromBody] SetAreaAssignmentsRequest? request)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));

        var userOk = await db.Users.AsNoTracking()
            .AnyAsync(u => u.Id == userId && u.StoreId == storeId);
        if (!userOk)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy tài khoản"));

        var wanted = (request?.AreaIds ?? [])
            .Where(id => id != Guid.Empty)
            .Distinct()
            .ToList();

        if (wanted.Count > 0)
        {
            var validCount = await db.PosServiceAreas.AsNoTracking()
                .CountAsync(a => a.StoreId == storeId && a.Deleted == null && wanted.Contains(a.Id));
            if (validCount != wanted.Count)
                return BadRequest(AppResponse<object>.Fail("Có khu vực không thuộc cửa hàng"));
        }

        var existing = await db.PosServiceAreaAssignments
            .Where(a => a.StoreId == storeId && a.UserId == userId)
            .ToListAsync();

        db.PosServiceAreaAssignments.RemoveRange(existing);

        var by = CurrentUserEmail;
        var now = DateTime.UtcNow;
        foreach (var areaId in wanted)
        {
            db.PosServiceAreaAssignments.Add(new PosServiceAreaAssignment
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                UserId = userId,
                AreaId = areaId,
                // Gán khu = được xem + thao tác (mở bàn/chuyển/tách).
                CanView = true,
                CanOperate = true,
                IsActive = true,
                GrantedBy = by,
                CreatedAt = now,
                CreatedBy = by,
            });
        }

        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new
        {
            userId,
            seeAll = wanted.Count == 0,
            areaIds = wanted,
            saved = wanted.Count,
        }));
    }

    /// <summary>Khu vực hiện tại của user đang đăng nhập (debug / client).</summary>
    [HttpGet("my-service-areas")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetMyServiceAreas()
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));

        var viewRestricted = await GetRestrictedAreaIdsAsync(storeId);
        var operateRestricted = await GetRestrictedOperateAreaIdsAsync(storeId);
        if (viewRestricted == null)
        {
            return Ok(AppResponse<object>.Success(new
            {
                seeAll = true,
                areaIds = Array.Empty<Guid>(),
                operateAreaIds = Array.Empty<Guid>(),
                reason = SeesAllPosServiceAreas() ? "role_unrestricted" : "no_assignments",
            }));
        }

        return Ok(AppResponse<object>.Success(new
        {
            seeAll = false,
            areaIds = viewRestricted.ToList(),
            operateAreaIds = operateRestricted?.ToList() ?? viewRestricted.ToList(),
            reason = "assigned",
        }));
    }
}
