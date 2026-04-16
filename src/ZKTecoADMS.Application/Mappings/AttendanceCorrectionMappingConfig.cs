using ZKTecoADMS.Application.DTOs.AttendanceCorrections;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Mappings;

public class AttendanceCorrectionMappingConfig : IRegister
{
    public void Register(TypeAdapterConfig config)
    {
        config.NewConfig<AttendanceCorrectionRequest, AttendanceCorrectionRequestDto>()
            .Map(dest => dest.Id, src => src.Id)
            .Map(dest => dest.EmployeeUserId, src => src.EmployeeUserId)
            .Map(dest => dest.EmployeeName, src => !string.IsNullOrEmpty(src.EmployeeName) 
                ? src.EmployeeName 
                : src.EmployeeUser != null 
                    ? $"{src.EmployeeUser.LastName} {src.EmployeeUser.FirstName}".Trim() 
                    : "")
            .Map(dest => dest.EmployeeCode, src => !string.IsNullOrEmpty(src.EmployeeCode) 
                ? src.EmployeeCode 
                : src.EmployeeUser != null && src.EmployeeUser.Employee != null 
                    ? src.EmployeeUser.Employee.EmployeeCode 
                    : "")
            .Map(dest => dest.AttendanceId, src => src.AttendanceId)
            .Map(dest => dest.Action, src => src.Action)
            .Map(dest => dest.OldDate, src => src.OldDate)
            .Map(dest => dest.OldTime, src => src.OldTime)
            .Map(dest => dest.OldDevice, src => src.OldDevice)
            .Map(dest => dest.OldType, src => src.OldType)
            .Map(dest => dest.NewDate, src => src.NewDate)
            .Map(dest => dest.NewTime, src => src.NewTime)
            .Map(dest => dest.Reason, src => src.Reason)
            .Map(dest => dest.Status, src => src.Status)
            .Map(dest => dest.ApprovedById, src => src.ApprovedById)
            .Map(dest => dest.ApprovedByName, src => src.ApprovedBy != null 
                ? $"{src.ApprovedBy.LastName} {src.ApprovedBy.FirstName}".Trim() 
                : null)
            .Map(dest => dest.ApprovedDate, src => src.ApprovedDate)
            .Map(dest => dest.ApproverNote, src => src.ApproverNote)
            .Map(dest => dest.CreatedAt, src => src.CreatedAt)
            .Map(dest => dest.UpdatedAt, src => src.UpdatedAt);

        config.NewConfig<CreateAttendanceCorrectionDto, AttendanceCorrectionRequest>()
            .Map(dest => dest.AttendanceId, src => src.AttendanceId)
            .Map(dest => dest.Action, src => src.Action)
            .Map(dest => dest.OldDate, src => src.OldDate)
            .Map(dest => dest.OldTime, src => src.OldTime)
            .Map(dest => dest.NewDate, src => src.NewDate)
            .Map(dest => dest.NewTime, src => src.NewTime)
            .Map(dest => dest.Reason, src => src.Reason)
            .Map(dest => dest.Status, _ => Domain.Enums.CorrectionStatus.Pending);
    }
}
