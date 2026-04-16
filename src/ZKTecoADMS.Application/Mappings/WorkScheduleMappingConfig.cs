using ZKTecoADMS.Application.DTOs.WorkSchedules;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Mappings;

public class WorkScheduleMappingConfig : IRegister
{
    public void Register(TypeAdapterConfig config)
    {
        // Work Schedule
        config.NewConfig<WorkSchedule, WorkScheduleDto>()
            .Map(dest => dest.Id, src => src.Id)
            .Map(dest => dest.EmployeeUserId, src => src.EmployeeUserId)
            .Map(dest => dest.EmployeeName, src => src.Employee != null 
                ? $"{src.Employee.FirstName} {src.Employee.LastName}".Trim() 
                : "")
            .Map(dest => dest.EmployeeCode, src => src.Employee != null 
                ? src.Employee.EmployeeCode 
                : "")
            .Map(dest => dest.ShiftId, src => src.ShiftId)
            .Map(dest => dest.ShiftName, src => src.Shift != null ? src.Shift.Name ?? src.Shift.Id.ToString() : "")
            .Map(dest => dest.ShiftStartTime, src => src.Shift != null ? src.Shift.StartTime : TimeSpan.Zero)
            .Map(dest => dest.ShiftEndTime, src => src.Shift != null ? src.Shift.EndTime : TimeSpan.Zero)
            .Map(dest => dest.Date, src => src.Date)
            .Map(dest => dest.StartTime, src => src.StartTime)
            .Map(dest => dest.EndTime, src => src.EndTime)
            .Map(dest => dest.IsDayOff, src => src.IsDayOff)
            .Map(dest => dest.Note, src => src.Note)
            .Map(dest => dest.AssignedById, src => src.AssignedById)
            .Map(dest => dest.CreatedAt, src => src.CreatedAt)
            .Map(dest => dest.UpdatedAt, src => src.UpdatedAt);

        config.NewConfig<CreateWorkScheduleDto, WorkSchedule>()
            .Map(dest => dest.EmployeeUserId, src => src.EmployeeUserId)
            .Map(dest => dest.ShiftId, src => src.ShiftId)
            .Map(dest => dest.Date, src => src.Date)
            .Map(dest => dest.StartTime, src => src.StartTime)
            .Map(dest => dest.EndTime, src => src.EndTime)
            .Map(dest => dest.IsDayOff, src => src.IsDayOff)
            .Map(dest => dest.Note, src => src.Note);

        // Schedule Registration
        config.NewConfig<ScheduleRegistration, ScheduleRegistrationDto>()
            .Map(dest => dest.Id, src => src.Id)
            .Map(dest => dest.EmployeeUserId, src => src.EmployeeUserId)
            .Map(dest => dest.EmployeeName, src => src.Employee != null 
                ? $"{src.Employee.FirstName} {src.Employee.LastName}".Trim() 
                : "")
            .Map(dest => dest.EmployeeCode, src => src.Employee != null 
                ? src.Employee.EmployeeCode 
                : "")
            .Map(dest => dest.Date, src => src.Date)
            .Map(dest => dest.ShiftId, src => src.ShiftId)
            .Map(dest => dest.ShiftName, src => src.Shift != null ? src.Shift.Name ?? src.Shift.Id.ToString() : "")
            .Map(dest => dest.IsDayOff, src => src.IsDayOff)
            .Map(dest => dest.Note, src => src.Note)
            .Map(dest => dest.Status, src => src.Status)
            .Map(dest => dest.ApprovedById, src => src.ApprovedById)
            .Map(dest => dest.ApprovedByName, src => src.ApprovedBy != null 
                ? $"{src.ApprovedBy.LastName} {src.ApprovedBy.FirstName}".Trim() 
                : null)
            .Map(dest => dest.ApprovedDate, src => src.ApprovedDate)
            .Map(dest => dest.RejectionReason, src => src.RejectionReason)
            .Map(dest => dest.CreatedAt, src => src.CreatedAt)
            .Map(dest => dest.UpdatedAt, src => src.UpdatedAt);

        config.NewConfig<CreateScheduleRegistrationDto, ScheduleRegistration>()
            .Map(dest => dest.EmployeeUserId, src => src.EmployeeUserId)
            .Map(dest => dest.ShiftId, src => src.ShiftId)
            .Map(dest => dest.Date, src => src.Date)
            .Map(dest => dest.IsDayOff, src => src.IsDayOff)
            .Map(dest => dest.Note, src => src.Note)
            .Map(dest => dest.Status, _ => Domain.Enums.ScheduleRegistrationStatus.Pending);
    }
}
