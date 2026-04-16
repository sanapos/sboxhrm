using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.IClock.CDataPost.Strategy;

/// <summary>
/// Handles OPERLOG data (employee information) uploads from device to server.
/// Format: USER PIN=%s\tName=%s\tPasswd=%d\tCard=%d\tGrp=%d\tTZ=%s
/// </summary>
public class OperLogStrategy(IServiceProvider serviceProvider) : IPostStrategy
{
    private readonly IDeviceUserOperationService _deviceUserOperationService = serviceProvider.GetRequiredService<IDeviceUserOperationService>();
    private readonly IDeviceUserService _deviceUserService = serviceProvider.GetRequiredService<IDeviceUserService>();
    private readonly IDeviceCmdService _deviceCmdService = serviceProvider.GetRequiredService<IDeviceCmdService>();
    private readonly ILogger<OperLogStrategy> _logger = serviceProvider.GetRequiredService<ILogger<OperLogStrategy>>();

    public async Task<string> ProcessDataAsync(Device device, string body)
    {
        // Step 1: Parse and process employees from device data
        var users = await _deviceUserOperationService.ProcessUsersFromDeviceAsync(device, body);

        if (users.Count == 0)
        {
            _logger.LogWarning("No valid employee records to save from device {DeviceId}", device.Id);
            return ClockResponses.Ok;
        }

        // Step 2: Persist users to database
        await _deviceUserService.CreateDeviceUsersAsync(device.Id, users);

        _logger.LogInformation("Successfully saved {Count} users from device {DeviceId}", users.Count, device.Id);

        // Step 3: Complete pending SyncDeviceUsers commands
        await CompleteSyncUserCommandsAsync(device.Id);

        return ClockResponses.Ok;
    }

    private async Task CompleteSyncUserCommandsAsync(Guid deviceId)
    {
        try
        {
            var pendingCommands = await _deviceCmdService.GetCreatedCommandsAsync(deviceId);
            var syncCommands = pendingCommands.Where(c => c.CommandType == DeviceCommandTypes.SyncDeviceUsers);
            
            foreach (var cmd in syncCommands)
            {
                await _deviceCmdService.UpdateCommandStatusAsync(cmd.Id, CommandStatus.Success);
                _logger.LogInformation("Completed SyncDeviceUsers command {CommandId} for device {DeviceId}", cmd.Id, deviceId);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error completing SyncDeviceUsers commands for device {DeviceId}", deviceId);
        }
    }
}