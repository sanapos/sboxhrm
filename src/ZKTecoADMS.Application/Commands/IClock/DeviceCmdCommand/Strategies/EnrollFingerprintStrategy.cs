using System.Text.RegularExpressions;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.IClock.DeviceCmdCommand.Strategies;

/// <summary>
/// Strategy for handling EnrollFingerprint command responses
/// Khi máy đăng ký vân tay thành công, lưu thông tin vào database
/// V8 firmware devices do NOT POST biometric data via ADMS, so we must save
/// the fingerprint record directly from the enrollment acknowledgment.
/// </summary>
[DeviceCommandStrategy(DeviceCommandTypes.EnrollFingerprint)]
public class EnrollFingerprintStrategy(
    IRepository<FingerprintTemplate> fingerprintRepository,
    IRepository<DeviceUser> deviceUserRepository,
    IRepository<DeviceCommand> deviceCommandRepository,
    ILogger<EnrollFingerprintStrategy> logger
) : IDeviceCommandStrategy
{
    public async Task ExecuteAsync(Device device, Guid objectRefId, ClockCommandResponse response, CancellationToken cancellationToken)
    {
        logger.LogWarning("[EnrollFingerprint] Processing for DeviceId={DeviceId}, CommandId={CommandId}, Return={Return}", 
            device.Id, response.CommandId, response.Return);

        if (response.Return != 0)
        {
            logger.LogWarning("[EnrollFingerprint] Device returned error code {Code}, skipping save", response.Return);
            return;
        }

        // Look up the original DeviceCommand to get the command string with PIN and FID
        var deviceCommand = await deviceCommandRepository.GetSingleAsync(
            c => c.CommandId == response.CommandId, cancellationToken: cancellationToken);
        
        if (deviceCommand == null)
        {
            logger.LogWarning("[EnrollFingerprint] DeviceCommand not found for CommandId={CommandId}", response.CommandId);
            return;
        }

        logger.LogWarning("[EnrollFingerprint] Found command: {Command}", deviceCommand.Command);

        // Parse PIN and FID from command string: "ENROLL_FP PIN=xxx\tFID=x"
        var pin = ParseValue(deviceCommand.Command, "PIN");
        var fidStr = ParseValue(deviceCommand.Command, "FID");
        
        if (string.IsNullOrEmpty(pin))
        {
            logger.LogWarning("[EnrollFingerprint] Could not parse PIN from command: {Command}", deviceCommand.Command);
            return;
        }

        int fingerIndex = 0;
        if (!string.IsNullOrEmpty(fidStr) && int.TryParse(fidStr, out var fid))
        {
            fingerIndex = fid;
        }

        logger.LogWarning("[EnrollFingerprint] Parsed PIN={Pin}, FID={FID}", pin, fingerIndex);

        // Find DeviceUser by PIN and DeviceId
        var deviceUser = await deviceUserRepository.GetSingleAsync(
            u => u.Pin == pin && u.DeviceId == device.Id, cancellationToken: cancellationToken);

        if (deviceUser == null)
        {
            logger.LogWarning("[EnrollFingerprint] DeviceUser not found for PIN={Pin}, DeviceId={DeviceId}", pin, device.Id);
            return;
        }

        logger.LogWarning("[EnrollFingerprint] Found DeviceUser: Id={UserId}, Name={Name}", deviceUser.Id, deviceUser.Name);

        // FID >= 50 is Face, FID 0-9 is Fingerprint
        if (fingerIndex >= 50)
        {
            logger.LogWarning("[EnrollFingerprint] FID={FID} is face enrollment, skipping fingerprint save", fingerIndex);
            return;
        }

        // Save or update FingerprintTemplate record
        var existing = await fingerprintRepository.GetSingleAsync(
            f => f.EmployeeId == deviceUser.Id && f.FingerIndex == fingerIndex, cancellationToken: cancellationToken);

        if (existing != null)
        {
            existing.UpdatedAt = DateTime.UtcNow;
            await fingerprintRepository.UpdateAsync(existing);
            logger.LogWarning("[EnrollFingerprint] Updated fingerprint record: User={UserName}, FingerIndex={Index}", 
                deviceUser.Name, fingerIndex);
        }
        else
        {
            var fingerprint = new FingerprintTemplate
            {
                Id = Guid.NewGuid(),
                EmployeeId = deviceUser.Id,
                FingerIndex = fingerIndex,
                Template = "enrolled-via-adms",
                TemplateSize = null,
                Quality = 1,
                Version = 10,
            };

            await fingerprintRepository.AddAsync(fingerprint);
            logger.LogWarning("[EnrollFingerprint] SAVED fingerprint: User={UserName}, FingerIndex={Index}, Id={Id}", 
                deviceUser.Name, fingerIndex, fingerprint.Id);
        }
    }

    private static string? ParseValue(string command, string key)
    {
        // Match KEY=VALUE where VALUE is terminated by tab, space, or end of string
        var match = Regex.Match(command, $@"{key}=([^\t\s]+)", RegexOptions.IgnoreCase);
        return match.Success ? match.Groups[1].Value : null;
    }
}
