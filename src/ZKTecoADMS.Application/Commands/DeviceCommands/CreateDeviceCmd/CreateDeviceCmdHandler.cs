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
        
        if (commandType == DeviceCommandTypes.SyncAttendances)
        {
            await CancelStaleSyncAttendanceCommandsAsync(device.Id, cancellationToken);
            AttendanceBulkDeleteGuard.ClearAutoSyncSuppress(device.Id);
            AttendanceBulkSyncTracker.ClearUploadActivity(device.Id);
        }

        logger.LogWarning("[CreateDeviceCmd] Creating command: DeviceId={DeviceId}, Command={Command}, Status={Status}, CommandType={CommandType}", 
            command.DeviceId, command.Command, command.Status, command.CommandType);
        
        var created = await deviceCmdRepository.AddAsync(command, cancellationToken);

        if (commandType == DeviceCommandTypes.SyncAttendances)
        {
            logger.LogInformation(
                "[CreateDeviceCmd] SyncAttendances queued for {DeviceId} — reset sync tracker",
                device.Id);
        }
        
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
            DeviceCommandTypes.SyncAttendances => ClockCommandBuilder.BuildDefaultSyncAttendancesCommand(),
            DeviceCommandTypes.SyncDeviceUsers => ClockCommandBuilder.BuildGetAllUsersCommand(),
            // SyncFingerprints: Query fingerprint templates
            DeviceCommandTypes.SyncFingerprints => ClockCommandBuilder.BuildGetFingerprintsCommand(),
            _ => "NOT IMPLEMENTED"
        };
    }

    /// <summary>Hủy lệnh SyncAttendances cũ (Created/Sent) trước khi xếp lệnh mới — tránh kẹt nhiều lệnh Sent.</summary>
    private async Task CancelStaleSyncAttendanceCommandsAsync(Guid deviceId, CancellationToken cancellationToken)
    {
        var stale = await deviceCmdRepository.GetAllAsync(
            c => c.DeviceId == deviceId
                 && c.CommandType == DeviceCommandTypes.SyncAttendances
                 && (c.Status == CommandStatus.Created || c.Status == CommandStatus.Sent),
            cancellationToken: cancellationToken);

        foreach (var cmd in stale)
        {
            var previous = cmd.Status;
            cmd.Status = CommandStatus.Failed;
            cmd.SentAt = null;
            await deviceCmdRepository.UpdateAsync(cmd, cancellationToken);
            logger.LogInformation(
                "[CreateDeviceCmd] Cancelled stale SyncAttendances {CommandId} (was {Status}) for {DeviceId}",
                cmd.CommandId, previous, deviceId);
        }
    }
}
