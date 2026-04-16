using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Leaves.DeleteLeave;

public class DeleteLeaveHandler(
    IRepository<Leave> leaveRepository,
    IRepository<Employee> employeeRepository,
    IRepository<WorkSchedule> workScheduleRepository,
    IRepository<ShiftTemplate> shiftTemplateRepository,
    IRepository<ScheduleRegistration> scheduleRegistrationRepository
) : ICommandHandler<DeleteLeaveCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(DeleteLeaveCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var leave = await leaveRepository.GetSingleAsync(
                filter: l => l.Id == request.LeaveId && l.StoreId == request.StoreId,
                cancellationToken: cancellationToken);

            if (leave == null)
            {
                return AppResponse<bool>.Error("Không tìm thấy đơn nghỉ phép");
            }

            // Regular employees can only delete their own pending leaves
            // Managers/admins can delete any leave
            if (!request.IsManager)
            {
                if (leave.EmployeeUserId != request.UserId)
                {
                    return AppResponse<bool>.Error("Bạn không có quyền xóa đơn này");
                }
                if (leave.Status != LeaveStatus.Pending)
                {
                    return AppResponse<bool>.Error("Không thể xóa đơn đã được duyệt/từ chối/hủy");
                }
            }

            // If the leave was approved, rollback WorkSchedule changes before deleting
            if (leave.Status == LeaveStatus.Approved)
            {
                var employee = await employeeRepository.GetSingleAsync(
                    filter: e => e.ApplicationUserId == leave.EmployeeUserId && e.StoreId == request.StoreId,
                    cancellationToken: cancellationToken);

                // Fallback: try finding by Employee.Id directly
                if (employee == null)
                {
                    employee = await employeeRepository.GetSingleAsync(
                        filter: e => e.Id == leave.EmployeeUserId && e.StoreId == request.StoreId,
                        cancellationToken: cancellationToken);
                }

                if (employee != null)
                {
                    var shiftTemplates = new List<ShiftTemplate>();
                    foreach (var shiftId in leave.ShiftIds)
                    {
                        var st = await shiftTemplateRepository.GetSingleAsync(
                            filter: s => s.Id == shiftId,
                            cancellationToken: cancellationToken);
                        if (st != null) shiftTemplates.Add(st);
                    }

                    for (var date = leave.StartDate.Date; date <= leave.EndDate.Date; date = date.AddDays(1))
                    {
                        if (shiftTemplates.Count > 0)
                        {
                            foreach (var shiftTemplate in shiftTemplates)
                            {
                                var dayOffSchedules = await workScheduleRepository.GetAllAsync(
                                    ws => ws.EmployeeUserId == employee.ApplicationUserId
                                          && ws.Date.Date == date.Date
                                          && ws.ShiftId == shiftTemplate.Id
                                          && ws.IsDayOff
                                          && ws.StoreId == request.StoreId,
                                    cancellationToken: cancellationToken);

                                foreach (var ws in dayOffSchedules)
                                {
                                    ws.IsDayOff = false;
                                    ws.StartTime = shiftTemplate.StartTime;
                                    ws.EndTime = shiftTemplate.EndTime;
                                    ws.Note = null;
                                    ws.UpdatedAt = DateTime.Now;
                                    await workScheduleRepository.UpdateAsync(ws, cancellationToken);
                                }
                            }
                        }
                        else
                        {
                            var dayOffSchedules = await workScheduleRepository.GetAllAsync(
                                ws => ws.EmployeeUserId == employee.ApplicationUserId
                                      && ws.Date.Date == date.Date
                                      && ws.IsDayOff
                                      && ws.StoreId == request.StoreId,
                                cancellationToken: cancellationToken);

                            foreach (var ws in dayOffSchedules)
                            {
                                ws.IsDayOff = false;
                                ws.Note = null;
                                ws.UpdatedAt = DateTime.Now;
                                await workScheduleRepository.UpdateAsync(ws, cancellationToken);
                            }
                        }
                    }
                }

                // Remove replacement schedules
                if (leave.ReplacementEmployeeId.HasValue && leave.ShiftIds.Count > 0)
                {
                    var replacementEmployee = await employeeRepository.GetSingleAsync(
                        filter: e => e.Id == leave.ReplacementEmployeeId.Value && e.StoreId == request.StoreId,
                        cancellationToken: cancellationToken);

                    if (replacementEmployee != null)
                    {
                        for (var date = leave.StartDate.Date; date <= leave.EndDate.Date; date = date.AddDays(1))
                        {
                            foreach (var shiftId in leave.ShiftIds)
                            {
                                var replacementSchedules = await workScheduleRepository.GetAllAsync(
                                    ws => ws.EmployeeUserId == replacementEmployee.ApplicationUserId
                                          && ws.Date.Date == date.Date
                                          && ws.ShiftId == shiftId
                                          && ws.StoreId == request.StoreId
                                          && !ws.IsDayOff,
                                    cancellationToken: cancellationToken);

                                foreach (var ws in replacementSchedules)
                                {
                                    if (ws.Note != null && ws.Note.Contains("nghỉ phép"))
                                    {
                                        await workScheduleRepository.DeleteAsync(ws, cancellationToken);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Delete ScheduleRegistrations created for the replacement employee
            if (leave.ReplacementEmployeeId.HasValue && leave.ShiftIds.Count > 0)
            {
                for (var date = leave.StartDate.Date; date <= leave.EndDate.Date; date = date.AddDays(1))
                {
                    foreach (var shiftId in leave.ShiftIds)
                    {
                        var replacementRegs = await scheduleRegistrationRepository.GetAllAsync(
                            r => r.EmployeeUserId == leave.ReplacementEmployeeId.Value
                                 && r.Date.Date == date.Date
                                 && r.ShiftId == shiftId
                                 && r.StoreId == request.StoreId
                                 && r.Note != null && r.Note.Contains("nghỉ phép"),
                            cancellationToken: cancellationToken);

                        foreach (var reg in replacementRegs)
                        {
                            await scheduleRegistrationRepository.DeleteAsync(reg, cancellationToken);
                        }
                    }
                }
            }

            // Hard delete the leave record
            await leaveRepository.DeleteAsync(leave, cancellationToken);

            return AppResponse<bool>.Success(true);
        }
        catch (Exception ex)
        {
            return AppResponse<bool>.Error(ex.Message);
        }
    }
}
