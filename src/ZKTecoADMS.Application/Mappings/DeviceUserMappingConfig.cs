using Mapster;
using ZKTecoADMS.Application.DTOs.DeviceUsers;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Mappings;

public class DeviceUserMappingConfig : IRegister
{
    public void Register(TypeAdapterConfig config)
    {
        config.NewConfig<DeviceUser, DeviceUserDto>()
            .Map(dest => dest.DeviceName, src => src.Device != null ? src.Device.DeviceName : null)
            .Map(dest => dest.FingerprintCount, src => src.FingerprintTemplates != null ? src.FingerprintTemplates.Count : 0);
    }
}
