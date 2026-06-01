using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.IClock.CDataPost.Strategy;

/// <summary>
/// Handles OPERLOG / USERINFO uploads from device to server.
/// </summary>
public class OperLogStrategy(IServiceProvider serviceProvider) : IPostStrategy
{
    private readonly IDeviceUserOperationService _deviceUserOperationService = serviceProvider.GetRequiredService<IDeviceUserOperationService>();
    private readonly IDeviceUserService _deviceUserService = serviceProvider.GetRequiredService<IDeviceUserService>();
    private readonly IDeviceCmdService _deviceCmdService = serviceProvider.GetRequiredService<IDeviceCmdService>();
    private readonly ILogger<OperLogStrategy> _logger = serviceProvider.GetRequiredService<ILogger<OperLogStrategy>>();

    public async Task<string> ProcessDataAsync(Device device, string body)
    {
        if (string.IsNullOrWhiteSpace(body))
        {
            _logger.LogInformation(
                "Device {DeviceId}: empty OPERLOG/USERINFO — end of user sync",
                device.Id);
            await CompleteSyncUserCommandsAsync(device.Id);
            return ClockResponses.Ok;
        }

        var bulkSyncInProgress = await IsUserBulkSyncInProgressAsync(device.Id);
        var users = await _deviceUserOperationService.ProcessUsersFromDeviceAsync(device, body);

        if (users.Count == 0)
        {
            _logger.LogWarning(
                "No valid USER lines in OPERLOG from device {DeviceId} (body length {Len})",
                device.Id, body.Length);
            if (bulkSyncInProgress)
            {
                return ClockResponses.Ok;
            }
            return ClockResponses.Fail;
        }

        await _deviceUserService.CreateDeviceUsersAsync(device.Id, users);
        _logger.LogInformation("Successfully saved/updated {Count} users from device {DeviceId}", users.Count, device.Id);

        // Không đánh dấu Success sau mỗi batch — chờ body rỗng hoặc auto-complete stale ở CDataGet
        return ClockResponses.Ok;
    }

    private async Task<bool> IsUserBulkSyncInProgressAsync(Guid deviceId)
    {
        var pending = await _deviceCmdService.GetPendingCommandsAsync(deviceId);
        return pending.Any(c => c.CommandType == DeviceCommandTypes.SyncDeviceUsers);
    }

    private async Task CompleteSyncUserCommandsAsync(Guid deviceId)
    {
        try
        {
            var pending = await _deviceCmdService.GetPendingCommandsAsync(deviceId);
            foreach (var cmd in pending.Where(c => c.CommandType == DeviceCommandTypes.SyncDeviceUsers))
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
