using ZKTecoADMS.Application.DTOs.Devices;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Application.Queries.Devices.GetDevicesByUser;
using ZKTecoADMS.Application.Queries.Devices.GetAllDevices;
using ZKTecoADMS.Application.Queries.Devices.GetDeviceById;
using Mapster;
using Microsoft.AspNetCore.Authorization;
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
    IRepository<Device> deviceRepository
    ) : AuthenticatedControllerBase
{
    [HttpGet("users/{CurrentUserId}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<DeviceDto>>> GetDevicesByUser(Guid CurrentUserId)
    {
        var query = new GetDevicesByUserQuery(CurrentUserId);
        return Ok(await bus.Send(query));
    }
    
    [HttpGet]
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
    public async Task<ActionResult<AppResponse<DeviceDto>>> GetDeviceById(Guid id)
    {
        var query = new GetDeviceByIdQuery(id);
        return Ok(await bus.Send(query));
    }

    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
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
            return Ok(AppResponse<DeviceDto>.Error($"Lỗi thêm thiết bị: {ex.Message}"));
        }
    }

    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<Guid>>> DeleteDevice(Guid id)
    {
        // Verify device belongs to user's store (Admin can delete any)
        if (!IsAdmin)
        {
            var device = await deviceRepository.GetByIdAsync(id);
            if (device == null)
                return Ok(AppResponse<Guid>.Error("Không tìm thấy thiết bị"));
            if (device.StoreId != GetCurrentStoreId())
                return Ok(AppResponse<Guid>.Error("Bạn không có quyền xóa thiết bị này"));
        }

        var cmd = new DeleteDeviceCommand(id);
        return Ok(await bus.Send(cmd));
    }

    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [HttpPut("{id}/toggle-active")]
    public async Task<ActionResult<AppResponse<DeviceDto>>> ActiveDevice(Guid id)
    {
        var cmd = new ToggleActiveCommand(id);
        return Ok(await bus.Send(cmd));
    }
    
    [HttpGet("{deviceId}/device-info")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<DeviceInfoDto>>> GetDeviceInfo(Guid deviceId)
    {
        var query = new GetDeviceInfoQuery(deviceId);
        return Ok(await bus.Send(query));
    }

    /// <summary>
    /// Refresh trạng thái online/offline của thiết bị dựa trên LastOnline thực tế
    /// </summary>
    [HttpGet("{deviceId}/refresh-status")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<object>>> RefreshDeviceStatus(Guid deviceId)
    {
        var device = await deviceRepository.GetByIdAsync(deviceId);
        if (device == null)
            return NotFound(AppResponse<object>.Fail("Thiết bị không tồn tại"));

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
    /// Lấy danh sách thiết bị đang chờ duyệt (Pending)
    /// </summary>
    [HttpGet("pending")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
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
    /// Lấy danh sách thiết bị đang kết nối (online trong 5 phút gần đây)
    /// </summary>
    [HttpGet("connected")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
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
    /// Duyệt thiết bị - chuyển từ Pending sang Active (Admin only)
    /// </summary>
    [HttpPost("{id}/approve")]
    [Authorize(Policy = PolicyNames.AdminOnly)]
    public async Task<ActionResult<AppResponse<DeviceDto>>> ApproveDevice(Guid id, [FromBody] ApproveDeviceRequest request)
    {
        var device = await deviceService.ApproveDeviceAsync(id, request.DeviceName, request.Description, request.Location);
        if (device == null)
        {
            return Ok(AppResponse<DeviceDto>.Error("Không tìm thấy thiết bị"));
        }
        
        var deviceDto = device.Adapt<DeviceDto>();
        return Ok(AppResponse<DeviceDto>.Success(deviceDto));
    }
    
    /// <summary>
    /// Từ chối thiết bị - xóa khỏi danh sách (Admin only)
    /// </summary>
    [HttpDelete("{id}/reject")]
    [Authorize(Policy = PolicyNames.AdminOnly)]
    public async Task<ActionResult<AppResponse<bool>>> RejectDevice(Guid id)
    {
        var result = await deviceService.RejectDeviceAsync(id);
        if (!result)
        {
            return Ok(AppResponse<bool>.Error("Không tìm thấy thiết bị"));
        }
        
        return Ok(AppResponse<bool>.Success(true));
    }
    
    // ==================== USER CLAIM DEVICE APIs ====================
    
    /// <summary>
    /// Lấy danh sách thiết bị đã claim của user hiện tại
    /// </summary>
    [HttpGet("my-devices")]
    [Authorize]
    public async Task<ActionResult<AppResponse<IEnumerable<DeviceDto>>>> GetMyDevices()
    {
        var devices = await deviceService.GetDevicesByOwnerAsync(CurrentUserId);
        var deviceDtos = devices.Adapt<IEnumerable<DeviceDto>>();
        return Ok(AppResponse<IEnumerable<DeviceDto>>.Success(deviceDtos));
    }
    
    /// <summary>
    /// User claim thiết bị bằng Serial Number
    /// Nếu thiết bị đã kết nối với server và chưa được claim, sẽ gán cho user
    /// </summary>
    [HttpPost("claim")]
    [Authorize]
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
    /// Kiểm tra Serial Number có tồn tại và available không
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
                ? "Thiết bị chưa kết nối với server" 
                : device.IsClaimed 
                    ? "Thiết bị đã được đăng ký bởi tài khoản khác" 
                    : "Thiết bị sẵn sàng để đăng ký"
        };
        
        return Ok(AppResponse<DeviceAvailabilityDto>.Success(availability));
    }
    
    /// <summary>
    /// User unclaim thiết bị - trả lại thiết bị về trạng thái available
    /// </summary>
    [HttpPost("{id}/unclaim")]
    [Authorize]
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
    /// Cập nhật thông tin thiết bị (tên, vị trí, mô tả)
    /// </summary>
    [HttpPut("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<DeviceDto>>> UpdateDevice(Guid id, [FromBody] UpdateDeviceRequest request)
    {
        var device = await deviceRepository.GetByIdAsync(id);
        if (device == null)
        {
            return Ok(AppResponse<DeviceDto>.Error("Không tìm thấy thiết bị"));
        }

        // Verify device belongs to user's store (Admin can update any)
        if (!IsAdmin && device.StoreId != GetCurrentStoreId())
        {
            return Ok(AppResponse<DeviceDto>.Error("Bạn không có quyền cập nhật thiết bị này"));
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
/// Request model cho việc duyệt thiết bị (Admin)
/// </summary>
public class ApproveDeviceRequest
{
    public string DeviceName { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string? Location { get; set; }
}

/// <summary>
/// Request model cho user claim thiết bị
/// </summary>
public class ClaimDeviceRequest
{
    public string SerialNumber { get; set; } = string.Empty;
    public string DeviceName { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string? Location { get; set; }
}

/// <summary>
/// DTO kiểm tra tình trạng thiết bị
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
/// Request model cho việc cập nhật thông tin thiết bị
/// </summary>
public class UpdateDeviceRequest
{
    public string? DeviceName { get; set; }
    public string? Description { get; set; }
    public string? Location { get; set; }
}
