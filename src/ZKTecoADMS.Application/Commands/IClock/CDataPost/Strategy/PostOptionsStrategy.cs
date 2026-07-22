using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Commands.IClock.CDataPost.Strategy;

/// <summary>
/// Handles POST /iclock/cdata?table=options from PUSH protocol devices.
/// </summary>
public class PostOptionsStrategy(IServiceProvider serviceProvider) : IPostStrategy
{
    private readonly IRepository<DeviceInfo> _deviceInfoRepository =
        serviceProvider.GetRequiredService<IRepository<DeviceInfo>>();
    private readonly IDeviceCapabilityService _capabilityService =
        serviceProvider.GetRequiredService<IDeviceCapabilityService>();
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

        var firmware = GetOption(options, "FirmwareVersion", "~FirmwareVersion", "FWVersion");
        if (!string.IsNullOrWhiteSpace(firmware))
            deviceInfo.FirmwareVersion = Truncate(firmware, 200);

        var userCount = GetOption(options, "UserCount", "~UserCount");
        if (int.TryParse(userCount, out var users))
            deviceInfo.EnrolledUserCount = users;

        var fpCount = GetOption(options, "FPCount", "~FPCount");
        if (int.TryParse(fpCount, out var fps))
            deviceInfo.FingerprintCount = fps;

        var attCount = GetOption(options, "AttCount", "~AttCount", "TransactionCount", "~TransactionCount");
        if (int.TryParse(attCount, out var atts))
            deviceInfo.AttendanceCount = atts;

        var ip = GetOption(options, "IPAddress", "~IPAddress", "IP");
        if (!string.IsNullOrWhiteSpace(ip))
            deviceInfo.DeviceIp = Truncate(ip, 200);

        var fpVer = GetOption(options, "ZKFPVersion", "~ZKFPVersion", "FPVersion");
        if (!string.IsNullOrWhiteSpace(fpVer))
            deviceInfo.FingerprintVersion = Truncate(fpVer, 200);

        var faceVer = GetOption(options, "FaceVersion", "~FaceVersion", "ZKFaceVersion", "~ZKFaceVersion");
        if (!string.IsNullOrWhiteSpace(faceVer))
            deviceInfo.FaceVersion = Truncate(faceVer, 200);

        var faceCount = GetOption(options, "FaceCount", "~FaceCount");
        if (!string.IsNullOrWhiteSpace(faceCount))
            deviceInfo.FaceTemplateCount = Truncate(faceCount, 200);

        var platform = GetOption(options, "Platform", "~Platform");
        var deviceModel = GetOption(options, "DeviceName", "~DeviceName");
        var oem = GetOption(options, "OEMVendor", "~OEMVendor");
        var pushVer = GetOption(options, "PushVersion", "~PushVersion", "PushVer");

        if (!string.IsNullOrWhiteSpace(platform) || !string.IsNullOrWhiteSpace(deviceModel) || !string.IsNullOrWhiteSpace(oem))
            deviceInfo.DevSupportData = Truncate(
                string.Join(",", new[] { platform, deviceModel, oem }.Where(s => !string.IsNullOrWhiteSpace(s))),
                200);

        // Access / lock indicators from device options (Security PUSH / ACC)
        var lockCountRaw = GetOption(options, "LockCount", "~LockCount");
        var lockFun = GetOption(options, "LockFunOn", "~LockFunOn", "DoorFunOn", "~DoorFunOn");
        if (int.TryParse(lockCountRaw, out var lockCount) && lockCount > 0)
            deviceInfo.SupportsDoorControl = true;
        else if (lockFun is "1" or "true" or "True")
            deviceInfo.SupportsDoorControl = true;

        await _deviceInfoRepository.AddOrUpdateAsync(deviceInfo);

        await _capabilityService.ApplyIdentityFromOptionsAsync(
            device.Id, platform, firmware, pushVer, deviceModel, oem);

        _logger.LogWarning(
            "[PostOptions] DeviceInfo updated for {SN}: Firmware={FW}, Platform={Platform}, Model={Model}, Users={Users}",
            device.SerialNumber, deviceInfo.FirmwareVersion, platform, deviceModel, deviceInfo.EnrolledUserCount);

        return ClockResponses.Ok;
    }

    private static Dictionary<string, string> ParseOptions(string body)
    {
        var options = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (string.IsNullOrWhiteSpace(body)) return options;

        // SenseFace / agap often POST comma-separated key=value (one line).
        // Older firmwares use newline-separated pairs.
        var normalized = body.Replace("\r\n", "\n").Replace('\r', '\n');
        var parts = normalized.Contains(',') && !normalized.Contains('\n')
            ? normalized.Split(',', StringSplitOptions.RemoveEmptyEntries)
            : normalized.Split('\n', StringSplitOptions.RemoveEmptyEntries);

        foreach (var part in parts)
        {
            var trimmed = part.Trim();
            var eqIndex = trimmed.IndexOf('=');
            if (eqIndex <= 0) continue;
            var key = trimmed[..eqIndex].Trim();
            var value = trimmed[(eqIndex + 1)..].Trim();
            if (key.Length == 0) continue;
            options[key] = value;
        }

        return options;
    }

    private static string? Truncate(string? value, int maxLen)
    {
        if (string.IsNullOrEmpty(value) || value.Length <= maxLen) return value;
        return value[..maxLen];
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
