using System.Text.RegularExpressions;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.IClock.DeviceCmdCommand.Strategies;

/// <summary>
/// Strategy for handling EnrollFace command responses.
/// 
/// Tương tự EnrollFingerprintStrategy: khi device xác nhận đăng ký khuôn mặt thành công,
/// lưu FaceTemplate record vào DB.
/// - Parse PIN từ command gốc
/// - Template data = null (device không upload template qua ADMS enrollment)
/// - Dữ liệu face template thực tế sẽ được sync qua CHECK BIODATA
/// </summary>
[DeviceCommandStrategy(DeviceCommandTypes.EnrollFace)]
public class EnrollFaceStrategy(
    IRepository<FaceTemplate> faceRepository,
    IRepository<DeviceUser> deviceUserRepository,
    IRepository<DeviceCommand> deviceCommandRepository,
    ILogger<EnrollFaceStrategy> logger
) : IDeviceCommandStrategy
{
    public async Task ExecuteAsync(Device device, Guid objectRefId, ClockCommandResponse response, CancellationToken cancellationToken)
    {
        logger.LogWarning("[EnrollFace] Processing for DeviceId={DeviceId}, Success={Success}, ReturnCode={Code}", 
            device.Id, response.IsSuccess, response.Return);

        if (!response.IsSuccess)
        {
            logger.LogWarning("[EnrollFace] Failed with return code {Code}", response.Return);
            return;
        }

        logger.LogWarning("[EnrollFace] Enrollment completed successfully on device {DeviceId}", device.Id);

        // Tìm lệnh gốc từ CommandId để lấy PIN
        var originalCommand = await deviceCommandRepository.GetSingleAsync(
            c => c.CommandId == response.CommandId);
        
        if (originalCommand == null)
        {
            logger.LogError("[EnrollFace] Original command not found for CommandId={CommandId}", response.CommandId);
            return;
        }

        logger.LogWarning("[EnrollFace] Original command: {Command}", originalCommand.Command);

        // Parse PIN từ command string: "ENROLL_FP PIN=xxx\tBIODATAFLAG=1\tFACEID=50"
        var pin = ParsePinFromCommand(originalCommand.Command);
        
        if (string.IsNullOrEmpty(pin))
        {
            logger.LogError("[EnrollFace] Could not parse PIN from command: {Command}", originalCommand.Command);
            return;
        }

        logger.LogWarning("[EnrollFace] Parsed: PIN={Pin}", pin);

        // Tìm DeviceUser theo PIN và DeviceId
        var deviceUser = await deviceUserRepository.GetSingleAsync(
            u => u.Pin == pin && u.DeviceId == device.Id);

        if (deviceUser == null)
        {
            logger.LogError("[EnrollFace] DeviceUser not found for PIN={Pin}, DeviceId={DeviceId}", pin, device.Id);
            return;
        }

        logger.LogWarning("[EnrollFace] Found DeviceUser: Id={UserId}, Name={Name}", deviceUser.Id, deviceUser.Name);

        // Kiểm tra xem đã có face template chưa (FaceIndex=50 cho visible light face)
        var existingFace = await faceRepository.GetSingleAsync(
            f => f.EmployeeId == deviceUser.Id && f.FaceIndex == 50);

        if (existingFace != null)
        {
            // Cập nhật - đánh dấu lại face đã đăng ký (có thể đăng ký lại)
            existingFace.UpdatedAt = DateTime.UtcNow;
            existingFace.Version = 50;
            await faceRepository.UpdateAsync(existingFace);
            logger.LogWarning("[EnrollFace] Updated existing face: User={Name}", deviceUser.Name);
        }
        else
        {
            // Tạo mới face template record
            var faceTemplate = new FaceTemplate
            {
                Id = Guid.NewGuid(),
                EmployeeId = deviceUser.Id,
                FaceIndex = 50, // Visible light face index
                Template = "enrolled-via-adms", // ADMS enrollment không upload template data
                TemplateSize = null,
                PhotoData = null,
                Version = 50,
                CreatedAt = DateTime.UtcNow
            };

            await faceRepository.AddAsync(faceTemplate, cancellationToken);
            logger.LogWarning("[EnrollFace] Created face record: User={Name}, FaceId={Id}", 
                deviceUser.Name, faceTemplate.Id);
        }
    }

    /// <summary>
    /// Parse PIN from enrollment command.
    /// Format: "ENROLL_FP PIN=xxx\tBIODATAFLAG=1\tFACEID=50"
    /// </summary>
    private static string? ParsePinFromCommand(string command)
    {
        var parts = Regex.Split(command, @"[\s\t]+");
        
        foreach (var part in parts)
        {
            var kv = part.Split('=', 2);
            if (kv.Length != 2) continue;

            var key = kv[0].Trim().ToUpperInvariant();
            if (key == "PIN")
            {
                return kv[1].Trim();
            }
        }

        return null;
    }
}
