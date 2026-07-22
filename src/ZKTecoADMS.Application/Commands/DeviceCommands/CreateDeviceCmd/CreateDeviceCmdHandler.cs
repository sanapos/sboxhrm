using Mapster;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Devices;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.DeviceCommands.CreateDeviceCmd;

public class CreateDeviceCmdHandler(
    IRepository<Device> deviceRepository,
    IRepository<DeviceCommand> deviceCmdRepository,
    IDeviceCapabilityService capabilityService,
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

        DateTime? attStart = null;
        DateTime? attEnd = null;
        if (commandType == DeviceCommandTypes.SyncAttendances && string.IsNullOrWhiteSpace(request.Command))
        {
            attEnd = ClockCommandBuilder.VietnamEndOfToday();
            attStart = DateTime.UtcNow.AddHours(7).AddYears(-5);
        }

        var (commandStr, warning) = await capabilityService.ResolveCommandAsync(
            device.Id,
            commandType,
            request.Pin,
            request.FingerIndex,
            request.Command,
            attStart,
            attEnd,
            cancellationToken);

        if (string.IsNullOrWhiteSpace(commandStr) || commandStr == "NOT IMPLEMENTED")
        {
            return AppResponse<DeviceCmdDto>.Fail(
                warning ?? "Thiếu tham số hoặc lệnh không hỗ trợ trên máy này.");
        }

        var command = new DeviceCommand
        {
            DeviceId = device.Id,
            Command = commandStr,
            Priority = request.Priority,
            CommandType = commandType,
            Status = CommandStatus.Created
        };

        // agap uses C:OPENDOOR0:AC_UNLOCK — short suffix (0..9999), not DateTime.Ticks.
        if (commandType == DeviceCommandTypes.OpenDoor)
            command.CommandId = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() % 10_000;

        if (commandType == DeviceCommandTypes.SyncAttendances)
        {
            await CancelStaleSyncAttendanceCommandsAsync(device.Id, cancellationToken);
            AttendanceBulkDeleteGuard.ClearAutoSyncSuppress(device.Id);
            AttendanceBulkSyncTracker.ClearUploadActivity(device.Id);
        }

        logger.LogWarning(
            "[CreateDeviceCmd] Creating command: DeviceId={DeviceId}, Command={Command}, Status={Status}, CommandType={CommandType}, Warning={Warning}",
            command.DeviceId, command.Command, command.Status, command.CommandType, warning);

        var created = await deviceCmdRepository.AddAsync(command, cancellationToken);
        var dto = created.Adapt<DeviceCmdDto>();

        // Warning in Errors while IsSuccess=true so Message surfaces in clients without failing.
        return string.IsNullOrWhiteSpace(warning)
            ? AppResponse<DeviceCmdDto>.Success(dto)
            : AppResponse<DeviceCmdDto>.Create(true, dto, [warning]);
    }

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
