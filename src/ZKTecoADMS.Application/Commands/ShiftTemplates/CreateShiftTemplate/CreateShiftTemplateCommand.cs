using ZKTecoADMS.Application.DTOs.Shifts;

namespace ZKTecoADMS.Application.Commands.ShiftTemplates.CreateShiftTemplate;

public record CreateShiftTemplateCommand(
    Guid ManagerId,
    Guid StoreId,
    string Name,
    string? Code,
    TimeSpan StartTime,
    TimeSpan EndTime,
    int MaximumAllowedLateMinutes = 30,
    int MaximumAllowedEarlyLeaveMinutes = 30,
    int BreakTimeMinutes = 0,
    int EarlyCheckInMinutes = 30,
    int LateGraceMinutes = 5,
    int EarlyLeaveGraceMinutes = 5,
    int OvertimeMinutesThreshold = 30,
    string? ShiftType = null,
    string? Description = null,
    bool IsActive = true) : ICommand<AppResponse<ShiftTemplateDto>>;
