using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Leaves.UndoLeaveApproval;

public class UndoLeaveApprovalHandler(
    IRepository<Leave> leaveRepository,
    IRepository<Employee> employeeRepository,
    IRepository<WorkSchedule> workScheduleRepository,
    IRepository<ShiftTemplate> shiftTemplateRepository,
    IRepository<ScheduleRegistration> scheduleRegistrationRepository,
    IRepository<LeaveApprovalRecord> approvalRecordRepository,
    ISystemNotificationService notificationService
) : ICommandHandler<UndoLeaveApprovalCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(UndoLeaveApprovalCommand request, CancellationToken cancellationToken)
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

            // Only allow undo for Approved or Rejected leaves
            if (leave.Status != LeaveStatus.Approved && leave.Status != LeaveStatus.Rejected)
            {
                return AppResponse<bool>.Error("Chỉ có thể hoàn duyệt đơn đã duyệt hoặc đã từ chối");
            }

            var wasApproved = leave.Status == LeaveStatus.Approved;

            // Set back to Pending
            leave.Status = LeaveStatus.Pending;
            leave.CurrentApprovalStep = 0;
            leave.UpdatedAt = DateTime.Now;
            await leaveRepository.UpdateAsync(leave, cancellationToken);

            // Reset all approval records to Pending
            var approvalRecords = await approvalRecordRepository.GetAllAsync(
                filter: r => r.LeaveId == leave.Id,
                cancellationToken: cancellationToken);
            foreach (var record in approvalRecords)
            {
                record.Status = ApprovalStatus.Pending;
                record.ActualUserId = null;
                record.ActualUserName = null;
                record.ActionDate = null;
                record.Note = null;
                await approvalRecordRepository.UpdateAsync(record, cancellationToken);
            }

            // If the leave was approved, rollback WorkSchedule changes
            if (wasApproved)
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
                    // Load shift templates
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
                                // Revert employee's day-off WorkSchedules back to working
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
                            // No shift specified - revert all day-off schedules for this date
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

                // If replacement employee was specified, remove their replacement schedules
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
                                // Delete replacement WorkSchedules
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

                                // Revert ScheduleRegistrations for replacement employee back to Pending
                                var approvedRegs = await scheduleRegistrationRepository.GetAllAsync(
                                    r => r.EmployeeUserId == replacementEmployee.ApplicationUserId
                                         && r.Date.Date == date.Date
                                         && r.ShiftId == shiftId
                                         && r.StoreId == request.StoreId
                                         && r.Status == ScheduleRegistrationStatus.Approved
                                         && r.Note != null && r.Note.Contains("nghỉ phép"),
                                    cancellationToken: cancellationToken);

                                foreach (var reg in approvedRegs)
                                {
                                    reg.Status = ScheduleRegistrationStatus.Pending;
                                    reg.ApprovedById = null;
                                    reg.ApprovedDate = null;
                                    reg.UpdatedAt = DateTime.Now;
                                    await scheduleRegistrationRepository.UpdateAsync(reg, cancellationToken);
                                }
                            }
                        }
                    }
                }
            }

            try
            {
                await notificationService.CreateAndSendAsync(
                    leave.EmployeeUserId, NotificationType.Warning,
                    "Đơn nghỉ phép hoàn duyệt",
                    $"Đơn nghỉ phép từ {leave.StartDate:dd/MM/yyyy} đến {leave.EndDate:dd/MM/yyyy} đã được hoàn duyệt về trạng thái chờ",
                    relatedEntityId: leave.Id, relatedEntityType: "Leave",
                    fromUserId: request.UserId, categoryCode: "approval", storeId: request.StoreId);
            }
            catch { /* Notification failure should not affect main operation */ }

            return AppResponse<bool>.Success(true);
        }
        catch (Exception ex)
        {
            return AppResponse<bool>.Error(ex.Message);
        }
    }
}
