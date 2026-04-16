using FluentValidation;
using ZKTecoADMS.Application.DTOs;
using ZKTecoADMS.Application.DTOs.Shifts;

namespace ZKTecoADMS.Application.Commands.Shifts.CreateShift;

public record CreateShiftCommand(
    Guid StoreId,
    Guid EmployeeUserId,
    List<WorkingDay> WorkingDays,
    int MaximumAllowedLateMinutes = 30,
    int MaximumAllowedEarlyLeaveMinutes = 30,
    int BreakTimeMinutes = 60,
    string? Description = null,
    bool IsManager = false) : ICommand<AppResponse<ShiftDto>>;
