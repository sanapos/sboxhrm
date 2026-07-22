using ZKTecoADMS.Application.DTOs.Shifts;

namespace ZKTecoADMS.Application.Commands.ShiftTemplates.UpdateShiftTemplate;

public record UpdateShiftTemplateCommand(
    Guid Id,
    string Name,
    string? Code,
    TimeSpan StartTime,
    TimeSpan EndTime,
    int MaximumAllowedLateMinutes,
    int MaximumAllowedEarlyLeaveMinutes,
    int BreakTimeMinutes,
    TimeSpan? LunchBreakStartTime,
    TimeSpan? LunchBreakEndTime,
    int EarlyCheckInMinutes,
    int LateGraceMinutes,
    int EarlyLeaveGraceMinutes,
    int OvertimeMinutesThreshold,
    int EarlyOvertimeMinutesThreshold,
    string? ShiftType,
    string? Description,
    bool IsActive) : ICommand<AppResponse<ShiftTemplateDto>>;
