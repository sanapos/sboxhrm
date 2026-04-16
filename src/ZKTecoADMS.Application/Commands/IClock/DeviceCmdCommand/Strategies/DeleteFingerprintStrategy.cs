using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.IClock.DeviceCmdCommand.Strategies;

/// <summary>
/// Strategy for handling DeleteFingerprint command responses
/// Khi máy xóa vân tay thành công, xóa record từ database
/// </summary>
[DeviceCommandStrategy(DeviceCommandTypes.DeleteFingerprint)]
public class DeleteFingerprintStrategy(
    IRepository<FingerprintTemplate> fingerprintRepository,
    ILogger<DeleteFingerprintStrategy> logger
) : IDeviceCommandStrategy
{
    public async Task ExecuteAsync(Device device, Guid objectRefId, ClockCommandResponse response, CancellationToken cancellationToken)
    {
        logger.LogInformation("[DeleteFingerprint] Processing for ObjectRefId={Id}, Success={Success}, ReturnCode={Code}", 
            objectRefId, response.IsSuccess, response.Return);

        if (!response.IsSuccess)
        {
            logger.LogWarning("[DeleteFingerprint] Failed with return code {Code}", response.Return);
            return;
        }

        // objectRefId là FingerprintTemplate.Id hoặc DeviceUser.Id tùy implementation
        // Nếu là DeviceUser.Id, xóa tất cả fingerprint của user đó
        // Nếu là FingerprintTemplate.Id, xóa fingerprint cụ thể
        
        var fingerprint = await fingerprintRepository.GetByIdAsync(objectRefId, cancellationToken: cancellationToken);
        if (fingerprint != null)
        {
            await fingerprintRepository.DeleteAsync(fingerprint, cancellationToken);
            logger.LogInformation("[DeleteFingerprint] Deleted fingerprint {FingerprintId}", fingerprint.Id);
        }
        else
        {
            // Có thể là xóa tất cả fingerprint của user
            var allFingerprints = await fingerprintRepository.GetAllAsync(
                f => f.EmployeeId == objectRefId, 
                cancellationToken: cancellationToken);
            
            foreach (var fp in allFingerprints)
            {
                await fingerprintRepository.DeleteAsync(fp, cancellationToken);
            }
            
            logger.LogInformation("[DeleteFingerprint] Deleted all fingerprints for user {UserId}", objectRefId);
        }
    }
}
