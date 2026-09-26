using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Application.DTOs.Devices;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Application.Queries.DeviceCommands.GetCommandsByDevice;
using ZKTecoADMS.Application.Commands.DeviceCommands.CreateDeviceCmd;
using ZKTecoADMS.Application.Queries.DeviceCommands.GetPendingCommands;
using ZKTecoADMS.Domain.Entities;
using Microsoft.AspNetCore.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/devices/{deviceId}/commands")]
public class DeviceCommandsController(
    IMediator bus,
    ILogger<DeviceCommandsController> logger
    ) : AuthenticatedControllerBase
{
    [HttpGet]
    public async Task<ActionResult<AppResponse<IEnumerable<DeviceCmdDto>>>> GetCommandsByDevice(Guid deviceId)
    {
        var query = new GetCommandsByDeviceQuery(deviceId);
        return Ok(await bus.Send(query));
    }

    [HttpPost]
    public async Task<ActionResult<DeviceCmdDto>> CreateDeviceCommand(Guid deviceId, [FromBody] DeviceCmdRequest request)
    {
        // Lệnh đọc (đồng bộ) chỉ cần xem; lệnh sửa người dùng / vân tay / khuôn mặt cần Sửa người
        // dùng máy; lệnh xóa sạch / khởi động lại / mở cửa cần Sửa thiết bị.
        var (module, action) = RequiredPermissionFor((DeviceCommandTypes)request.CommandType);
        var permissionService = HttpContext.RequestServices.GetRequiredService<IModulePermissionService>();
        var allowed = module == null
            ? await permissionService.HasPermissionAsync(CurrentUserId, CurrentUserRole, CurrentStoreId,
                  "Device", ModulePermissionAction.View)
              || await permissionService.HasPermissionAsync(CurrentUserId, CurrentUserRole, CurrentStoreId,
                  "DeviceUser", ModulePermissionAction.View)
              || await permissionService.HasPermissionAsync(CurrentUserId, CurrentUserRole, CurrentStoreId,
                  "Attendance", ModulePermissionAction.View)
            : await permissionService.HasPermissionAsync(CurrentUserId, CurrentUserRole, CurrentStoreId,
                  module, action);
        if (!allowed)
            return StatusCode(StatusCodes.Status403Forbidden,
                AppResponse<object>.Fail("Tài khoản không có quyền gửi lệnh này tới máy chấm công."));

        logger.LogInformation("[CreateCommand] DeviceId={DeviceId}, CommandType={CommandType}, Priority={Priority}, Command={Command}", 
            deviceId, request.CommandType, request.Priority, request.Command);
        
        var cmd = new CreateDeviceCmdCommand(
            deviceId,
            request.CommandType,
            request.Priority,
            request.Command,
            request.Pin,
            request.FingerIndex);
        var result = await bus.Send(cmd);
        
        logger.LogInformation("[CreateCommand] Result: IsSuccess={IsSuccess}, Message={Message}", 
            result.IsSuccess, result.Message);
        
        return Ok(result);
    }

    static (string? Module, ModulePermissionAction Action) RequiredPermissionFor(DeviceCommandTypes type) => type switch
    {
        DeviceCommandTypes.SyncAttendances or DeviceCommandTypes.SyncDeviceUsers
            or DeviceCommandTypes.SyncFingerprints or DeviceCommandTypes.SyncFaces
            or DeviceCommandTypes.GetDeviceInfo => (null, ModulePermissionAction.View),
        DeviceCommandTypes.AddDeviceUser or DeviceCommandTypes.UpdateDeviceUser
            or DeviceCommandTypes.EnrollFingerprint or DeviceCommandTypes.EnrollFace
            or DeviceCommandTypes.PushFingerprint or DeviceCommandTypes.PushFace
            or DeviceCommandTypes.PushUserPic => ("DeviceUser", ModulePermissionAction.Edit),
        DeviceCommandTypes.DeleteDeviceUser or DeviceCommandTypes.DeleteFingerprint
            or DeviceCommandTypes.DeleteFace => ("DeviceUser", ModulePermissionAction.Delete),
        _ => ("Device", ModulePermissionAction.Edit), // xóa sạch, khởi động lại, mở / đóng cửa
    };

    [HttpGet("pending")]
    public async Task<ActionResult<AppResponse<IEnumerable<DeviceCommand>>>> GetPendingCommands(Guid deviceId)
    {
        var query = new GetPendingCmdQuery(deviceId);

        return Ok(await bus.Send(query));
    }
}

/// <summary>
/// Controller để lấy thông tin command theo ID
/// </summary>
[ApiController]
[Authorize]
[Route("api/devicecommands")]
public class DeviceCommandStatusController(ZKTecoDbContext dbContext) : AuthenticatedControllerBase
{
    [HttpGet("{commandId}")]
    public async Task<ActionResult<AppResponse<DeviceCmdDto>>> GetCommandById(Guid commandId)
    {
        // DeviceCommand không có StoreId — lọc qua Devices (có bộ lọc cửa hàng).
        var command = await dbContext.DeviceCommands
            .FirstOrDefaultAsync(c => c.Id == commandId && dbContext.Devices.Any(d => d.Id == c.DeviceId));

        if (command == null)
        {
            return NotFound(AppResponse<DeviceCmdDto>.Fail("Command not found"));
        }

        var dto = new DeviceCmdDto(
            Id: command.Id,
            CreatedAt: command.CreatedAt,
            UpdatedAt: command.UpdatedAt,
            UpdatedBy: command.UpdatedBy,
            CreatedBy: command.CreatedBy,
            DeviceId: command.DeviceId,
            Command: command.Command,
            Status: command.Status,
            CommandType: command.CommandType,
            ResponseData: command.ResponseData,
            ErrorMessage: command.ErrorMessage,
            SentAt: command.SentAt,
            CompletedAt: command.CompletedAt
        );

        return Ok(AppResponse<DeviceCmdDto>.Success(dto));
    }
}
