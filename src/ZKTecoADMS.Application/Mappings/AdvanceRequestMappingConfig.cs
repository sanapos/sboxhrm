using ZKTecoADMS.Application.DTOs.AdvanceRequests;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Mappings;

public class AdvanceRequestMappingConfig : IRegister
{
    public void Register(TypeAdapterConfig config)
    {
        config.NewConfig<AdvanceRequest, AdvanceRequestDto>()
            .Map(dest => dest.Id, src => src.Id)
            .Map(dest => dest.EmployeeUserId, src => src.EmployeeUserId)
            .Map(dest => dest.EmployeeId, src => src.EmployeeId)
            .Map(dest => dest.EmployeeName, src => 
                src.Employee != null 
                    ? $"{src.Employee.LastName} {src.Employee.FirstName}".Trim()
                    : src.EmployeeUser != null 
                        ? $"{src.EmployeeUser.LastName} {src.EmployeeUser.FirstName}".Trim() 
                        : "")
            .Map(dest => dest.EmployeeCode, src => 
                src.Employee != null 
                    ? src.Employee.EmployeeCode
                    : src.EmployeeUser != null && src.EmployeeUser.Employee != null 
                        ? src.EmployeeUser.Employee.EmployeeCode 
                        : "")
            .Map(dest => dest.Amount, src => src.Amount)
            .Map(dest => dest.Reason, src => src.Reason)
            .Map(dest => dest.RequestDate, src => src.RequestDate)
            .Map(dest => dest.Status, src => src.Status)
            .Map(dest => dest.ApprovedById, src => src.ApprovedById)
            .Map(dest => dest.ApprovedByName, src => src.ApprovedBy != null 
                ? $"{src.ApprovedBy.LastName} {src.ApprovedBy.FirstName}".Trim() 
                : null)
            .Map(dest => dest.ApprovedDate, src => src.ApprovedDate)
            .Map(dest => dest.RejectionReason, src => src.RejectionReason)
            .Map(dest => dest.Note, src => src.Note)
            .Map(dest => dest.IsPaid, src => src.IsPaid)
            .Map(dest => dest.ForMonth, src => src.ForMonth)
            .Map(dest => dest.ForYear, src => src.ForYear)
            .Map(dest => dest.CreatedAt, src => src.CreatedAt)
            .Map(dest => dest.UpdatedAt, src => src.UpdatedAt);

        config.NewConfig<CreateAdvanceRequestDto, AdvanceRequest>()
            .Map(dest => dest.Amount, src => src.Amount)
            .Map(dest => dest.Reason, src => src.Reason)
            .Map(dest => dest.Note, src => src.Note)
            .Map(dest => dest.RequestDate, _ => DateTime.UtcNow)
            .Map(dest => dest.Status, _ => Domain.Enums.AdvanceRequestStatus.Pending);
    }
}
