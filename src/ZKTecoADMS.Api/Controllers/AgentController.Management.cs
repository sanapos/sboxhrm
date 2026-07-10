using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.DTOs.SystemAdmin;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

public partial class AgentController
{
    /// <summary>
    /// Danh sách user thuộc cửa hàng của đại lý (không trả plainTextPassword).
    /// </summary>
    [HttpGet("users")]
    public async Task<ActionResult<AppResponse<object>>> GetMyUsers(
        [FromQuery] string? search = null,
        [FromQuery] Guid? storeId = null,
        [FromQuery] string? role = null,
        [FromQuery] int pageNumber = 1,
        [FromQuery] int pageSize = 500)
    {
        var (agent, err) = await RequireCurrentAgentAsync();
        if (err != null) return err;

        if (pageSize > 1000) pageSize = 1000;
        if (pageNumber < 1) pageNumber = 1;

        if (storeId.HasValue &&
            !await AgentScopeHelper.StoreBelongsToAgentAsync(_dbContext, agent.Id, storeId.Value))
        {
            return BadRequest(AppResponse<object>.Fail("Cửa hàng không thuộc đại lý này"));
        }

        var query = _userManager.Users
            .Include(u => u.Store)
            .Where(u => u.Store != null && u.Store.AgentId == agent.Id);

        if (!string.IsNullOrEmpty(search))
        {
            var searchPattern = $"%{search}%";
            query = query.Where(u =>
                EF.Functions.ILike(u.Email!, searchPattern) ||
                EF.Functions.ILike(u.FullName, searchPattern));
        }

        if (storeId.HasValue)
            query = query.Where(u => u.StoreId == storeId.Value);

        if (!string.IsNullOrEmpty(role))
            query = query.Where(u => u.Role == role);

        var totalCount = await query.CountAsync();
        var users = await query
            .OrderByDescending(u => u.CreatedAt)
            .Skip((pageNumber - 1) * pageSize)
            .Take(pageSize)
            .Select(u => new SystemUserDto(
                u.Id,
                u.Email ?? "",
                u.FullName,
                u.Role ?? "",
                u.StoreId,
                u.Store != null ? u.Store.Name : null,
                u.Store != null ? u.Store.Code : null,
                u.IsActive,
                u.CreatedAt,
                u.LastLoginAt,
                null,
                u.Store != null ? u.Store.AgentId : null,
                null
            ))
            .ToListAsync();

        return Ok(AppResponse<object>.Success(new { items = users, totalCount, pageNumber, pageSize }));
    }

    /// <summary>
    /// Chi tiết cửa hàng thuộc đại lý.
    /// </summary>
    [HttpGet("stores/{id:guid}/full")]
    public async Task<ActionResult<AppResponse<StoreFullDetailDto>>> GetMyStoreFullDetail(Guid id)
    {
        var (agent, err) = await RequireCurrentAgentAsync();
        if (err != null) return err;

        if (!await AgentScopeHelper.StoreBelongsToAgentAsync(_dbContext, agent.Id, id))
            return NotFound(AppResponse<StoreFullDetailDto>.Fail("Cửa hàng không thuộc đại lý này"));

        var store = await _dbContext.Stores
            .Include(s => s.Owner)
            .Include(s => s.Users)
            .Include(s => s.Devices)
            .Include(s => s.LicenseKeys)
            .FirstOrDefaultAsync(s => s.Id == id);

        if (store == null)
            return NotFound(AppResponse<StoreFullDetailDto>.Fail("Không tìm thấy cửa hàng"));

        var dto = new StoreFullDetailDto(
            store.Id,
            store.Name,
            store.Code,
            store.Description,
            store.Address,
            store.Phone,
            store.IsActive,
            store.IsLocked,
            store.LockReason,
            store.LockedAt,
            store.LicenseType.ToString(),
            store.LicenseKey,
            store.ExpiryDate,
            store.MaxUsers,
            store.MaxDevices,
            store.Users.Count,
            store.Devices.Count,
            store.OwnerId,
            store.Owner?.FullName,
            store.Owner?.Email,
            store.CreatedAt,
            store.UpdatedAt
        );

        return Ok(AppResponse<StoreFullDetailDto>.Success(dto));
    }

    [HttpPut("stores/{id:guid}")]
    public async Task<ActionResult<AppResponse<StoreDetailDto>>> UpdateMyStore(
        Guid id,
        [FromBody] UpdateStoreRequest request)
    {
        var (agent, err) = await RequireCurrentAgentAsync();
        if (err != null) return err;

        if (!await AgentScopeHelper.StoreBelongsToAgentAsync(_dbContext, agent.Id, id))
            return NotFound(AppResponse<StoreDetailDto>.Fail("Cửa hàng không thuộc đại lý này"));

        var store = await _dbContext.Stores
            .AsTracking()
            .Include(s => s.Owner)
            .Include(s => s.Agent)
            .Include(s => s.Users)
            .Include(s => s.Devices)
            .Include(s => s.ServicePackage)
            .FirstOrDefaultAsync(s => s.Id == id);

        if (store == null)
            return NotFound(AppResponse<StoreDetailDto>.Fail("Không tìm thấy cửa hàng"));

        store.Name = request.Name;
        store.Description = request.Description;
        store.Address = request.Address;
        store.Province = request.Province;
        store.Phone = request.Phone;
        store.UpdatedAt = DateTime.UtcNow;
        store.UpdatedBy = CurrentUserId.ToString();

        await _dbContext.SaveChangesAsync();
        _logger.LogInformation("Agent {UserId} updated store {StoreId}", CurrentUserId, id);

        return Ok(AppResponse<StoreDetailDto>.Success(AgentStoreMapper.ToStoreDetailDto(store)));
    }

    [HttpPost("stores/{id:guid}/toggle-status")]
    public async Task<ActionResult<AppResponse<StoreDetailDto>>> ToggleMyStoreStatus(Guid id)
    {
        var (agent, err) = await RequireCurrentAgentAsync();
        if (err != null) return err;

        if (!await AgentScopeHelper.StoreBelongsToAgentAsync(_dbContext, agent.Id, id))
            return NotFound(AppResponse<StoreDetailDto>.Fail("Cửa hàng không thuộc đại lý này"));

        var store = await LoadStoreForAgentAsync(id);
        if (store == null)
            return NotFound(AppResponse<StoreDetailDto>.Fail("Không tìm thấy cửa hàng"));

        store.IsActive = !store.IsActive;
        store.UpdatedAt = DateTime.UtcNow;
        store.UpdatedBy = CurrentUserId.ToString();
        await _dbContext.SaveChangesAsync();

        return Ok(AppResponse<StoreDetailDto>.Success(AgentStoreMapper.ToStoreDetailDto(store)));
    }

    [HttpPost("stores/{id:guid}/lock")]
    public async Task<ActionResult<AppResponse<StoreDetailDto>>> LockMyStore(
        Guid id,
        [FromBody] LockStoreRequest request)
    {
        var (agent, err) = await RequireCurrentAgentAsync();
        if (err != null) return err;

        if (!await AgentScopeHelper.StoreBelongsToAgentAsync(_dbContext, agent.Id, id))
            return NotFound(AppResponse<StoreDetailDto>.Fail("Cửa hàng không thuộc đại lý này"));

        var store = await LoadStoreForAgentAsync(id);
        if (store == null)
            return NotFound(AppResponse<StoreDetailDto>.Fail("Không tìm thấy cửa hàng"));

        store.IsLocked = true;
        store.LockReason = request.Reason;
        store.LockedAt = DateTime.UtcNow;
        store.UpdatedAt = DateTime.UtcNow;
        store.UpdatedBy = CurrentUserId.ToString();
        await _dbContext.SaveChangesAsync();

        return Ok(AppResponse<StoreDetailDto>.Success(AgentStoreMapper.ToStoreDetailDto(store)));
    }

    [HttpPost("stores/{id:guid}/unlock")]
    public async Task<ActionResult<AppResponse<StoreDetailDto>>> UnlockMyStore(Guid id)
    {
        var (agent, err) = await RequireCurrentAgentAsync();
        if (err != null) return err;

        if (!await AgentScopeHelper.StoreBelongsToAgentAsync(_dbContext, agent.Id, id))
            return NotFound(AppResponse<StoreDetailDto>.Fail("Cửa hàng không thuộc đại lý này"));

        var store = await LoadStoreForAgentAsync(id);
        if (store == null)
            return NotFound(AppResponse<StoreDetailDto>.Fail("Không tìm thấy cửa hàng"));

        store.IsLocked = false;
        store.LockReason = null;
        store.LockedAt = null;
        store.UpdatedAt = DateTime.UtcNow;
        store.UpdatedBy = CurrentUserId.ToString();
        await _dbContext.SaveChangesAsync();

        return Ok(AppResponse<StoreDetailDto>.Success(AgentStoreMapper.ToStoreDetailDto(store)));
    }

    [HttpPost("stores/{id:guid}/extend")]
    public async Task<ActionResult<AppResponse<StoreDetailDto>>> ExtendMyStore(
        Guid id,
        [FromBody] ExtendSubscriptionRequest request)
    {
        var (agent, err) = await RequireCurrentAgentAsync();
        if (err != null) return err;

        if (!await AgentScopeHelper.StoreBelongsToAgentAsync(_dbContext, agent.Id, id))
            return NotFound(AppResponse<StoreDetailDto>.Fail("Cửa hàng không thuộc đại lý này"));

        var store = await LoadStoreForAgentAsync(id);
        if (store == null)
            return NotFound(AppResponse<StoreDetailDto>.Fail("Không tìm thấy cửa hàng"));

        if (request.DaysToAdd <= 0)
            return BadRequest(AppResponse<StoreDetailDto>.Fail("Số ngày gia hạn phải lớn hơn 0"));

        if (!StoreRenewalHelper.IsPresetDay(request.DaysToAdd))
        {
            return BadRequest(AppResponse<StoreDetailDto>.Fail(
                StoreRenewalHelper.PresetOnlyMessage));
        }

        if (IsStoreRenewalLimitReached(store.RenewalCount))
        {
            return BadRequest(AppResponse<StoreDetailDto>.Fail(
                "Cửa hàng đã gia hạn tối đa 3 lần. Vui lòng kích hoạt key mới."));
        }

        var trackedAgent = await _dbContext.Agents
            .AsTracking()
            .FirstOrDefaultAsync(a => a.Id == agent.Id);
        if (trackedAgent == null)
            return NotFound(AppResponse<StoreDetailDto>.Fail("Không tìm thấy đại lý"));

        if (trackedAgent.RenewalDayBalance < request.DaysToAdd)
        {
            return BadRequest(AppResponse<StoreDetailDto>.Fail(
                StoreRenewalHelper.InsufficientAgentBalanceMessage(
                    trackedAgent.RenewalDayBalance, request.DaysToAdd)));
        }

        store.ExpiryDate = StoreLicenseHelper.ComputeExtendedExpiryDate(store, request.DaysToAdd);
        store.RenewalCount++;
        store.IsLocked = false;
        store.LockReason = null;
        store.IsActive = true;
        trackedAgent.RenewalDayBalance -= request.DaysToAdd;
        store.UpdatedAt = DateTime.UtcNow;
        store.UpdatedBy = CurrentUserId.ToString();
        await _dbContext.SaveChangesAsync();

        return Ok(AppResponse<StoreDetailDto>.Success(AgentStoreMapper.ToStoreDetailDto(store)));
    }

    [HttpGet("stores/{storeId:guid}/activatable-licenses")]
    public async Task<ActionResult<AppResponse<List<LicenseKeyDto>>>> GetActivatableLicensesForMyStore(
        Guid storeId)
    {
        var (agent, err) = await RequireCurrentAgentAsync();
        if (err != null) return err;

        if (!await AgentScopeHelper.StoreBelongsToAgentAsync(_dbContext, agent.Id, storeId))
            return NotFound(AppResponse<List<LicenseKeyDto>>.Fail("Cửa hàng không thuộc đại lý này"));

        var store = await _dbContext.Stores.AsNoTracking()
            .FirstOrDefaultAsync(s => s.Id == storeId);
        if (store == null)
            return NotFound(AppResponse<List<LicenseKeyDto>>.Fail("Không tìm thấy cửa hàng"));

        var items = await LicenseKeyActivationHelper
            .FilterActivatableForStore(
                _dbContext.LicenseKeys
                    .Include(l => l.Store)
                    .Include(l => l.Agent)
                    .Include(l => l.ServicePackage),
                store)
            .OrderByDescending(l => l.CreatedAt)
            .Take(500)
            .ToListAsync();

        var dtos = items.Select(l => new LicenseKeyDto(
            l.Id, l.Key, l.LicenseType.ToString(), l.DurationDays,
            l.MaxUsers, l.MaxDevices, l.IsUsed, l.ActivatedAt,
            l.StoreId, l.Store?.Name, l.AgentId, l.Agent?.Name,
            l.ServicePackageId, l.ServicePackage?.Name,
            l.Notes, l.IsActive, l.CreatedAt
        )).ToList();

        return Ok(AppResponse<List<LicenseKeyDto>>.Success(dtos));
    }

    [HttpPost("stores/{storeId:guid}/activate-license")]
    public async Task<ActionResult<AppResponse<StoreDetailDto>>> ActivateLicenseForMyStore(
        Guid storeId,
        [FromBody] ActivateLicenseRequest request)
    {
        var (agent, err) = await RequireCurrentAgentAsync();
        if (err != null) return err;

        if (!await AgentScopeHelper.StoreBelongsToAgentAsync(_dbContext, agent.Id, storeId))
            return NotFound(AppResponse<StoreDetailDto>.Fail("Cửa hàng không thuộc đại lý này"));

        var store = await _dbContext.Stores
            .AsTracking()
            .Include(s => s.Owner)
            .Include(s => s.Agent)
            .Include(s => s.Users)
            .Include(s => s.Devices)
            .Include(s => s.ServicePackage)
            .FirstOrDefaultAsync(s => s.Id == storeId);

        if (store == null)
            return NotFound(AppResponse<StoreDetailDto>.Fail("Không tìm thấy cửa hàng"));

        var license = await _dbContext.LicenseKeys
            .AsTracking()
            .Include(l => l.ServicePackage)
            .FirstOrDefaultAsync(l =>
                l.Key == request.LicenseKey &&
                l.IsActive &&
                !l.IsUsed);

        if (license == null)
        {
            return BadRequest(AppResponse<StoreDetailDto>.Fail(
                "License key không hợp lệ hoặc đã được sử dụng"));
        }

        if (!LicenseKeyActivationHelper.CanActivateForStore(license, store))
        {
            return BadRequest(AppResponse<StoreDetailDto>.Fail(
                LicenseKeyActivationHelper.InvalidScopeMessage));
        }

        if (license.AgentId.HasValue && license.AgentId != agent.Id)
        {
            return BadRequest(AppResponse<StoreDetailDto>.Fail(
                "License key không thuộc đại lý này"));
        }

        var isFirstActivation = string.IsNullOrEmpty(store.LicenseKey);
        if (!isFirstActivation && store.RenewalCount >= 3)
        {
            return BadRequest(AppResponse<StoreDetailDto>.Fail(
                "Cửa hàng đã gia hạn tối đa 3 lần. Không thể kích hoạt thêm key."));
        }

        license.IsUsed = true;
        license.StoreId = storeId;
        license.ActivatedAt = DateTime.UtcNow;

        store.ExpiryDate = StoreLicenseHelper.ComputeExtendedExpiryDate(store, license.DurationDays);
        store.LicenseKey = license.Key;
        store.LicenseType = license.LicenseType;
        store.MaxUsers = license.MaxUsers;
        store.MaxDevices = license.MaxDevices;

        if (license.ServicePackageId != null)
            store.ServicePackageId = license.ServicePackageId;

        if (!isFirstActivation)
            store.RenewalCount++;

        store.IsActive = true;
        store.IsLocked = false;
        store.LockReason = null;
        store.UpdatedAt = DateTime.UtcNow;
        store.UpdatedBy = CurrentUserId.ToString();

        await _dbContext.SaveChangesAsync();

        _logger.LogInformation(
            "Agent {UserId} activated license {Key} for store {StoreId}",
            CurrentUserId, license.Key, storeId);

        try
        {
            if (store.OwnerId.HasValue)
            {
                var packageName = license.ServicePackage?.Name ?? license.LicenseType.ToString();
                await _notificationService.CreateAndSendAsync(
                    targetUserId: store.OwnerId.Value,
                    type: NotificationType.Success,
                    title: "Kích hoạt License thành công",
                    message:
                        $"Cửa hàng '{store.Name}' đã được kích hoạt gói {packageName}, hạn sử dụng đến {store.ExpiryDate:dd/MM/yyyy}",
                    relatedEntityId: storeId,
                    relatedEntityType: "Store",
                    categoryCode: "license",
                    storeId: storeId);
            }

            await SuperAdminNotificationHelper.NotifySuperAdminsAsync(
                _notificationService,
                _userManager,
                NotificationType.Success,
                "Key license đã kích hoạt (đại lý)",
                $"Đại lý kích hoạt key cho '{store.Name}' — gói {license.ServicePackage?.Name ?? license.LicenseType.ToString()}, hạn {store.ExpiryDate:dd/MM/yyyy}",
                relatedUrl: SuperAdminNotificationHelper.AdminLicensesUrl,
                relatedEntityId: storeId,
                relatedEntityType: "Store",
                categoryCode: "license",
                storeId: storeId);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to send license activation notification for store {StoreId}", storeId);
        }

        return Ok(AppResponse<StoreDetailDto>.Success(AgentStoreMapper.ToStoreDetailDto(store)));
    }

    /// <summary>
    /// Thiết bị trong phạm vi đại lý + thiết bị chưa gán (để gán vào cửa hàng).
    /// </summary>
    [HttpGet("devices/manage")]
    public async Task<ActionResult<AppResponse<object>>> GetMyDevicesForManage(
        [FromQuery] Guid? storeId = null,
        [FromQuery] bool? isOnline = null,
        [FromQuery] bool? isClaimed = null,
        [FromQuery] string? search = null,
        [FromQuery] int pageNumber = 1,
        [FromQuery] int pageSize = 500)
    {
        var (agent, err) = await RequireCurrentAgentAsync();
        if (err != null) return err;

        if (pageSize > 1000) pageSize = 1000;
        if (pageNumber < 1) pageNumber = 1;

        var storeIds = await AgentScopeHelper.GetStoreIdsAsync(_dbContext, agent.Id);

        if (storeId.HasValue && !storeIds.Contains(storeId.Value))
            return BadRequest(AppResponse<object>.Fail("Cửa hàng không thuộc đại lý này"));

        var query = _dbContext.Devices.AsNoTracking()
            .Include(d => d.Store)
                .ThenInclude(s => s!.Agent)
            .AsQueryable();

        query = query.Where(d =>
            (d.StoreId != null && storeIds.Contains(d.StoreId.Value)) ||
            d.StoreId == null);

        if (storeId.HasValue)
            query = query.Where(d => d.StoreId == storeId.Value);

        if (isClaimed == false)
            query = query.Where(d => d.StoreId == null || !d.IsClaimed);
        else if (isClaimed == true)
            query = query.Where(d => d.StoreId != null && d.IsClaimed);

        if (!string.IsNullOrWhiteSpace(search))
        {
            var pattern = $"%{search.Trim()}%";
            query = query.Where(d =>
                EF.Functions.ILike(d.SerialNumber, pattern) ||
                EF.Functions.ILike(d.DeviceName, pattern) ||
                (d.Store != null && EF.Functions.ILike(d.Store.Name, pattern)));
        }

        if (isOnline.HasValue)
        {
            var status = isOnline.Value ? "Online" : "Offline";
            query = query.Where(d => d.DeviceStatus == status);
        }

        var totalCount = await query.CountAsync();
        var rawDevices = await query
            .OrderByDescending(d => d.LastOnline)
            .Skip((pageNumber - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();

        var items = await DeviceStoreHydrator.ToSystemDeviceDtosAsync(_dbContext, rawDevices);

        return Ok(AppResponse<object>.Success(new { items, totalCount, pageNumber, pageSize }));
    }

    [HttpPut("devices/{id:guid}/assign-store/{storeId:guid}")]
    public async Task<ActionResult<AppResponse<SystemDeviceDto>>> AssignDeviceToMyStore(
        Guid id,
        Guid storeId)
    {
        var (agent, err) = await RequireCurrentAgentAsync();
        if (err != null) return err;

        if (!await AgentScopeHelper.StoreBelongsToAgentAsync(_dbContext, agent.Id, storeId))
            return BadRequest(AppResponse<SystemDeviceDto>.Fail("Cửa hàng không thuộc đại lý này"));

        var device = await _dbContext.Devices.AsTracking().FirstOrDefaultAsync(d => d.Id == id);
        if (device == null)
            return NotFound(AppResponse<SystemDeviceDto>.Fail("Không tìm thấy thiết bị"));

        var storeIds = await AgentScopeHelper.GetStoreIdsAsync(_dbContext, agent.Id);
        if (device.StoreId.HasValue && !storeIds.Contains(device.StoreId.Value))
            return BadRequest(AppResponse<SystemDeviceDto>.Fail("Thiết bị không thuộc phạm vi đại lý"));

        var store = await _dbContext.Stores.Include(s => s.Owner)
            .FirstOrDefaultAsync(s => s.Id == storeId);
        if (store == null)
            return NotFound(AppResponse<SystemDeviceDto>.Fail("Không tìm thấy cửa hàng"));

        device.StoreId = storeId;
        device.OwnerId = store.OwnerId;
        device.IsClaimed = true;
        device.ClaimedAt = DateTime.UtcNow;
        device.IsActive = true;
        device.UpdatedAt = DateTime.UtcNow;

        await _dbContext.SaveChangesAsync();
        return Ok(AppResponse<SystemDeviceDto>.Success(AgentStoreMapper.ToSystemDeviceDto(device, store)));
    }

    [HttpPut("devices/{id:guid}/unassign-store")]
    public async Task<ActionResult<AppResponse<SystemDeviceDto>>> UnassignDeviceFromMyStore(Guid id)
    {
        var (agent, err) = await RequireCurrentAgentAsync();
        if (err != null) return err;

        var storeIds = await AgentScopeHelper.GetStoreIdsAsync(_dbContext, agent.Id);

        var device = await _dbContext.Devices.AsTracking()
            .Include(d => d.Store)
            .FirstOrDefaultAsync(d => d.Id == id);

        if (device == null)
            return NotFound(AppResponse<SystemDeviceDto>.Fail("Không tìm thấy thiết bị"));

        if (!device.StoreId.HasValue || !storeIds.Contains(device.StoreId.Value))
            return BadRequest(AppResponse<SystemDeviceDto>.Fail("Thiết bị không thuộc cửa hàng của đại lý"));

        device.StoreId = null;
        device.OwnerId = null;
        device.IsClaimed = false;
        device.ClaimedAt = null;
        device.IsActive = false;
        device.UpdatedAt = DateTime.UtcNow;

        await _dbContext.SaveChangesAsync();
        return Ok(AppResponse<SystemDeviceDto>.Success(AgentStoreMapper.ToSystemDeviceDto(device)));
    }

    [HttpPut("users/{id:guid}/credentials")]
    public async Task<ActionResult<AppResponse<SystemUserDto>>> UpdateMyUserCredentials(
        Guid id,
        [FromBody] UpdateUserCredentialsRequest request)
    {
        var (agent, err) = await RequireCurrentAgentAsync();
        if (err != null) return err;

        if (!await AgentScopeHelper.UserBelongsToAgentAsync(_userManager, agent.Id, id))
            return NotFound(AppResponse<SystemUserDto>.Fail("User không thuộc cửa hàng của đại lý"));

        var user = await _userManager.FindByIdAsync(id.ToString());
        if (user == null)
            return NotFound(AppResponse<SystemUserDto>.Fail("User not found"));

        if (user.Role is nameof(Roles.SuperAdmin) or nameof(Roles.Agent))
            return BadRequest(AppResponse<SystemUserDto>.Fail("Không thể sửa tài khoản quản trị hệ thống"));

        if (!string.IsNullOrEmpty(request.NewEmail) && request.NewEmail != user.Email)
        {
            var existingUser = await _userManager.FindByEmailAsync(request.NewEmail);
            if (existingUser != null)
                return BadRequest(AppResponse<SystemUserDto>.Fail("Email đã được sử dụng"));

            user.Email = request.NewEmail;
            user.UserName = request.NewEmail;
            user.NormalizedEmail = request.NewEmail.ToUpper();
            user.NormalizedUserName = request.NewEmail.ToUpper();
        }

        if (!string.IsNullOrEmpty(request.NewPassword))
        {
            var token = await _userManager.GeneratePasswordResetTokenAsync(user);
            var result = await _userManager.ResetPasswordAsync(user, token, request.NewPassword);
            if (!result.Succeeded)
            {
                return BadRequest(AppResponse<SystemUserDto>.Fail(
                    string.Join(", ", result.Errors.Select(e => e.Description))));
            }
            UserPasswordVisibility.RememberPassword(user, request.NewPassword);
        }

        if (!string.IsNullOrEmpty(request.FullName))
        {
            var names = request.FullName.Split(' ');
            user.FirstName = names.FirstOrDefault() ?? user.FirstName;
            user.LastName = names.Length > 1 ? string.Join(" ", names.Skip(1)) : user.LastName;
        }

        await _userManager.UpdateAsync(user);

        var store = user.StoreId.HasValue
            ? await _dbContext.Stores.FindAsync(user.StoreId.Value)
            : null;

        return Ok(AppResponse<SystemUserDto>.Success(new SystemUserDto(
            user.Id,
            user.Email ?? "",
            user.FullName,
            user.Role ?? "",
            user.StoreId,
            store?.Name,
            store?.Code,
            user.IsActive,
            user.CreatedAt,
            user.LastLoginAt,
            null,
            store?.AgentId,
            null
        )));
    }

    private async Task<Store?> LoadStoreForAgentAsync(Guid storeId) =>
        await _dbContext.Stores
            .AsTracking()
            .Include(s => s.Owner)
            .Include(s => s.Agent)
            .Include(s => s.Users)
            .Include(s => s.Devices)
            .Include(s => s.ServicePackage)
            .FirstOrDefaultAsync(s => s.Id == storeId);
}
