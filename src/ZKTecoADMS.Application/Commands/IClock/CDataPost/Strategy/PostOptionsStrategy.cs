using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Commands.IClock.CDataPost.Strategy;

/// <summary>
/// Handles POST /iclock/cdata?table=options from PUSH protocol devices.
/// The body contains key=value pairs with device info (firmware, user count, etc.)
/// This is the PUSH device equivalent of the INFO parameter in GET /iclock/getrequest.
/// </summary>
public class PostOptionsStrategy(IServiceProvider serviceProvider) : IPostStrategy
{
    private readonly IRepository<DeviceInfo> _deviceInfoRepository =
        serviceProvider.GetRequiredService<IRepository<DeviceInfo>>();
    private readonly ILogger<PostOptionsStrategy> _logger =
        serviceProvider.GetRequiredService<ILogger<PostOptionsStrategy>>();

    public async Task<string> ProcessDataAsync(Device device, string body)
    {
        _logger.LogWarning("[PostOptions] Processing options from device {SN} (ID: {DeviceId})",
            device.SerialNumber, device.Id);
        _logger.LogWarning("[PostOptions] Body: {Body}", body);

        var options = ParseOptions(body);

        var deviceInfo = await _deviceInfoRepository.GetSingleAsync(di => di.DeviceId == device.Id)
            ?? new DeviceInfo { DeviceId = device.Id };

        // FirmwareVersion - try multiple known keys
        var firmware = GetOption(options, "FirmwareVersion", "~FirmwareVersion", "FWVersion");
        if (!string.IsNullOrWhiteSpace(firmware))
            deviceInfo.FirmwareVersion = firmware;

        // Enrolled user count
        var userCount = GetOption(options, "UserCount", "~UserCount");
        if (int.TryParse(userCount, out var users))
            deviceInfo.EnrolledUserCount = users;

        // Fingerprint count
        var fpCount = GetOption(options, "FPCount", "~FPCount");
        if (int.TryParse(fpCount, out var fps))
            deviceInfo.FingerprintCount = fps;

        // Attendance record count
        var attCount = GetOption(options, "AttCount", "~AttCount", "TransactionCount", "~TransactionCount");
        if (int.TryParse(attCount, out var atts))
            deviceInfo.AttendanceCount = atts;

        // IP Address
        var ip = GetOption(options, "IPAddress", "~IPAddress", "IP");
        if (!string.IsNullOrWhiteSpace(ip))
            deviceInfo.DeviceIp = ip;

        // Fingerprint version
        var fpVer = GetOption(options, "ZKFPVersion", "~ZKFPVersion", "FPVersion");
        if (!string.IsNullOrWhiteSpace(fpVer))
            deviceInfo.FingerprintVersion = fpVer;

        // Face version
        var faceVer = GetOption(options, "FaceVersion", "~FaceVersion", "ZKFaceVersion", "~ZKFaceVersion", "FaceFunOn");
        if (!string.IsNullOrWhiteSpace(faceVer))
            deviceInfo.FaceVersion = faceVer;

        // Face template count
        var faceCount = GetOption(options, "FaceCount", "~FaceCount");
        if (!string.IsNullOrWhiteSpace(faceCount))
            deviceInfo.FaceTemplateCount = faceCount;

        // Platform / device support info
        var platform = GetOption(options, "Platform", "~Platform", "DeviceName", "~DeviceName", "~OEMVendor");
        if (!string.IsNullOrWhiteSpace(platform))
            deviceInfo.DevSupportData = platform;

        await _deviceInfoRepository.AddOrUpdateAsync(deviceInfo);

        _logger.LogWarning("[PostOptions] DeviceInfo updated for {SN}: Firmware={FW}, Users={Users}, FP={FP}, Face={Face}",
            device.SerialNumber, deviceInfo.FirmwareVersion, deviceInfo.EnrolledUserCount,
            deviceInfo.FingerprintCount, deviceInfo.FaceVersion);

        return ClockResponses.Ok;
    }

    private static Dictionary<string, string> ParseOptions(string body)
    {
        var options = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (string.IsNullOrWhiteSpace(body)) return options;

        var lines = body.Split('\n', StringSplitOptions.RemoveEmptyEntries);
        foreach (var line in lines)
        {
            var trimmed = line.Trim();
            var eqIndex = trimmed.IndexOf('=');
            if (eqIndex > 0)
            {
                var key = trimmed[..eqIndex].Trim();
                var value = trimmed[(eqIndex + 1)..].Trim();
                options[key] = value;
            }
        }

        return options;
    }

    private static string? GetOption(Dictionary<string, string> options, params string[] keys)
    {
        foreach (var key in keys)
        {
            if (options.TryGetValue(key, out var value) && !string.IsNullOrWhiteSpace(value))
                return value;
        }
        return null;
    }
}
