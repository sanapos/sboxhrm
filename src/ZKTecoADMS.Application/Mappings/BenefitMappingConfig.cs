using Mapster;
using ZKTecoADMS.Application.DTOs.Benefits;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Mappings;

public class BenefitMappingConfig : IRegister
{
    public void Register(TypeAdapterConfig config)
    {
        config.NewConfig<Benefit, BenefitDto>()
            .Map(dest => dest.StandardWorkMode, src => src.StandardWorkMode.ToString());
    }
}
