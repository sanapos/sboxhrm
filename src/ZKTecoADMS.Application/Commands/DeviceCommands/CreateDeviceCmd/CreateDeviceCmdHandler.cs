using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Devices;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.DeviceCommands.CreateDeviceCmd;

public class CreateDeviceCmdHandler(
    IRepository<Device> deviceRepository, 
    IRepository<DeviceCommand> deviceCmdRepository,
    ILogger<CreateDeviceCmdHandler> logger) : ICommandHandler<CreateDeviceCmdCommand, AppResponse<DeviceCmdDto>>
{
    public async Task<AppResponse<DeviceCmdDto>> Handle(CreateDeviceCmdCommand request, CancellationToken cancellationToken)
    {
        logger.LogWarning("[CreateDeviceCmd] Received request: DeviceId={DeviceId}, CommandType={CommandType}", 
            request.DeviceId, request.CommandType);
        
        var device = await deviceRepository.GetByIdAsync(request.DeviceId, cancellationToken: cancellationToken);
        if (device == null)
        {
            logger.LogWarning("[CreateDeviceCmd] Device not found: {DeviceId}", request.DeviceId);
            return AppResponse<DeviceCmdDto>.Fail("Device not found");
        }
        var commandType = (DeviceCommandTypes)request.CommandType;
        
        // Nếu có command string từ client (cho EnrollFingerprint, DeleteFingerprint), dùng nó
        // Ngược lại, tạo command string từ command type
        var commandStr = !string.IsNullOrEmpty(request.Command) 
            ? request.Command 
            : GetCommand(commandType, request.DeviceId);
        
        var command = new DeviceCommand
        {
            DeviceId = device.Id,
            Command = commandStr,
            Priority = request.Priority,
            CommandType = commandType,
            Status = CommandStatus.Created // Explicitly set status
        };
        
        logger.LogWarning("[CreateDeviceCmd] Creating command: DeviceId={DeviceId}, Command={Command}, Status={Status}, CommandType={CommandType}", 
            command.DeviceId, command.Command, command.Status, command.CommandType);
        
        var created = await deviceCmdRepository.AddAsync(command, cancellationToken);
        
        logger.LogWarning("[CreateDeviceCmd] Command created successfully: Id={Id}, CommandId={CommandId}, Status={Status}", 
            created.Id, created.CommandId, created.Status);

        return AppResponse<DeviceCmdDto>.Success(created.Adapt<DeviceCmdDto>());
    }

    private static string GetCommand(DeviceCommandTypes commandType, Guid id)
    {
        return commandType switch
        {
            DeviceCommandTypes.ClearAttendances => "CLEAR LOG",
            DeviceCommandTypes.ClearDeviceUsers => "CLEAR ALL USERINFO",
            DeviceCommandTypes.ClearData => "CLEAR DATA",
            DeviceCommandTypes.RestartDevice => "REBOOT",
            DeviceCommandTypes.SyncAttendances => ClockCommandBuilder.BuildGetAttendanceCommand(DateTime.Now.AddYears(-5), DateTime.Now),
            // SyncDeviceUsers: Dùng CHECK USERINFO để yêu cầu máy gửi lại toàn bộ danh sách user
            // Device sẽ POST data với table=OPERLOG chứa USER PIN=xxx\tName=xxx\t...
            DeviceCommandTypes.SyncDeviceUsers => "CHECK USERINFO",
            // SyncFingerprints: Query fingerprint templates
            DeviceCommandTypes.SyncFingerprints => ClockCommandBuilder.BuildGetFingerprintsCommand(),
            _ => "NOT IMPLEMENTED"
        };
    }
}
