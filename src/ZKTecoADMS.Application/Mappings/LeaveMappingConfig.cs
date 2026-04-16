using Mapster;
using ZKTecoADMS.Application.DTOs.Leaves;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Mappings;

public class LeaveMappingConfig : IRegister
{
    public void Register(TypeAdapterConfig config)
    {
        config.NewConfig<Leave, LeaveDto>()
            .Map(dest => dest.EmployeeName, src => 
                src.EmployeeUser != null 
                    ? $"{src.EmployeeUser.LastName} {src.EmployeeUser.FirstName}" 
                    : string.Empty)
            .Map(dest => dest.ReplacementEmployeeName, src =>
                src.ReplacementEmployee != null
                    ? $"{src.ReplacementEmployee.LastName} {src.ReplacementEmployee.FirstName}"
                    : null)
            .Map(dest => dest.ReplacementEmployeeId, src => src.ReplacementEmployeeId);
    }
}
