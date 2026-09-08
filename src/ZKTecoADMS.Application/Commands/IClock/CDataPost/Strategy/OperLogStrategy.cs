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

        var (userBody, fpBody) = SplitUserAndFingerprintLines(body);
        if (!string.IsNullOrWhiteSpace(fpBody))
        {
            _logger.LogWarning(
                "[OperLog] Device {SN} OPERLOG contains fingerprint lines ({Len} chars) — saving TMP",
                device.SerialNumber, fpBody.Length);
            var bio = new PostBiometricStrategy(serviceProvider, "FINGERTMP");
            await bio.ProcessDataAsync(device, fpBody);
        }

        if (string.IsNullOrWhiteSpace(userBody))
            return ClockResponses.Ok;

        var bulkSyncInProgress = await IsUserBulkSyncInProgressAsync(device.Id);
        var users = await _deviceUserOperationService.ProcessUsersFromDeviceAsync(device, userBody);

        if (users.Count == 0)
        {
            _logger.LogWarning(
                "No valid USER lines in OPERLOG from device {DeviceId} (body length {Len})",
                device.Id, userBody.Length);
            if (bulkSyncInProgress || !string.IsNullOrWhiteSpace(fpBody))
                return ClockResponses.Ok;
            return ClockResponses.Fail;
        }

        await _deviceUserService.CreateDeviceUsersAsync(device.Id, users);
        _logger.LogInformation("Successfully saved/updated {Count} users from device {DeviceId}", users.Count, device.Id);

        return ClockResponses.Ok;
    }

    /// <summary>
    /// PUSH SDK: fingerprint templates arrive as OPERLOG lines
    /// <c>FP PIN=… FID=… Size=… Valid=… TMP=…</c> — not table=FINGERTMP.
    /// </summary>
    internal static (string UserBody, string FingerprintBody) SplitUserAndFingerprintLines(string body)
    {
        var user = new System.Text.StringBuilder();
        var fp = new System.Text.StringBuilder();
        foreach (var raw in body.Split(['\n', '\r'], StringSplitOptions.RemoveEmptyEntries))
        {
            var line = raw.Trim();
            if (line.Length == 0) continue;
            if (IsFingerprintOperLogLine(line))
                fp.Append(line).Append('\n');
            else
                user.Append(line).Append('\n');
        }

        return (user.ToString(), fp.ToString());
    }

    private static bool IsFingerprintOperLogLine(string line)
    {
        if (line.StartsWith("FP ", StringComparison.OrdinalIgnoreCase)
            || line.StartsWith("FP\t", StringComparison.OrdinalIgnoreCase)
            || line.StartsWith("FINGERTMP", StringComparison.OrdinalIgnoreCase))
            return true;
        return line.Contains("FID=", StringComparison.OrdinalIgnoreCase)
            && line.Contains("TMP=", StringComparison.OrdinalIgnoreCase)
            && !line.StartsWith("USER", StringComparison.OrdinalIgnoreCase);
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
