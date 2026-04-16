using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.IClock.DeviceCmdCommand.Strategies;

/// <summary>
/// Strategy for handling DeleteFace command responses.
/// Khi máy xóa khuôn mặt thành công, xóa record từ database.
/// </summary>
[DeviceCommandStrategy(DeviceCommandTypes.DeleteFace)]
public class DeleteFaceStrategy(
    IRepository<FaceTemplate> faceRepository,
    ILogger<DeleteFaceStrategy> logger
) : IDeviceCommandStrategy
{
    public async Task ExecuteAsync(Device device, Guid objectRefId, ClockCommandResponse response, CancellationToken cancellationToken)
    {
        logger.LogInformation("[DeleteFace] Processing for ObjectRefId={Id}, Success={Success}, ReturnCode={Code}", 
            objectRefId, response.IsSuccess, response.Return);

        if (!response.IsSuccess)
        {
            logger.LogWarning("[DeleteFace] Failed with return code {Code}", response.Return);
            return;
        }

        // objectRefId có thể là FaceTemplate.Id hoặc DeviceUser.Id
        var face = await faceRepository.GetByIdAsync(objectRefId, cancellationToken: cancellationToken);
        if (face != null)
        {
            await faceRepository.DeleteAsync(face, cancellationToken);
            logger.LogInformation("[DeleteFace] Deleted face {FaceId}", face.Id);
        }
        else
        {
            // Có thể là xóa tất cả face của user
            var allFaces = await faceRepository.GetAllAsync(
                f => f.EmployeeId == objectRefId, 
                cancellationToken: cancellationToken);
            
            foreach (var f in allFaces)
            {
                await faceRepository.DeleteAsync(f, cancellationToken);
            }
            
            logger.LogInformation("[DeleteFace] Deleted all faces for user {UserId}", objectRefId);
        }
    }
}
