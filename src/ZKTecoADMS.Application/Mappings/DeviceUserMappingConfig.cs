using Mapster;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.DeviceUsers;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Mappings;

public class DeviceUserMappingConfig : IRegister
{
    public void Register(TypeAdapterConfig config)
    {
        config.NewConfig<DeviceUser, DeviceUserDto>()
            .Map(dest => dest.DeviceName, src => src.Device != null ? src.Device.DeviceName : null)
            .Map(dest => dest.FingerprintCount, src => src.FingerprintTemplates != null ? src.FingerprintTemplates.Count : 0)
            .Map(dest => dest.CopyableFingerprintCount, src =>
                src.FingerprintTemplates == null
                    ? 0
                    : src.FingerprintTemplates.Count(f => DeviceUserPins.IsCopyableTemplate(f.Template)))
            .Map(dest => dest.FaceCount, src => src.FaceTemplates != null ? src.FaceTemplates.Count : 0);
    }
}
