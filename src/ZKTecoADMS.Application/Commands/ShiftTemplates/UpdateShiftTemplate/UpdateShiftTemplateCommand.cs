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
    int EarlyCheckInMinutes,
    int LateGraceMinutes,
    int EarlyLeaveGraceMinutes,
    int OvertimeMinutesThreshold,
    string? ShiftType,
    string? Description,
    bool IsActive) : ICommand<AppResponse<ShiftTemplateDto>>;
