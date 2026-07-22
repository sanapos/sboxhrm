using ZKTecoADMS.Application.DTOs.Devices;

namespace ZKTecoADMS.Application.Queries.Devices.GetDeviceInfo;

public class GetDeviceInfoHandler(
    IRepository<DeviceInfo> deviceInfoRepository
) : IQueryHandler<GetDeviceInfoQuery, AppResponse<DeviceInfoDto>>
{
    public async Task<AppResponse<DeviceInfoDto>> Handle(GetDeviceInfoQuery request, CancellationToken cancellationToken)
    {
        var info = await deviceInfoRepository.GetSingleAsync(
            di => di.DeviceId == request.Id,
            cancellationToken: cancellationToken);

        if (info == null)
            return AppResponse<DeviceInfoDto>.Fail("Không tìm thấy thông tin thiết bị");

        return AppResponse<DeviceInfoDto>.Success(new DeviceInfoDto(
            DeviceId: info.DeviceId.ToString(),
            FirmwareVersion: info.FirmwareVersion,
            EnrolledUserCount: info.EnrolledUserCount,
            FingerprintCount: info.FingerprintCount,
            AttendanceCount: info.AttendanceCount,
            DeviceIp: info.DeviceIp,
            FingerprintVersion: info.FingerprintVersion,
            FaceVersion: info.FaceVersion,
            FaceTemplateCount: info.FaceTemplateCount,
            DevSupportData: info.DevSupportData,
            Platform: info.Platform,
            PushVersion: info.PushVersion,
            DeviceModelName: info.DeviceModelName,
            OemVendor: info.OemVendor,
            EngineProfile: info.EngineProfile,
            SupportsUserQuery: info.SupportsUserQuery,
            SupportsAttendanceQuery: info.SupportsAttendanceQuery,
            SupportsEnrollFingerprint: info.SupportsEnrollFingerprint,
            SupportsFaceUpdate: info.SupportsFaceUpdate,
            SupportsDoorControl: info.SupportsDoorControl,
            PreferStampSync: info.PreferStampSync,
            CapabilityNotes: info.CapabilityNotes
        ));
    }
}