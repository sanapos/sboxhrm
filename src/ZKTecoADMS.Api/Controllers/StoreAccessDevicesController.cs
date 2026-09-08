using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Helpers;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Danh sách / nhả thiết bị đăng nhập (web, app, POS) theo hạn mức gói.</summary>
[ApiController]
[Route("api/store/access-devices")]
[Authorize]
public class StoreAccessDevicesController(ZKTecoDbContext db) : AuthenticatedControllerBase
{
    public record AccessDeviceDto(
        Guid Id,
        string DeviceKey,
        string Platform,
        string? DeviceName,
        Guid? UserId,
        string? UserName,
        DateTime LastSeenAt,
        bool IsThisDevice);

    [HttpGet]
    [RequireAnyModulePermission(ModulePermissionAction.View, "SettingsHub", "SystemSettings", "UserManagement")]
    public async Task<ActionResult<AppResponse<object>>> List([FromQuery] string? deviceKey, CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var (used, max, unlimited) = await StorePackageHelper.GetAccessDeviceQuotaAsync(db, storeId, ct);

        var myKey = (deviceKey ?? "").Trim();
        if (myKey.Length > 80) myKey = myKey[..80];

        var rows = await db.StoreAccessDevices.AsNoTracking()
            .Where(d => d.StoreId == storeId)
            .OrderByDescending(d => d.LastSeenAt)
            .Select(d => new
            {
                d.Id,
                d.DeviceKey,
                d.Platform,
                d.DeviceName,
                d.UserId,
                d.LastSeenAt,
            })
            .ToListAsync(ct);

        var userIds = rows.Where(r => r.UserId.HasValue).Select(r => r.UserId!.Value).Distinct().ToList();
        var names = new Dictionary<Guid, string>();
        if (userIds.Count > 0)
        {
            var userRows = await db.Users.AsNoTracking()
                .Where(u => userIds.Contains(u.Id))
                .Select(u => new { u.Id, u.FirstName, u.LastName, u.Email, u.UserName })
                .ToListAsync(ct);
            foreach (var u in userRows)
            {
                var full = $"{u.LastName} {u.FirstName}".Trim();
                names[u.Id] = !string.IsNullOrWhiteSpace(full)
                    ? full
                    : (u.Email ?? u.UserName ?? "");
            }
        }

        var items = rows.Select(r => new AccessDeviceDto(
            r.Id,
            r.DeviceKey,
            r.Platform,
            r.DeviceName,
            r.UserId,
            r.UserId.HasValue && names.TryGetValue(r.UserId.Value, out var n) ? n : null,
            r.LastSeenAt,
            myKey.Length > 0 && string.Equals(r.DeviceKey, myKey, StringComparison.Ordinal))).ToList();

        return Ok(AppResponse<object>.Success(new
        {
            used,
            max,
            unlimited,
            items,
        }));
    }

    [HttpDelete("{id:guid}")]
    [RequireAnyModulePermission(ModulePermissionAction.Edit, "SettingsHub", "SystemSettings", "UserManagement")]
    public async Task<ActionResult<AppResponse<object>>> Release(Guid id, CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var row = await db.StoreAccessDevices.AsTracking()
            .FirstOrDefaultAsync(d => d.Id == id && d.StoreId == storeId, ct);
        if (row == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy thiết bị"));

        var now = DateTime.UtcNow;
        row.IsActive = false;
        row.Deleted = now;
        row.DeletedBy = CurrentUserEmail ?? CurrentUserId.ToString();
        row.UpdatedAt = now;
        row.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync(ct);

        var (used, max, unlimited) = await StorePackageHelper.GetAccessDeviceQuotaAsync(db, storeId, ct);
        return Ok(AppResponse<object>.Success(new
        {
            released = true,
            id,
            used,
            max,
            unlimited,
        }));
    }
}
