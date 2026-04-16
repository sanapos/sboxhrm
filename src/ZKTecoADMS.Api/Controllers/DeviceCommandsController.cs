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
        logger.LogInformation("[CreateCommand] DeviceId={DeviceId}, CommandType={CommandType}, Priority={Priority}, Command={Command}", 
            deviceId, request.CommandType, request.Priority, request.Command);
        
        var cmd = new CreateDeviceCmdCommand(deviceId, request.CommandType, request.Priority, request.Command);
        var result = await bus.Send(cmd);
        
        logger.LogInformation("[CreateCommand] Result: IsSuccess={IsSuccess}, Message={Message}", 
            result.IsSuccess, result.Message);
        
        return Ok(result);
    }

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
        var command = await dbContext.DeviceCommands
            .FirstOrDefaultAsync(c => c.Id == commandId);

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
