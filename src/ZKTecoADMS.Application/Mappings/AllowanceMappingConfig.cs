using ZKTecoADMS.Application.DTOs.Allowances;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Mappings;

public class AllowanceMappingConfig : IRegister
{
    public void Register(TypeAdapterConfig config)
    {
        // Allowance is a global setting, not per-employee
        config.NewConfig<Allowance, AllowanceDto>()
            .Map(dest => dest.Id, src => src.Id)
            .Map(dest => dest.Name, src => src.Name)
            .Map(dest => dest.Code, src => src.Code)
            .Map(dest => dest.Description, src => src.Description)
            .Map(dest => dest.Type, src => src.Type)
            .Map(dest => dest.Amount, src => src.Amount)
            .Map(dest => dest.Currency, src => src.Currency)
            .Map(dest => dest.IsTaxable, src => src.IsTaxable)
            .Map(dest => dest.IsInsuranceApplicable, src => src.IsInsuranceApplicable)
            .Map(dest => dest.IsActive, src => src.IsActive)
            .Map(dest => dest.CreatedAt, src => src.CreatedAt)
            .Map(dest => dest.UpdatedAt, src => src.UpdatedAt)
            .Ignore(dest => dest.EmployeeIds);

        config.NewConfig<CreateAllowanceDto, Allowance>()
            .Map(dest => dest.Name, src => src.Name)
            .Map(dest => dest.Code, src => src.Code)
            .Map(dest => dest.Description, src => src.Description)
            .Map(dest => dest.Type, src => src.Type)
            .Map(dest => dest.Amount, src => src.Amount)
            .Map(dest => dest.Currency, src => src.Currency)
            .Map(dest => dest.IsTaxable, src => src.IsTaxable)
            .Map(dest => dest.IsInsuranceApplicable, src => src.IsInsuranceApplicable)
            .Map(dest => dest.IsActive, _ => true);
    }
}
