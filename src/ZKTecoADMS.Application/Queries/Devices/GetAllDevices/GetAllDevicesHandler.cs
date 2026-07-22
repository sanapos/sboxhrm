using Mapster;
using ZKTecoADMS.Application.DTOs.Devices;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Application.Queries.Devices.GetAllDevices;

public class GetAllDevicesHandler(
    IRepository<Device> deviceRepository,
    IRepository<DeviceInfo> deviceInfoRepository
) : IQueryHandler<GetAllDevicesQuery, AppResponse<IEnumerable<DeviceDto>>>
{
    public async Task<AppResponse<IEnumerable<DeviceDto>>> Handle(GetAllDevicesQuery request, CancellationToken cancellationToken)
    {
        var results = await deviceRepository.GetAllAsync(
            filter: null,
            cancellationToken: cancellationToken
        );

        IEnumerable<Device> filtered = results;

        if (request.StoreId.HasValue)
        {
            filtered = filtered.Where(d => d.StoreId == request.StoreId.Value);
        }
        else if (!request.IsAdminRequest)
        {
            filtered = filtered.Where(d => d.ManagerId == request.UserId);
        }

        var list = filtered.ToList();
        var deviceIds = list.Select(d => d.Id).ToHashSet();
        var infos = await deviceInfoRepository.GetAllAsync(
            di => deviceIds.Contains(di.DeviceId),
            cancellationToken: cancellationToken);
        var infoByDevice = infos.ToDictionary(i => i.DeviceId);

        var dtos = list.Select(d =>
        {
            var dto = d.Adapt<DeviceDto>();
            if (infoByDevice.TryGetValue(d.Id, out var info))
            {
                dto.EngineProfile = info.EngineProfile;
                dto.Platform = info.Platform;
                dto.FirmwareVersion = info.FirmwareVersion;
                dto.SupportsUserQuery = info.SupportsUserQuery;
                dto.SupportsAttendanceQuery = info.SupportsAttendanceQuery;
                dto.SupportsEnrollFingerprint = info.SupportsEnrollFingerprint;
                dto.SupportsFaceUpdate = info.SupportsFaceUpdate;
                dto.SupportsDoorControl = info.SupportsDoorControl;
                dto.PreferStampSync = info.PreferStampSync;
                dto.AllowEnrollFingerprintUi = info.SupportsEnrollFingerprint != false;
                dto.AllowEnrollFaceUi = info.SupportsFaceUpdate == true;
                dto.AllowDoorControlUi = info.SupportsDoorControl != false;
                dto.CapabilityNotes = info.CapabilityNotes;
            }
            return dto;
        });

        return AppResponse<IEnumerable<DeviceDto>>.Success(dtos);
    }
}
