using ZKTecoADMS.Application.DTOs.Devices;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Application.Queries.Devices.GetDevicesByUser;
using ZKTecoADMS.Application.Queries.Devices.GetAllDevices;
using ZKTecoADMS.Application.Queries.Devices.GetDeviceById;
using Mapster;
using Microsoft.AspNetCore.Authorization;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Commands.Devices.ToggleActive;
using ZKTecoADMS.Application.Commands.Devices.AddDevice;
using ZKTecoADMS.Application.Commands.Devices.DeleteDevice;
using ZKTecoADMS.Application.Queries.Devices.GetDeviceInfo;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Repositories;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize(Policy = PolicyNames.AtLeastEmployee)]
public class DevicesController(
    IMediator bus,
    IDeviceService deviceService,
    IRepository<Device> deviceRepository,
    IDeviceCapabilityService capabilityService
    ) : AuthenticatedControllerBase
{
    [HttpGet("users/{CurrentUserId}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Device", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<DeviceDto>>> GetDevicesByUser(Guid CurrentUserId)
    {
        var query = new GetDevicesByUserQuery(CurrentUserId);
        return Ok(await bus.Send(query));
    }
    
    [HttpGet]
    [RequireAnyModulePermission(ModulePermissionAction.View, "Device", "Attendance", "AttendanceSummary", "AttendanceByShift")]
    public async Task<ActionResult<AppResponse<IEnumerable<DeviceDto>>>> GetAllDevices([FromQuery] bool? storeOnly)
    {
        var query = new GetAllDevicesQuery(
            UserId: CurrentUserId,
            IsAdminRequest: IsAdmin,
            StoreId: storeOnly == true ? GetCurrentStoreId() : null
        );
        
        return Ok(await bus.Send(query));
    }

    [HttpGet("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Device", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<DeviceDto>>> GetDeviceById(Guid id)
    {
        var query = new GetDeviceByIdQuery(id);
        return Ok(await bus.Send(query));
    }

    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Device", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<DeviceDto>>> AddDevice([FromBody] AddDeviceRequest request)
    {
        try
        {
            Console.WriteLine($"[AddDevice] SN={request.SerialNumber}, Name={request.DeviceName}, UserId={CurrentUserId}, StoreId={GetCurrentStoreId()}");
            var cmd = request.Adapt<AddDeviceCommand>();
            cmd.ManagerId = CurrentUserId;
            cmd.StoreId = GetCurrentStoreId();
            
            var result = await bus.Send(cmd);
            Console.WriteLine($"[AddDevice] Success={result.IsSuccess}, Message={result.Message}");
            return Ok(result);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[AddDevice] ERROR: {ex.Message}");
            Console.WriteLine($"[AddDevice] Stack: {ex.StackTrace}");
            if (ex.InnerException != null)
                Console.WriteLine($"[AddDevice] Inner: {ex.InnerException.Message}");
            return Ok(AppResponse<DeviceDto>.Error($"Lá»—i thÃªm thiáº¿t bá»‹: {ex.Message}"));
        }
    }

    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Device", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<Guid>>> DeleteDevice(Guid id)
    {
        // Verify device belongs to user's store (Admin can delete any)
        if (!IsAdmin)
        {
            var device = await deviceRepository.GetByIdAsync(id);
            if (device == null)
                return Ok(AppResponse<Guid>.Error("KhÃ´ng tÃ¬m tháº¥y thiáº¿t bá»‹"));
            if (device.StoreId != GetCurrentStoreId())
                return Ok(AppResponse<Guid>.Error("Báº¡n khÃ´ng cÃ³ quyá»n xÃ³a thiáº¿t bá»‹ nÃ y"));
        }

        var cmd = new DeleteDeviceCommand(id);
        return Ok(await bus.Send(cmd));
    }

    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [HttpPut("{id}/toggle-active")]
    [RequireModulePermission("Device", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<DeviceDto>>> ActiveDevice(Guid id)
    {
        var cmd = new ToggleActiveCommand(id);
        return Ok(await bus.Send(cmd));
    }
    
    [HttpGet("{deviceId}/device-info")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Device", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<DeviceInfoDto>>> GetDeviceInfo(Guid deviceId)
    {
        var query = new GetDeviceInfoQuery(deviceId);
        return Ok(await bus.Send(query));
    }

    /// <summary>ADMS capability / engine profile (QUERY, ENROLL_FP, stamp sync).</summary>
    [HttpGet("{deviceId}/capability")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Device", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<DeviceCapabilityDto>>> GetDeviceCapability(Guid deviceId)
    {
        var dto = await capabilityService.GetCapabilityDtoAsync(deviceId);
        return Ok(AppResponse<DeviceCapabilityDto>.Success(dto));
    }

    /// <summary>
    /// Refresh tráº¡ng thÃ¡i online/offline cá»§a thiáº¿t bá»‹ dá»±a trÃªn LastOnline thá»±c táº¿
    /// </summary>
    [HttpGet("{deviceId}/refresh-status")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Device", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> RefreshDeviceStatus(Guid deviceId)
    {
        var device = await deviceRepository.GetByIdAsync(deviceId);
        if (device == null)
            return NotFound(AppResponse<object>.Fail("Thiáº¿t bá»‹ khÃ´ng tá»“n táº¡i"));

        var isOnline = device.LastOnline != null && 
                       DateTime.UtcNow.Subtract(device.LastOnline.Value).TotalSeconds <= 90;
        
        // Update DeviceStatus in DB if inconsistent
        var expectedStatus = isOnline ? "Online" : "Offline";
        if (device.DeviceStatus != expectedStatus)
        {
            device.DeviceStatus = expectedStatus;
            device.UpdatedAt = DateTime.UtcNow;
            await deviceRepository.UpdateAsync(device);
        }

        return Ok(AppResponse<object>.Success(new
        {
            device.Id,
            device.SerialNumber,
            device.DeviceName,
            IsOnline = isOnline,
            DeviceStatus = expectedStatus,
            device.LastOnline,
        }));
    }
    
    /// <summary>
    /// Láº¥y danh sÃ¡ch thiáº¿t bá»‹ Ä‘ang chá» duyá»‡t (Pending)
    /// </summary>
    [HttpGet("pending")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Device", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<IEnumerable<DeviceDto>>>> GetPendingDevices()
    {
        var devices = await deviceService.GetPendingDevicesAsync();
        
        // Non-admin users only see pending devices without store or belonging to their store
        if (!IsAdmin)
        {
            var storeId = GetCurrentStoreId();
            devices = devices.Where(d => !d.StoreId.HasValue || d.StoreId == storeId);
        }
        
        var deviceDtos = devices.Adapt<IEnumerable<DeviceDto>>();
        return Ok(AppResponse<IEnumerable<DeviceDto>>.Success(deviceDtos));
    }
    
    /// <summary>
    /// Láº¥y danh sÃ¡ch thiáº¿t bá»‹ Ä‘ang káº¿t ná»‘i (online trong 5 phÃºt gáº§n Ä‘Ã¢y)
    /// </summary>
    [HttpGet("connected")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Device", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<IEnumerable<DeviceDto>>>> GetConnectedDevices()
    {
        var devices = await deviceService.GetConnectedDevicesAsync();
        
        // Non-admin users only see connected devices belonging to their store
        if (!IsAdmin)
        {
            var storeId = GetCurrentStoreId();
            devices = devices.Where(d => d.StoreId == storeId);
        }
        
        var deviceDtos = devices.Adapt<IEnumerable<DeviceDto>>();
        return Ok(AppResponse<IEnumerable<DeviceDto>>.Success(deviceDtos));
    }
    
    /// <summary>
    /// Duyá»‡t thiáº¿t bá»‹ - chuyá»ƒn tá»« Pending sang Active (Admin only)
    /// </summary>
    [HttpPost("{id}/approve")]
    [Authorize(Policy = PolicyNames.AdminOnly)]
    [RequireModulePermission("Device", ModulePermissionAction.Approve)]
    public async Task<ActionResult<AppResponse<DeviceDto>>> ApproveDevice(Guid id, [FromBody] ApproveDeviceRequest request)
    {
        var device = await deviceService.ApproveDeviceAsync(id, request.DeviceName, request.Description, request.Location);
        if (device == null)
        {
            return Ok(AppResponse<DeviceDto>.Error("KhÃ´ng tÃ¬m tháº¥y thiáº¿t bá»‹"));
        }
        
        var deviceDto = device.Adapt<DeviceDto>();
        return Ok(AppResponse<DeviceDto>.Success(deviceDto));
    }
    
    /// <summary>
    /// Tá»« chá»‘i thiáº¿t bá»‹ - xÃ³a khá»i danh sÃ¡ch (Admin only)
    /// </summary>
    [HttpDelete("{id}/reject")]
    [Authorize(Policy = PolicyNames.AdminOnly)]
    [RequireModulePermission("Device", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> RejectDevice(Guid id)
    {
        var result = await deviceService.RejectDeviceAsync(id);
        if (!result)
        {
            return Ok(AppResponse<bool>.Error("KhÃ´ng tÃ¬m tháº¥y thiáº¿t bá»‹"));
        }
        
        return Ok(AppResponse<bool>.Success(true));
    }
    
    // ==================== USER CLAIM DEVICE APIs ====================
    
    /// <summary>
    /// Láº¥y danh sÃ¡ch thiáº¿t bá»‹ Ä‘Ã£ claim cá»§a user hiá»‡n táº¡i
    /// </summary>
    [HttpGet("my-devices")]
    [Authorize]
    [RequireModulePermission("Device", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<IEnumerable<DeviceDto>>>> GetMyDevices()
    {
        var devices = await deviceService.GetDevicesByOwnerAsync(CurrentUserId);
        var deviceDtos = devices.Adapt<IEnumerable<DeviceDto>>();
        return Ok(AppResponse<IEnumerable<DeviceDto>>.Success(deviceDtos));
    }
    
    /// <summary>
    /// User claim thiáº¿t bá»‹ báº±ng Serial Number
    /// Náº¿u thiáº¿t bá»‹ Ä‘Ã£ káº¿t ná»‘i vá»›i server vÃ  chÆ°a Ä‘Æ°á»£c claim, sáº½ gÃ¡n cho user
    /// </summary>
    [HttpPost("claim")]
    [Authorize]
    [RequireModulePermission("Device", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<DeviceDto>>> ClaimDevice([FromBody] ClaimDeviceRequest request)
    {
        var result = await deviceService.ClaimDeviceAsync(
            CurrentUserId, 
            request.SerialNumber, 
            request.DeviceName, 
            request.Description, 
            request.Location);
        
        if (!result.IsSuccess)
        {
            return Ok(AppResponse<DeviceDto>.Error(result.Message));
        }
        
        var deviceDto = result.Data!.Adapt<DeviceDto>();
        return Ok(AppResponse<DeviceDto>.Success(deviceDto));
    }
    
    /// <summary>
    /// Kiá»ƒm tra Serial Number cÃ³ tá»“n táº¡i vÃ  available khÃ´ng
    /// </summary>
    [HttpGet("check-serial/{serialNumber}")]
    [Authorize]
    public async Task<ActionResult<AppResponse<DeviceAvailabilityDto>>> CheckSerialNumber(string serialNumber)
    {
        var device = await deviceService.GetDeviceBySerialNumberAsync(serialNumber);
        
        var availability = new DeviceAvailabilityDto
        {
            SerialNumber = serialNumber,
            Exists = device != null,
            IsAvailable = device != null && !device.IsClaimed,
            IsClaimed = device?.IsClaimed ?? false,
            LastOnline = device?.LastOnline,
            Message = device == null 
                ? "Thiáº¿t bá»‹ chÆ°a káº¿t ná»‘i vá»›i server" 
                : device.IsClaimed 
                    ? "Thiáº¿t bá»‹ Ä‘Ã£ Ä‘Æ°á»£c Ä‘Äƒng kÃ½ bá»Ÿi tÃ i khoáº£n khÃ¡c" 
                    : "Thiáº¿t bá»‹ sáºµn sÃ ng Ä‘á»ƒ Ä‘Äƒng kÃ½"
        };
        
        return Ok(AppResponse<DeviceAvailabilityDto>.Success(availability));
    }
    
    /// <summary>
    /// User unclaim thiáº¿t bá»‹ - tráº£ láº¡i thiáº¿t bá»‹ vá» tráº¡ng thÃ¡i available
    /// </summary>
    [HttpPost("{id}/unclaim")]
    [Authorize]
    [RequireModulePermission("Device", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<bool>>> UnclaimDevice(Guid id)
    {
        var result = await deviceService.UnclaimDeviceAsync(id, CurrentUserId);
        if (!result.IsSuccess)
        {
            return Ok(AppResponse<bool>.Error(result.Message));
        }
        
        return Ok(AppResponse<bool>.Success(true));
    }
    
    /// <summary>
    /// Cáº­p nháº­t thÃ´ng tin thiáº¿t bá»‹ (tÃªn, vá»‹ trÃ­, mÃ´ táº£)
    /// </summary>
    [HttpPut("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Device", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<DeviceDto>>> UpdateDevice(Guid id, [FromBody] UpdateDeviceRequest request)
    {
        var device = await deviceRepository.GetByIdAsync(id);
        if (device == null)
        {
            return Ok(AppResponse<DeviceDto>.Error("KhÃ´ng tÃ¬m tháº¥y thiáº¿t bá»‹"));
        }

        // Verify device belongs to user's store (Admin can update any)
        if (!IsAdmin && device.StoreId != GetCurrentStoreId())
        {
            return Ok(AppResponse<DeviceDto>.Error("Báº¡n khÃ´ng cÃ³ quyá»n cáº­p nháº­t thiáº¿t bá»‹ nÃ y"));
        }
        
        if (!string.IsNullOrWhiteSpace(request.DeviceName))
            device.DeviceName = request.DeviceName;
        if (request.Location != null)
            device.Location = request.Location;
        if (request.Description != null)
            device.Description = request.Description;
            
        device.UpdatedAt = DateTime.UtcNow;
        await deviceRepository.UpdateAsync(device);
        
        var deviceDto = device.Adapt<DeviceDto>();
        return Ok(AppResponse<DeviceDto>.Success(deviceDto));
    }
}

/// <summary>
/// Request model cho viá»‡c duyá»‡t thiáº¿t bá»‹ (Admin)
/// </summary>
public class ApproveDeviceRequest
{
    public string DeviceName { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string? Location { get; set; }
}

/// <summary>
/// Request model cho user claim thiáº¿t bá»‹
/// </summary>
public class ClaimDeviceRequest
{
    public string SerialNumber { get; set; } = string.Empty;
    public string DeviceName { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string? Location { get; set; }
}

/// <summary>
/// DTO kiá»ƒm tra tÃ¬nh tráº¡ng thiáº¿t bá»‹
/// </summary>
public class DeviceAvailabilityDto
{
    public string SerialNumber { get; set; } = string.Empty;
    public bool Exists { get; set; }
    public bool IsAvailable { get; set; }
    public bool IsClaimed { get; set; }
    public DateTime? LastOnline { get; set; }
    public string Message { get; set; } = string.Empty;
}

/// <summary>
/// Request model cho viá»‡c cáº­p nháº­t thÃ´ng tin thiáº¿t bá»‹
/// </summary>
public class UpdateDeviceRequest
{
    public string? DeviceName { get; set; }
    public string? Description { get; set; }
    public string? Location { get; set; }
}

