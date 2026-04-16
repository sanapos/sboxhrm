using System.Text;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Queries.IClock.GetRequest;

public class GetRequestHandler(
    IDeviceService deviceService,
    IDeviceCmdService deviceCmdService,
    IRepository<DeviceInfo> deviceInfoRepository,
    ILogger<GetRequestHandler> logger

    ) : ICommandHandler<GetRequestQuery, string>
{
    public async Task<string> Handle(GetRequestQuery request, CancellationToken cancellationToken)
    {
        var sn = request.SN;

        var device = await deviceService.GetDeviceBySerialNumberAsync(sn);
        if (device == null)
        {
            logger.LogWarning("[GetRequest] Device not found for SN: {SN}", sn);
            return ClockResponses.Ok;
        }

        // Thiết bị chưa liên kết cửa hàng → không gửi lệnh
        if (!device.StoreId.HasValue)
        {
            logger.LogInformation("[GetRequest] Device {SN} not linked to any store. No commands.", sn);
            return ClockResponses.Ok;
        }

        logger.LogWarning("[GetRequest] Device found: SN={SN}, DeviceId={DeviceId}", sn, device.Id);

        if (!string.IsNullOrEmpty(request.Info))
        {
            await UpdateDeviceInfoAsync(device.Id, request.Info);
        }

        var commands = await deviceCmdService.GetCreatedCommandsAsync(device.Id);

        var deviceCommands = commands.ToList();
        
        logger.LogWarning("[GetRequest] Device {SN} (ID: {DeviceId}) - Found {Count} pending commands", sn, device.Id, deviceCommands.Count);

        if (deviceCommands.Count == 0) return ClockResponses.Ok;

        var response = new StringBuilder();
        foreach (var command in deviceCommands.OrderByDescending(c => c.Priority))
        {
            var cmd = $"C:{command.CommandId}:{command.Command}";
            response.AppendLine(cmd);
            
            logger.LogInformation("[GetRequest] Sending command to device {SN}: {Cmd}", sn, cmd);

            await deviceCmdService.UpdateCommandStatusAsync(command.Id, CommandStatus.Sent);
        }

        return response.ToString();

    }
    
    private async Task UpdateDeviceInfoAsync(Guid deviceId, string info)
    {
        var deviceInfo = await deviceInfoRepository.GetSingleAsync(di => di.DeviceId == deviceId) ?? new DeviceInfo
        {
            DeviceId = deviceId
        };

        // INFO format: [firmware version],[enrolled users],[fingerprints],[attendance records],[device IP],[fingerprint version],[face version],[face templates count],[dev support data]
        var infoParts = info.Split(',', StringSplitOptions.None);

        // Parse each field based on position
        if (infoParts.Length > 0 && !string.IsNullOrWhiteSpace(infoParts[0]))
        {
            deviceInfo.FirmwareVersion = infoParts[0].Trim();
        }

        if (infoParts.Length > 1 && int.TryParse(infoParts[1], out var enrolledUsers))
        {
            deviceInfo.EnrolledUserCount = enrolledUsers;
        }

        if (infoParts.Length > 2 && int.TryParse(infoParts[2], out var fingerprintCount))
        {
            deviceInfo.FingerprintCount = fingerprintCount;
        }

        if (infoParts.Length > 3 && int.TryParse(infoParts[3], out var attendanceCount))
        {
            deviceInfo.AttendanceCount = attendanceCount;
        }

        if (infoParts.Length > 4 && !string.IsNullOrWhiteSpace(infoParts[4]))
        {
            deviceInfo.DeviceIp = infoParts[4].Trim();
        }

        if (infoParts.Length > 5 && !string.IsNullOrWhiteSpace(infoParts[5]))
        {
            deviceInfo.FingerprintVersion = infoParts[5].Trim();
        }

        if (infoParts.Length > 6 && !string.IsNullOrWhiteSpace(infoParts[6]))
        {
            deviceInfo.FaceVersion = infoParts[6].Trim();
        }

        if (infoParts.Length > 7 && !string.IsNullOrWhiteSpace(infoParts[7]))
        {
            deviceInfo.FaceTemplateCount = infoParts[7].Trim();
        }

        if (infoParts.Length > 8 && !string.IsNullOrWhiteSpace(infoParts[8]))
        {
            deviceInfo.DevSupportData = infoParts[8].Trim();
        }

        await deviceInfoRepository.AddOrUpdateAsync(deviceInfo);
    }
}