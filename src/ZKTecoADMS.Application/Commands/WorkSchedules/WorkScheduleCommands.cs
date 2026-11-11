using Microsoft.AspNetCore.Identity;
using ZKTecoADMS.Application.DTOs.WorkSchedules;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Notifications;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.WorkSchedules;

// Create Work Schedule Command
public record CreateWorkScheduleCommand(
    Guid StoreId,
    Guid EmployeeUserId,
    Guid? ShiftId,
    DateTime Date,
    TimeSpan? StartTime,
    TimeSpan? EndTime,
    bool IsDayOff,
    string? Note) : ICommand<AppResponse<WorkScheduleDto>>;

public class CreateWorkScheduleHandler(
    IRepository<WorkSchedule> workScheduleRepository,
    IRepository<Employee> employeeRepository,
    IRepository<ShiftTemplate> shiftRepository,
    ISystemNotificationService notificationService,
    IAttendanceService attendanceService
) : ICommandHandler<CreateWorkScheduleCommand, AppResponse<WorkScheduleDto>>
{
    public async Task<AppResponse<WorkScheduleDto>> Handle(CreateWorkScheduleCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var employee = await employeeRepository.GetSingleAsync(
                filter: e => (e.ApplicationUserId == request.EmployeeUserId || e.Id == request.EmployeeUserId) && e.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            if (employee == null)
            {
                return AppResponse<WorkScheduleDto>.Error("Employee not found");
            }

            if (request.ShiftId.HasValue)
            {
                var shift = await shiftRepository.GetSingleAsync(
                    filter: s => s.Id == request.ShiftId.Value && s.StoreId == request.StoreId,
                    cancellationToken: cancellationToken);
                if (shift == null)
                {
                    return AppResponse<WorkScheduleDto>.Error("Shift not found");
                }
            }

            var existingSchedules = await workScheduleRepository.GetAllAsync(
                ws => ws.EmployeeUserId == employee.Id && ws.Date.Date == request.Date.Date && ws.StoreId == request.StoreId,
                cancellationToken: cancellationToken);

            var createError = WorkScheduleDuplicateHelper.Validate(
                existingSchedules.Where(e => e.Date.Date == request.Date.Date), request.ShiftId, request.IsDayOff);
            if (createError != null)
                return AppResponse<WorkScheduleDto>.Error(createError);

            var workSchedule = new WorkSchedule
            {
                StoreId = request.StoreId,
                EmployeeUserId = employee.Id,
                ShiftId = request.ShiftId,
                Date = request.Date.Date,
                StartTime = request.StartTime,
                EndTime = request.EndTime,
                IsDayOff = request.IsDayOff,
                Note = request.Note
            };

            var created = await workScheduleRepository.AddAsync(workSchedule, cancellationToken);
            await SchedulePenaltyRecalc.RunAsync(attendanceService, request.StoreId,
                [(employee.Id, workSchedule.Date)], cancellationToken);
            var result = await workScheduleRepository.GetSingleAsync(
                filter: w => w.Id == created.Id && w.StoreId == request.StoreId,
                includeProperties: [nameof(WorkSchedule.Employee), nameof(WorkSchedule.Shift)], 
                cancellationToken: cancellationToken);
            
            try
            {
                // «Lịch mới ngày 12/11» / «Ca Sáng 07:00–11:00»
                var day = ScheduleNotifyText.Day(request.Date);
                var slot = ScheduleNotifyText.Slot(result?.Shift, request.StartTime, request.EndTime, request.IsDayOff);
                if (employee.ApplicationUserId.HasValue)
                {
                    await notificationService.CreateAndSendAsync(
                        employee.ApplicationUserId.Value, NotificationType.Info,
                        $"Lịch mới ngày {day}",
                        slot,
                        relatedEntityId: created.Id, relatedEntityType: "WorkSchedule",
                        categoryCode: "shift", storeId: request.StoreId);
                }
                else
                {
                    await notificationService.NotifyEmployeesWithoutAccountAsync(request.StoreId, [employee.Id],
                        "Lịch làm việc mới", $"Ngày {day}: {slot}", "attendance");
                }
            }
            catch { /* Notification failure should not affect main operation */ }

            return AppResponse<WorkScheduleDto>.Success(result!.Adapt<WorkScheduleDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<WorkScheduleDto>.Error(ex.Message);
        }
    }
}

// Bulk Create Work Schedules Command
public record BulkCreateWorkSchedulesCommand(
    Guid StoreId,
    List<Guid> EmployeeUserIds,
    Guid? ShiftId,
    DateTime StartDate,
    DateTime EndDate,
    List<DayOfWeek> WorkDays) : ICommand<AppResponse<List<WorkScheduleDto>>>;

public class BulkCreateWorkSchedulesHandler(
    IRepository<WorkSchedule> workScheduleRepository,
    IRepository<Employee> employeeRepository,
    IRepository<ShiftTemplate> shiftRepository,
    ISystemNotificationService notificationService,
    IAttendanceService attendanceService
) : ICommandHandler<BulkCreateWorkSchedulesCommand, AppResponse<List<WorkScheduleDto>>>
{
    public async Task<AppResponse<List<WorkScheduleDto>>> Handle(BulkCreateWorkSchedulesCommand request, CancellationToken cancellationToken)
    {
        try
        {
            ShiftTemplate? shift = null;
            if (request.ShiftId.HasValue)
            {
                shift = await shiftRepository.GetSingleAsync(
                    filter: s => s.Id == request.ShiftId.Value && s.StoreId == request.StoreId,
                    cancellationToken: cancellationToken);
                if (shift == null)
                {
                    return AppResponse<List<WorkScheduleDto>>.Error("Shift not found");
                }
            }

            var schedulesToCreate = new List<WorkSchedule>();

            foreach (var userId in request.EmployeeUserIds)
            {
                var employee = await employeeRepository.GetSingleAsync(
                    filter: e => (e.ApplicationUserId == userId || e.Id == userId) && e.StoreId == request.StoreId,
                    cancellationToken: cancellationToken);
                if (employee == null) continue;

                // Batch check existing schedules for this employee in the date range
                var existingSchedules = await workScheduleRepository.GetAllAsync(
                    ws => ws.EmployeeUserId == employee.Id 
                          && ws.Date >= request.StartDate.Date 
                          && ws.Date <= request.EndDate.Date 
                          && ws.StoreId == request.StoreId,
                    cancellationToken: cancellationToken);
                var existingKeys = existingSchedules
                    .Select(ws => (ws.Date.Date, ws.ShiftId))
                    .ToHashSet();
                // Ngày đã đánh dấu nghỉ trên lịch → không xếp thêm ca (tránh vừa nghỉ vừa có ca).
                var dayOffDates = existingSchedules
                    .Where(ws => ws.IsDayOff)
                    .Select(ws => ws.Date.Date)
                    .ToHashSet();

                for (var date = request.StartDate.Date; date <= request.EndDate.Date; date = date.AddDays(1))
                {
                    if (!request.WorkDays.Contains(date.DayOfWeek)) continue;
                    if (dayOffDates.Contains(date)) continue;
                    if (existingKeys.Contains((date, request.ShiftId))) continue;

                    schedulesToCreate.Add(new WorkSchedule
                    {
                        StoreId = request.StoreId,
                        EmployeeUserId = employee.Id,
                        ShiftId = request.ShiftId,
                        Date = date,
                        IsDayOff = false
                    });
                }
            }

            // Batch insert all schedules in one DB roundtrip
            if (schedulesToCreate.Count > 0)
            {
                await workScheduleRepository.AddRangeAsync(schedulesToCreate, cancellationToken);
                await SchedulePenaltyRecalc.RunAsync(attendanceService, request.StoreId,
                    schedulesToCreate.Select(ws => (ws.EmployeeUserId, ws.Date)), cancellationToken);
            }

            // Reload all created schedules with includes
            var createdIds = schedulesToCreate.Select(s => s.Id).ToList();
            var results = await workScheduleRepository.GetAllAsync(
                filter: ws => createdIds.Contains(ws.Id) && ws.StoreId == request.StoreId,
                includeProperties: [nameof(WorkSchedule.Employee), nameof(WorkSchedule.Shift)],
                cancellationToken: cancellationToken);
            
            try
            {
                // Chỉ báo người thật sự có ca mới (trước đây ngày nào cũng đã có lịch vẫn nhận «Lịch làm việc mới»).
                var scheduledEmployeeIds = schedulesToCreate.Select(s => s.EmployeeUserId).ToHashSet();
                var affectedEmployeeIds = request.EmployeeUserIds.Distinct();
                var targetUserIds = new List<Guid>();
                var noAccountIds = new List<Guid>();
                foreach (var empId in affectedEmployeeIds)
                {
                    var emp = await employeeRepository.GetSingleAsync(
                        filter: e => (e.Id == empId || e.ApplicationUserId == empId) && e.StoreId == request.StoreId,
                        cancellationToken: cancellationToken);
                    if (emp == null || !scheduledEmployeeIds.Contains(emp.Id)) continue;
                    if (emp.ApplicationUserId.HasValue)
                        targetUserIds.Add(emp.ApplicationUserId.Value);
                    else
                        noAccountIds.Add(emp.Id);
                }

                if (schedulesToCreate.Count > 0)
                {
                    // «Lịch mới 10/11–16/11» / «Ca Sáng 07:00–11:00 · Chạm để xem lịch»
                    var range = ScheduleNotifyText.Range(
                        schedulesToCreate.Min(s => s.Date), schedulesToCreate.Max(s => s.Date));
                    var shiftText = shift != null ? ScheduleNotifyText.Slot(shift) : null;
                    var body = shiftText != null ? $"{shiftText} · Chạm để xem lịch" : "Chạm để xem lịch";

                    if (noAccountIds.Count > 0)
                    {
                        await notificationService.NotifyEmployeesWithoutAccountAsync(request.StoreId, noAccountIds,
                            "Lịch làm việc mới",
                            shiftText != null ? $"{range}: {shiftText}" : $"Bạn có lịch làm việc {range}",
                            "attendance");
                    }
                    if (targetUserIds.Count > 0)
                    {
                        await notificationService.CreateAndSendToUsersAsync(
                            targetUserIds.Distinct().ToList(), NotificationType.Info,
                            $"Lịch mới {range}",
                            body,
                            relatedEntityType: "WorkSchedule",
                            categoryCode: "shift", storeId: request.StoreId);
                    }
                }
            }
            catch { /* Notification failure should not affect main operation */ }

            return AppResponse<List<WorkScheduleDto>>.Success(results.Adapt<List<WorkScheduleDto>>());
        }
        catch (Exception ex)
        {
            return AppResponse<List<WorkScheduleDto>>.Error(ex.Message);
        }
    }
}

// Update Work Schedule Command
public record UpdateWorkScheduleCommand(
    Guid StoreId,
    Guid Id,
    Guid? ShiftId,
    TimeSpan? StartTime,
    TimeSpan? EndTime,
    bool IsDayOff,
    string? Note) : ICommand<AppResponse<WorkScheduleDto>>;

public class UpdateWorkScheduleHandler(
    IRepository<WorkSchedule> workScheduleRepository,
    IRepository<ShiftTemplate> shiftRepository,
    ISystemNotificationService notificationService,
    IAttendanceService attendanceService
) : ICommandHandler<UpdateWorkScheduleCommand, AppResponse<WorkScheduleDto>>
{
    public async Task<AppResponse<WorkScheduleDto>> Handle(UpdateWorkScheduleCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var workSchedule = await workScheduleRepository.GetSingleAsync(
                filter: w => w.Id == request.Id && w.StoreId == request.StoreId,
                includeProperties: [nameof(WorkSchedule.Employee), nameof(WorkSchedule.Shift)], 
                cancellationToken: cancellationToken);
            if (workSchedule == null)
            {
                return AppResponse<WorkScheduleDto>.Error("Work schedule not found");
            }

            var sameDay = await workScheduleRepository.GetAllAsync(
                w => w.EmployeeUserId == workSchedule.EmployeeUserId && w.StoreId == request.StoreId
                     && w.Date >= workSchedule.Date.Date && w.Date < workSchedule.Date.Date.AddDays(1)
                     && w.Id != workSchedule.Id,
                cancellationToken: cancellationToken);
            var updateError = WorkScheduleDuplicateHelper.Validate(sameDay, request.ShiftId, request.IsDayOff);
            if (updateError != null)
                return AppResponse<WorkScheduleDto>.Error(updateError);

            // Ca cũ (trước khi sửa) — để báo «Ca Sáng → Ca Chiều».
            var oldSlot = ScheduleNotifyText.Slot(
                workSchedule.Shift, workSchedule.StartTime, workSchedule.EndTime, workSchedule.IsDayOff);

            workSchedule.ShiftId = request.ShiftId;
            workSchedule.StartTime = request.StartTime;
            workSchedule.EndTime = request.EndTime;
            workSchedule.IsDayOff = request.IsDayOff;
            workSchedule.Note = request.Note;

            await workScheduleRepository.UpdateAsync(workSchedule, cancellationToken);
            await SchedulePenaltyRecalc.RunAsync(attendanceService, request.StoreId,
                [(workSchedule.EmployeeUserId, workSchedule.Date)], cancellationToken);

            try
            {
                // «Lịch 12/11 đã đổi» / «Ca Sáng 07:00–11:00 → Ca Chiều 13:00–21:00»
                ShiftTemplate? newShift = null;
                if (!request.IsDayOff && request.ShiftId.HasValue)
                {
                    newShift = request.ShiftId == workSchedule.Shift?.Id
                        ? workSchedule.Shift
                        : await shiftRepository.GetSingleAsync(
                            s => s.Id == request.ShiftId.Value, cancellationToken: cancellationToken);
                }
                var newSlot = ScheduleNotifyText.Slot(newShift, request.StartTime, request.EndTime, request.IsDayOff);
                var note = request.Note?.Trim();
                var body = !string.Equals(oldSlot, newSlot, StringComparison.Ordinal)
                    ? $"{oldSlot} → {newSlot}"
                    : string.IsNullOrEmpty(note) ? newSlot : $"{newSlot} · Ghi chú: {note}";
                var day = ScheduleNotifyText.Day(workSchedule.Date);

                if (workSchedule.Employee?.ApplicationUserId.HasValue == true)
                {
                    await notificationService.CreateAndSendAsync(
                        workSchedule.Employee.ApplicationUserId.Value, NotificationType.Info,
                        $"Lịch {day} đã đổi",
                        body,
                        relatedEntityId: workSchedule.Id, relatedEntityType: "WorkSchedule",
                        categoryCode: "shift", storeId: request.StoreId);
                }
                else if (workSchedule.Employee != null)
                {
                    await notificationService.NotifyEmployeesWithoutAccountAsync(request.StoreId, [workSchedule.Employee.Id],
                        "Cập nhật lịch làm việc", $"Ngày {day}: {body}", "attendance");
                }
            }
            catch { /* Notification failure should not affect main operation */ }
            
            return AppResponse<WorkScheduleDto>.Success(workSchedule.Adapt<WorkScheduleDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<WorkScheduleDto>.Error(ex.Message);
        }
    }
}

// Delete Work Schedule Command
public record DeleteWorkScheduleCommand(Guid StoreId, Guid Id) : ICommand<AppResponse<bool>>;

public class DeleteWorkScheduleHandler(
    IRepository<WorkSchedule> workScheduleRepository,
    IRepository<ShiftTemplate> shiftRepository,
    ISystemNotificationService notificationService,
    IAttendanceService attendanceService
) : ICommandHandler<DeleteWorkScheduleCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(DeleteWorkScheduleCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var workSchedule = await workScheduleRepository.GetSingleAsync(
                filter: w => w.Id == request.Id && w.StoreId == request.StoreId,
                includeProperties: [nameof(WorkSchedule.Employee)],
                cancellationToken: cancellationToken);
            if (workSchedule == null)
            {
                return AppResponse<bool>.Error("Work schedule not found");
            }

            var scheduleDate = workSchedule.Date;
            var notifyUserId = workSchedule.Employee?.ApplicationUserId;
            var removedShiftId = workSchedule.ShiftId;
            var removedStart = workSchedule.StartTime;
            var removedEnd = workSchedule.EndTime;
            var removedDayOff = workSchedule.IsDayOff;

            await workScheduleRepository.DeleteAsync(workSchedule, cancellationToken);
            await SchedulePenaltyRecalc.RunAsync(attendanceService, request.StoreId,
                [(workSchedule.EmployeeUserId, scheduleDate)], cancellationToken);

            // Notify employee about schedule removal
            try
            {
                if (!notifyUserId.HasValue) return AppResponse<bool>.Success(true);

                // «Lịch 12/11 đã bị xóa» / «Ca Sáng 07:00–11:00 · Bạn không còn ca này»
                var removedShift = !removedDayOff && removedShiftId.HasValue
                    ? await shiftRepository.GetSingleAsync(
                        s => s.Id == removedShiftId.Value, cancellationToken: cancellationToken)
                    : null;
                var removedText = removedDayOff
                    ? "Ngày nghỉ đã gỡ khỏi lịch"
                    : $"{ScheduleNotifyText.Slot(removedShift, removedStart, removedEnd)} · Bạn không còn ca này";

                await notificationService.CreateAndSendAsync(
                    targetUserId: notifyUserId.Value,
                    type: NotificationType.Warning,
                    title: $"Lịch {ScheduleNotifyText.Day(scheduleDate)} đã bị xóa",
                    message: removedText,
                    relatedEntityType: "WorkSchedule",
                    categoryCode: "shift",
                    storeId: request.StoreId);
            }
            catch { /* Don't fail delete if notification fails */ }
            
            return AppResponse<bool>.Success(true);
        }
        catch (Exception ex)
        {
            return AppResponse<bool>.Error(ex.Message);
        }
    }
}

// Create Schedule Registration Command
public record CreateScheduleRegistrationCommand(
    Guid StoreId,
    Guid EmployeeUserId,
    DateTime Date,
    Guid? ShiftId,
    bool IsDayOff,
    string? Note) : ICommand<AppResponse<ScheduleRegistrationDto>>;

public class CreateScheduleRegistrationHandler(
    IRepository<ScheduleRegistration> registrationRepository,
    IRepository<ScheduleApprovalRecord> scheduleApprovalRecordRepository,
    IRepository<AppSettings> appSettingsRepository,
    IRepository<Employee> employeeRepository,
    UserManager<ApplicationUser> userManager,
    ISystemNotificationService notificationService
) : ICommandHandler<CreateScheduleRegistrationCommand, AppResponse<ScheduleRegistrationDto>>
{
    public async Task<AppResponse<ScheduleRegistrationDto>> Handle(CreateScheduleRegistrationCommand request, CancellationToken cancellationToken)
    {
        try
        {
            // Look up by ApplicationUserId first (frontend sends ApplicationUser.Id), fallback to Employee.Id
            var employee = await employeeRepository.GetSingleAsync(
                filter: e => (e.ApplicationUserId == request.EmployeeUserId || e.Id == request.EmployeeUserId) && e.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            if (employee == null)
            {
                return AppResponse<ScheduleRegistrationDto>.Error("Employee not found");
            }

            if (request.Date.Date < DateTime.UtcNow.AddHours(7).Date)
                return AppResponse<ScheduleRegistrationDto>.Error("Không thể đăng ký lịch cho ngày đã qua");

            var duplicateReg = await registrationRepository.GetSingleAsync(
                filter: r => r.EmployeeUserId == employee.Id
                             && r.Date.Date == request.Date.Date
                             && r.StoreId == request.StoreId
                             && r.ShiftId == request.ShiftId
                             && r.IsDayOff == request.IsDayOff
                             && r.Status != ScheduleRegistrationStatus.Rejected,
                cancellationToken: cancellationToken);
            if (duplicateReg != null)
            {
                return AppResponse<ScheduleRegistrationDto>.Error(
                    request.IsDayOff
                        ? "Đã có đăng ký nghỉ cho ngày này"
                        : "Đã có đăng ký ca này cho ngày");
            }

            var approvalLevels = await ScheduleApprovalChainHelper.GetApprovalLevelsAsync(
                appSettingsRepository, request.StoreId, cancellationToken);

            var registration = new ScheduleRegistration
            {
                StoreId = request.StoreId,
                EmployeeUserId = employee.Id,
                Date = request.Date.Date,
                ShiftId = request.ShiftId,
                IsDayOff = request.IsDayOff,
                Note = request.Note,
                Status = ScheduleRegistrationStatus.Pending,
                TotalApprovalLevels = approvalLevels,
                CurrentApprovalStep = 0
            };

            var created = await registrationRepository.AddAsync(registration, cancellationToken);

            var employeeAppUserId = employee.ApplicationUserId ?? request.EmployeeUserId;
            var approvalChain = await ScheduleApprovalChainHelper.BuildApprovalChainAsync(
                employeeAppUserId, request.StoreId, approvalLevels,
                employeeRepository, userManager, cancellationToken);
            foreach (var record in approvalChain)
            {
                record.ScheduleRegistrationId = created.Id;
                record.StoreId = request.StoreId;
                await scheduleApprovalRecordRepository.AddAsync(record, cancellationToken);
            }

            var result = await registrationRepository.GetSingleAsync(
                filter: r => r.Id == created.Id && r.StoreId == request.StoreId,
                includeProperties: [
                    nameof(ScheduleRegistration.Employee),
                    nameof(ScheduleRegistration.Shift),
                    nameof(ScheduleRegistration.ApprovalRecords)
                ],
                cancellationToken: cancellationToken);

            try
            {
                var employeeName = $"{employee.LastName} {employee.FirstName}".Trim();
                if (string.IsNullOrWhiteSpace(employeeName))
                    employeeName = "Nhân viên";

                var firstApprover = approvalChain
                    .Where(r => r.StepOrder == 1 && r.AssignedUserId.HasValue)
                    .Select(r => r.AssignedUserId!.Value)
                    .ToList();

                if (firstApprover.Count > 0)
                {
                    // «Cần duyệt đăng ký lịch» / «Nguyễn Văn An · 12/11 · Ca Sáng 07:00–11:00 · Cấp 1/2»
                    var slot = request.IsDayOff ? "Xin nghỉ" : ScheduleNotifyText.Slot(result?.Shift);
                    await notificationService.CreateAndSendToUsersAsync(
                        firstApprover, NotificationType.ApprovalRequired,
                        "Cần duyệt đăng ký lịch",
                        $"{employeeName} · {ScheduleNotifyText.Day(request.Date)} · {slot}" +
                        (approvalLevels > 1 ? $" · Cấp 1/{approvalLevels}" : ""),
                        relatedEntityId: created.Id, relatedEntityType: "ScheduleRegistration",
                        fromUserId: employee.ApplicationUserId, categoryCode: "shift",
                        storeId: request.StoreId);
                }
            }
            catch { /* Notification failure should not affect main operation */ }

            return AppResponse<ScheduleRegistrationDto>.Success(result!.Adapt<ScheduleRegistrationDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<ScheduleRegistrationDto>.Error(ex.Message);
        }
    }
}

// Delete Schedule Registration Command (only pending registrations)
public record DeleteScheduleRegistrationCommand(
    Guid StoreId,
    Guid RegistrationId,
    Guid? CallerUserId = null,
    bool CallerIsManager = true) : ICommand<AppResponse<bool>>;

public class DeleteScheduleRegistrationHandler(
    IRepository<ScheduleRegistration> registrationRepository,
    IRepository<ScheduleApprovalRecord> scheduleApprovalRecordRepository,
    IRepository<WorkSchedule> workScheduleRepository,
    IRepository<Employee> employeeRepository,
    ISystemNotificationService notificationService
) : ICommandHandler<DeleteScheduleRegistrationCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(DeleteScheduleRegistrationCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var registration = await registrationRepository.GetSingleAsync(
                filter: r => r.Id == request.RegistrationId && r.StoreId == request.StoreId,
                cancellationToken: cancellationToken);

            if (registration == null)
            {
                return AppResponse<bool>.Error("Không tìm thấy đăng ký");
            }

            var registrationDate = registration.Date;
            var registrationWasApproved = registration.Status == ScheduleRegistrationStatus.Approved;
            var registrationIsDayOff = registration.IsDayOff;
            var employee = await employeeRepository.GetSingleAsync(
                filter: e => e.Id == registration.EmployeeUserId && e.StoreId == request.StoreId,
                cancellationToken: cancellationToken);

            // Nhân viên chỉ được xóa phiếu chờ duyệt của chính mình; xóa phiếu đã xử lý là việc của quản lý.
            if (!request.CallerIsManager)
            {
                if (employee?.ApplicationUserId == null || employee.ApplicationUserId != request.CallerUserId)
                    return AppResponse<bool>.Error("Bạn chỉ được xóa đăng ký của chính mình");
                if (registration.Status != ScheduleRegistrationStatus.Pending)
                    return AppResponse<bool>.Error("Đăng ký đã được xử lý, không thể xóa");
            }

            // Đã duyệt → gỡ lịch do phiếu tạo (không đụng lịch quản lý đã xếp sẵn).
            if (registration.Status == ScheduleRegistrationStatus.Approved)
            {
                await RegistrationScheduleCleanup.RemoveAppliedScheduleAsync(
                    registration, request.StoreId, workScheduleRepository, cancellationToken);
            }

            var approvalRecords = await scheduleApprovalRecordRepository.GetAllAsync(
                r => r.ScheduleRegistrationId == registration.Id,
                cancellationToken: cancellationToken);
            foreach (var ar in approvalRecords)
                await scheduleApprovalRecordRepository.DeleteAsync(ar, cancellationToken);

            await registrationRepository.DeleteAsync(registration, cancellationToken);

            // Notify employee about registration deletion
            try
            {
                // Nhân viên tự xóa phiếu của mình thì không cần báo lại cho chính họ.
                if (employee?.ApplicationUserId.HasValue == true
                    && employee.ApplicationUserId != request.CallerUserId)
                {
                    // «Đăng ký lịch 12/11 đã bị xóa» / «Lê Thị Hoa: Ca đã xếp từ đăng ký này cũng được gỡ khỏi lịch»
                    var detail = registrationWasApproved
                        ? registrationIsDayOff
                            ? "Ngày nghỉ đã duyệt cũng được gỡ khỏi lịch"
                            : "Ca đã xếp từ đăng ký này cũng được gỡ khỏi lịch"
                        : "Bạn có thể đăng ký lại nếu cần";
                    await notificationService.CreateAndSendAsync(
                        targetUserId: employee.ApplicationUserId.Value,
                        type: NotificationType.Warning,
                        title: $"Đăng ký lịch {ScheduleNotifyText.Day(registrationDate)} đã bị xóa",
                        message: detail,
                        relatedEntityType: "WorkSchedule",
                        fromUserId: request.CallerUserId,
                        categoryCode: "shift",
                        storeId: request.StoreId);
                }
            }
            catch { /* Don't fail delete if notification fails */ }

            return AppResponse<bool>.Success(true);
        }
        catch (Exception ex)
        {
            return AppResponse<bool>.Error(ex.Message);
        }
    }
}

// Approve Schedule Registration Command
public record ApproveScheduleRegistrationCommand(
    Guid StoreId,
    Guid RequestId,
    Guid ApprovedById,
    bool IsApproved,
    string? RejectionReason) : ICommand<AppResponse<ScheduleRegistrationDto>>;

public class ApproveScheduleRegistrationHandler(
    IRepository<ScheduleRegistration> registrationRepository,
    IRepository<ScheduleApprovalRecord> scheduleApprovalRecordRepository,
    IRepository<WorkSchedule> workScheduleRepository,
    IRepository<ShiftStaffingQuota> staffingQuotaRepository,
    IRepository<Employee> employeeRepository,
    UserManager<ApplicationUser> userManager,
    ISystemNotificationService notificationService
) : ICommandHandler<ApproveScheduleRegistrationCommand, AppResponse<ScheduleRegistrationDto>>
{
    public async Task<AppResponse<ScheduleRegistrationDto>> Handle(ApproveScheduleRegistrationCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var registration = await registrationRepository.GetSingleAsync(
                filter: r => r.Id == request.RequestId && r.StoreId == request.StoreId,
                includeProperties: [
                    nameof(ScheduleRegistration.Employee),
                    nameof(ScheduleRegistration.Shift),
                    nameof(ScheduleRegistration.ApprovedBy)
                ],
                cancellationToken: cancellationToken);

            if (registration == null)
                return AppResponse<ScheduleRegistrationDto>.Error("Schedule registration not found");

            if (registration.Status != ScheduleRegistrationStatus.Pending)
                return AppResponse<ScheduleRegistrationDto>.Error("This registration has already been processed");

            var allRecords = (await scheduleApprovalRecordRepository.GetAllAsync(
                r => r.ScheduleRegistrationId == request.RequestId,
                cancellationToken: cancellationToken))
                .OrderBy(r => r.StepOrder).ToList();

            var currentRecord = allRecords.FirstOrDefault(r => r.Status == ApprovalStatus.Pending);

            if (allRecords.Count == 0)
            {
                currentRecord = new ScheduleApprovalRecord
                {
                    ScheduleRegistrationId = request.RequestId,
                    StepOrder = 1,
                    StepName = "Phê duyệt",
                    AssignedUserId = request.ApprovedById,
                    Status = ApprovalStatus.Pending,
                    StoreId = request.StoreId
                };
                await scheduleApprovalRecordRepository.AddAsync(currentRecord, cancellationToken);
                allRecords.Add(currentRecord);
                registration.TotalApprovalLevels = Math.Max(1, registration.TotalApprovalLevels);
            }

            var approver = await userManager.FindByIdAsync(request.ApprovedById.ToString());
            var canApproveAsStoreManager = IsStoreScheduleApproverRole(approver?.Role);

            // Không tự duyệt phiếu của chính mình (Admin/SuperAdmin là ngoại lệ vì có thể không có cấp trên).
            var isOwnRequest = registration.Employee?.ApplicationUserId == request.ApprovedById;
            var isTopAdmin = approver?.Role != null
                && (approver.Role.Equals(nameof(Roles.Admin), StringComparison.OrdinalIgnoreCase)
                    || approver.Role.Equals(nameof(Roles.SuperAdmin), StringComparison.OrdinalIgnoreCase));
            if (isOwnRequest && !isTopAdmin)
                return AppResponse<ScheduleRegistrationDto>.Error("Bạn không thể tự duyệt đăng ký lịch của chính mình");

            // Bản ghi mồ côi: mọi bước đã Approved nhưng phiếu vẫn Pending (Apply lịch lần trước bị lỗi).
            if (currentRecord == null
                && request.IsApproved
                && allRecords.Count > 0
                && allRecords.All(r => r.Status == ApprovalStatus.Approved))
            {
                if (!canApproveAsStoreManager)
                    return AppResponse<ScheduleRegistrationDto>.Error("Bạn không có quyền hoàn tất yêu cầu này");

                var quotaErrorOrphan = await ScheduleStaffingQuotaHelper.GetQuotaExceededMessageAsync(
                    staffingQuotaRepository, workScheduleRepository, registrationRepository,
                    employeeRepository, registration, request.StoreId, cancellationToken);
                if (quotaErrorOrphan != null)
                    return AppResponse<ScheduleRegistrationDto>.Error(quotaErrorOrphan);

                await ApplyApprovedScheduleAsync(registration, request.StoreId, workScheduleRepository, cancellationToken);
                registration.Status = ScheduleRegistrationStatus.Approved;
                registration.ApprovedById = request.ApprovedById;
                registration.ApprovedDate = DateTime.UtcNow;
                registration.RejectionReason = null;
                registration.CurrentApprovalStep = allRecords.Max(r => r.StepOrder);
                await registrationRepository.UpdateAsync(registration, cancellationToken);
                return await ReloadRegistrationDtoAsync(
                    registrationRepository, registration.Id, request.StoreId, cancellationToken);
            }

            if (currentRecord == null)
                return AppResponse<ScheduleRegistrationDto>.Error("Không còn bước duyệt nào cần xử lý");

            // Màn Duyệt lịch: QL/GĐ được duyệt hàng đợi cửa hàng, không chỉ người được gán chuỗi.
            // AssignedUserId null (không có QL trực tiếp / Admin) → bất kỳ QL cửa hàng cũng duyệt được.
            var isAssigned = !currentRecord.AssignedUserId.HasValue
                             || currentRecord.AssignedUserId == request.ApprovedById;
            if (!canApproveAsStoreManager && !isAssigned)
                return AppResponse<ScheduleRegistrationDto>.Error("Bạn không có quyền duyệt bước này");

            if (!request.IsApproved)
            {
                currentRecord.ActualUserId = request.ApprovedById;
                currentRecord.ActualUserName = approver?.FullName ?? approver?.Email;
                currentRecord.Status = ApprovalStatus.Rejected;
                currentRecord.Note = request.RejectionReason;
                currentRecord.ActionDate = DateTime.UtcNow;
                await scheduleApprovalRecordRepository.UpdateAsync(currentRecord, cancellationToken);

                registration.Status = ScheduleRegistrationStatus.Rejected;
                registration.ApprovedById = request.ApprovedById;
                registration.ApprovedDate = DateTime.UtcNow;
                registration.RejectionReason = request.RejectionReason;
                registration.CurrentApprovalStep = currentRecord.StepOrder;
                await registrationRepository.UpdateAsync(registration, cancellationToken);

                try
                {
                    if (registration.Employee?.ApplicationUserId.HasValue == true)
                    {
                        // «Đăng ký lịch 12/11 bị từ chối» / «Ca Sáng 07:00–11:00 · Lý do: Đủ người · Cấp 1/2»
                        var parts = new List<string> { RegistrationSlot(registration) };
                        if (!string.IsNullOrWhiteSpace(request.RejectionReason))
                            parts.Add($"Lý do: {request.RejectionReason.Trim()}");
                        if (registration.TotalApprovalLevels > 1)
                            parts.Add($"Cấp {currentRecord.StepOrder}/{registration.TotalApprovalLevels}");
                        await notificationService.CreateAndSendAsync(
                            registration.Employee.ApplicationUserId.Value, NotificationType.Warning,
                            $"Đăng ký lịch {ScheduleNotifyText.Day(registration.Date)} bị từ chối",
                            string.Join(" · ", parts),
                            relatedEntityId: registration.Id, relatedEntityType: "ScheduleRegistration",
                            fromUserId: request.ApprovedById, categoryCode: "shift", storeId: request.StoreId);
                    }
                }
                catch { }

                return AppResponse<ScheduleRegistrationDto>.Success(registration.Adapt<ScheduleRegistrationDto>());
            }

            var nextPending = allRecords.FirstOrDefault(r =>
                r.StepOrder > currentRecord.StepOrder && r.Status == ApprovalStatus.Pending);
            if (nextPending == null)
            {
                var quotaError = await ScheduleStaffingQuotaHelper.GetQuotaExceededMessageAsync(
                    staffingQuotaRepository, workScheduleRepository, registrationRepository,
                    employeeRepository, registration, request.StoreId, cancellationToken);
                if (quotaError != null)
                    return AppResponse<ScheduleRegistrationDto>.Error(quotaError);

                // Ghi lịch trước khi đánh dấu bước duyệt — nếu Apply lỗi, phiếu vẫn Pending để duyệt lại.
                await ApplyApprovedScheduleAsync(registration, request.StoreId, workScheduleRepository, cancellationToken);
            }

            currentRecord.ActualUserId = request.ApprovedById;
            currentRecord.ActualUserName = approver?.FullName ?? approver?.Email;
            currentRecord.Status = ApprovalStatus.Approved;
            currentRecord.Note = "Đã phê duyệt";
            currentRecord.ActionDate = DateTime.UtcNow;
            await scheduleApprovalRecordRepository.UpdateAsync(currentRecord, cancellationToken);

            registration.CurrentApprovalStep = currentRecord.StepOrder;

            if (nextPending == null)
            {
                registration.Status = ScheduleRegistrationStatus.Approved;
                registration.ApprovedById = request.ApprovedById;
                registration.ApprovedDate = DateTime.UtcNow;
                registration.RejectionReason = null;

                await registrationRepository.UpdateAsync(registration, cancellationToken);

                try
                {
                    if (registration.Employee?.ApplicationUserId.HasValue == true)
                    {
                        // «Đăng ký lịch 12/11 đã duyệt» / «Lê Thị Hoa: Ca Sáng 07:00–11:00 · Đã vào lịch»
                        await notificationService.CreateAndSendAsync(
                            registration.Employee.ApplicationUserId.Value, NotificationType.Success,
                            $"Đăng ký lịch {ScheduleNotifyText.Day(registration.Date)} đã duyệt",
                            registration.TotalApprovalLevels > 1
                                ? $"{RegistrationSlot(registration)} · Đã vào lịch (duyệt đủ {registration.TotalApprovalLevels} cấp)"
                                : $"{RegistrationSlot(registration)} · Đã vào lịch",
                            relatedEntityId: registration.Id, relatedEntityType: "ScheduleRegistration",
                            fromUserId: request.ApprovedById, categoryCode: "shift", storeId: request.StoreId);
                    }
                }
                catch { }
            }
            else
            {
                await registrationRepository.UpdateAsync(registration, cancellationToken);

                try
                {
                    if (nextPending.AssignedUserId.HasValue)
                    {
                        // Người gửi = NV xin (không phải người duyệt trước — formatter đưa tên người gửi lên đầu).
                        // «Cần duyệt đăng ký lịch» / «Nguyễn Văn An · 12/11 · Ca Sáng 07:00–11:00 · Cấp 2/2 · Lê Thị Hoa đã duyệt cấp 1»
                        var approverName = NotificationPushFormatter.FormatUserDisplayName(approver);
                        var body = $"{ScheduleNotifyText.EmployeeName(registration.Employee)} · {ScheduleNotifyText.Day(registration.Date)} · " +
                                   $"{RegistrationSlot(registration)} · Cấp {nextPending.StepOrder}/{registration.TotalApprovalLevels}";
                        if (!string.IsNullOrWhiteSpace(approverName))
                            body += $" · {approverName} đã duyệt cấp {currentRecord.StepOrder}";
                        await notificationService.CreateAndSendAsync(
                            nextPending.AssignedUserId.Value, NotificationType.ApprovalRequired,
                            "Cần duyệt đăng ký lịch",
                            body,
                            relatedEntityId: registration.Id, relatedEntityType: "ScheduleRegistration",
                            fromUserId: registration.Employee?.ApplicationUserId, categoryCode: "shift", storeId: request.StoreId);
                    }

                    if (registration.Employee?.ApplicationUserId.HasValue == true)
                    {
                        // «Đăng ký lịch 12/11: xong cấp 1/2» / «Lê Thị Hoa: Ca Sáng 07:00–11:00 · Chờ duyệt cấp 2»
                        await notificationService.CreateAndSendAsync(
                            registration.Employee.ApplicationUserId.Value, NotificationType.Info,
                            $"Đăng ký lịch {ScheduleNotifyText.Day(registration.Date)}: xong cấp {currentRecord.StepOrder}/{registration.TotalApprovalLevels}",
                            $"{RegistrationSlot(registration)} · Chờ duyệt cấp {nextPending.StepOrder}",
                            relatedEntityId: registration.Id, relatedEntityType: "ScheduleRegistration",
                            fromUserId: request.ApprovedById, categoryCode: "shift", storeId: request.StoreId);
                    }
                }
                catch { }
            }

            return await ReloadRegistrationDtoAsync(
                registrationRepository, registration.Id, request.StoreId, cancellationToken);
        }
        catch (Exception ex)
        {
            return AppResponse<ScheduleRegistrationDto>.Error(ex.Message);
        }
    }

    /// <summary>«Ca Sáng 07:00–11:00» / «Ngày nghỉ» cho thông báo duyệt đăng ký lịch.</summary>
    private static string RegistrationSlot(ScheduleRegistration registration) =>
        registration.IsDayOff ? "Ngày nghỉ" : ScheduleNotifyText.Slot(registration.Shift);

    /// <summary>Cùng tập vai trò policy AtLeastManager — màn Duyệt lịch là hàng đợi cửa hàng.</summary>
    private static bool IsStoreScheduleApproverRole(string? role)
    {
        if (string.IsNullOrWhiteSpace(role))
            return false;
        return role.Equals(nameof(Roles.Admin), StringComparison.OrdinalIgnoreCase)
            || role.Equals(nameof(Roles.SuperAdmin), StringComparison.OrdinalIgnoreCase)
            || role.Equals(nameof(Roles.Director), StringComparison.OrdinalIgnoreCase)
            || role.Equals(nameof(Roles.Manager), StringComparison.OrdinalIgnoreCase)
            || role.Equals(nameof(Roles.DepartmentHead), StringComparison.OrdinalIgnoreCase)
            || role.Equals(nameof(Roles.Agent), StringComparison.OrdinalIgnoreCase);
    }

    private static async Task<AppResponse<ScheduleRegistrationDto>> ReloadRegistrationDtoAsync(
        IRepository<ScheduleRegistration> registrationRepository,
        Guid registrationId,
        Guid storeId,
        CancellationToken cancellationToken)
    {
        var refreshed = await registrationRepository.GetSingleAsync(
            filter: r => r.Id == registrationId && r.StoreId == storeId,
            includeProperties: [
                nameof(ScheduleRegistration.Employee),
                nameof(ScheduleRegistration.Shift),
                nameof(ScheduleRegistration.ApprovalRecords)
            ],
            cancellationToken: cancellationToken);

        return AppResponse<ScheduleRegistrationDto>.Success(refreshed!.Adapt<ScheduleRegistrationDto>());
    }

    private static async Task ApplyApprovedScheduleAsync(
        ScheduleRegistration registration,
        Guid storeId,
        IRepository<WorkSchedule> workScheduleRepository,
        CancellationToken cancellationToken)
    {
        var dayStart = registration.Date.Date;
        var dayEnd = dayStart.AddDays(1);
        var daySchedules = await workScheduleRepository.GetAllAsync(
            ws => ws.EmployeeUserId == registration.EmployeeUserId
                  && ws.Date >= dayStart && ws.Date < dayEnd
                  && ws.StoreId == storeId,
            cancellationToken: cancellationToken);

        if (registration.IsDayOff && daySchedules.Any(ws => !ws.IsDayOff && ws.ShiftId != null))
            throw new InvalidOperationException(
                "Nhân viên đã được xếp ca trong ngày này — hãy gỡ ca trên lịch trước khi duyệt đăng ký nghỉ");
        if (!registration.IsDayOff && daySchedules.Any(ws => ws.IsDayOff))
            throw new InvalidOperationException(
                "Nhân viên đang được đánh dấu nghỉ trong ngày này — hãy gỡ ngày nghỉ trước khi duyệt đăng ký ca");

        var existingSchedule = daySchedules.FirstOrDefault(ws =>
            WorkScheduleDuplicateHelper.ConflictsWith(
                ws, registration.EmployeeUserId, registration.Date, registration.ShiftId, registration.IsDayOff));

        if (existingSchedule != null)
        {
            existingSchedule.ShiftId = registration.ShiftId;
            existingSchedule.IsDayOff = registration.IsDayOff;
            existingSchedule.Note = registration.Note;
            await workScheduleRepository.UpdateAsync(existingSchedule, cancellationToken);
            registration.AppliedWorkScheduleId = existingSchedule.Id;
            registration.AppliedCreatedNewSchedule = false;
        }
        else
        {
            var workSchedule = new WorkSchedule
            {
                StoreId = storeId,
                EmployeeUserId = registration.EmployeeUserId,
                ShiftId = registration.ShiftId,
                Date = registration.Date,
                IsDayOff = registration.IsDayOff,
                Note = registration.Note
            };
            var created = await workScheduleRepository.AddAsync(workSchedule, cancellationToken);
            registration.AppliedWorkScheduleId = created.Id;
            registration.AppliedCreatedNewSchedule = true;
        }
    }
}

// Undo Schedule Registration Approval Command
public record UndoScheduleRegistrationApprovalCommand(
    Guid StoreId,
    Guid RegistrationId) : ICommand<AppResponse<bool>>;

public class UndoScheduleRegistrationApprovalHandler(
    IRepository<ScheduleRegistration> registrationRepository,
    IRepository<ScheduleApprovalRecord> scheduleApprovalRecordRepository,
    IRepository<WorkSchedule> workScheduleRepository,
    IRepository<Employee> employeeRepository,
    ISystemNotificationService notificationService
) : ICommandHandler<UndoScheduleRegistrationApprovalCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(UndoScheduleRegistrationApprovalCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var registration = await registrationRepository.GetSingleAsync(
                filter: r => r.Id == request.RegistrationId && r.StoreId == request.StoreId,
                cancellationToken: cancellationToken);

            if (registration == null)
            {
                return AppResponse<bool>.Error("Không tìm thấy đăng ký");
            }

            if (registration.Status == ScheduleRegistrationStatus.Pending)
            {
                return AppResponse<bool>.Error("Đăng ký đang ở trạng thái chờ duyệt");
            }

            var wasApproved = registration.Status == ScheduleRegistrationStatus.Approved;
            // Gỡ lịch trước khi xóa dấu vết dòng lịch đã ghi.
            if (wasApproved)
            {
                await RegistrationScheduleCleanup.RemoveAppliedScheduleAsync(
                    registration, request.StoreId, workScheduleRepository, cancellationToken);
            }
            registration.AppliedWorkScheduleId = null;
            registration.AppliedCreatedNewSchedule = false;

            registration.Status = ScheduleRegistrationStatus.Pending;
            registration.ApprovedById = null;
            registration.ApprovedDate = null;
            registration.RejectionReason = null;
            registration.CurrentApprovalStep = 0;
            registration.UpdatedAt = DateTime.Now;
            await registrationRepository.UpdateAsync(registration, cancellationToken);

            var approvalRecords = (await scheduleApprovalRecordRepository.GetAllAsync(
                r => r.ScheduleRegistrationId == registration.Id,
                cancellationToken: cancellationToken))
                .OrderBy(r => r.StepOrder).ToList();
            foreach (var ar in approvalRecords)
            {
                ar.Status = ApprovalStatus.Pending;
                ar.ActualUserId = null;
                ar.ActualUserName = null;
                ar.Note = null;
                ar.ActionDate = null;
                await scheduleApprovalRecordRepository.UpdateAsync(ar, cancellationToken);
            }

            try
            {
                var employee = await employeeRepository.GetSingleAsync(
                    filter: e => e.Id == registration.EmployeeUserId,
                    cancellationToken: cancellationToken);
                if (employee?.ApplicationUserId.HasValue == true)
                {
                    await notificationService.CreateAndSendAsync(
                        employee.ApplicationUserId.Value, NotificationType.Warning,
                        $"Đăng ký lịch {ScheduleNotifyText.Day(registration.Date)} quay lại chờ duyệt",
                        wasApproved
                            ? "Ca đã xếp từ đăng ký này được gỡ khỏi lịch, chờ duyệt lại"
                            : "Kết quả duyệt trước đã hủy, chờ duyệt lại",
                        relatedEntityId: registration.Id, relatedEntityType: "ScheduleRegistration",
                        categoryCode: "shift", storeId: request.StoreId);
                }
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

// ══════════════════════════════════════════════
// Send Schedule Reminder to employees who haven't registered
// ══════════════════════════════════════════════
public record SendScheduleReminderCommand(
    Guid StoreId, Guid FromUserId,
    DateTime FromDate, DateTime ToDate,
    string? Department) : ICommand<AppResponse<int>>;

public class SendScheduleReminderHandler(
    IRepository<Employee> employeeRepository,
    IRepository<ScheduleRegistration> registrationRepository,
    IRepository<WorkSchedule> workScheduleRepository,
    ISystemNotificationService notificationService
) : ICommandHandler<SendScheduleReminderCommand, AppResponse<int>>
{
    public async Task<AppResponse<int>> Handle(SendScheduleReminderCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var employees = await employeeRepository.GetAllAsync(
                e => e.StoreId == request.StoreId && e.ApplicationUserId.HasValue
                     && (request.Department == null || e.Department == request.Department),
                cancellationToken: cancellationToken);

            var registeredEmployeeIds = new HashSet<Guid>();
            var registrations = await registrationRepository.GetAllAsync(
                r => r.StoreId == request.StoreId
                     && r.Date >= request.FromDate.Date && r.Date <= request.ToDate.Date,
                cancellationToken: cancellationToken);
            foreach (var r in registrations) registeredEmployeeIds.Add(r.EmployeeUserId);

            var schedules = await workScheduleRepository.GetAllAsync(
                s => s.StoreId == request.StoreId
                     && s.Date >= request.FromDate.Date && s.Date <= request.ToDate.Date,
                cancellationToken: cancellationToken);
            foreach (var s in schedules) registeredEmployeeIds.Add(s.EmployeeUserId);

            var unregistered = employees.Where(e =>
                !registeredEmployeeIds.Contains(e.ApplicationUserId!.Value)
                && !registeredEmployeeIds.Contains(e.Id)).ToList();

            if (unregistered.Count == 0)
                return AppResponse<int>.Success(0);

            var userIds = unregistered
                .Where(e => e.ApplicationUserId.HasValue)
                .Select(e => e.ApplicationUserId!.Value).ToList();

            await notificationService.CreateAndSendToUsersAsync(
                userIds, NotificationType.Warning,
                $"Nhắc đăng ký lịch {ScheduleNotifyText.Range(request.FromDate, request.ToDate)}",
                "Bạn chưa đăng ký lịch làm việc · Chạm để đăng ký",
                relatedEntityType: "WorkSchedule",
                categoryCode: "shift", storeId: request.StoreId,
                fromUserId: request.FromUserId);

            return AppResponse<int>.Success(unregistered.Count);
        }
        catch (Exception ex)
        {
            return AppResponse<int>.Error(ex.Message);
        }
    }
}

// ══════════════════════════════════════════════
// Request Shift Coverage - notify employees to register for a specific shift
// ══════════════════════════════════════════════
public record RequestShiftCoverageCommand(
    Guid StoreId, Guid FromUserId,
    Guid ShiftTemplateId, DateTime Date,
    string? Department, string? Message) : ICommand<AppResponse<int>>;

public class RequestShiftCoverageHandler(
    IRepository<Employee> employeeRepository,
    IRepository<ShiftTemplate> shiftRepository,
    IRepository<WorkSchedule> workScheduleRepository,
    ISystemNotificationService notificationService
) : ICommandHandler<RequestShiftCoverageCommand, AppResponse<int>>
{
    public async Task<AppResponse<int>> Handle(RequestShiftCoverageCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var shift = await shiftRepository.GetSingleAsync(
                s => s.Id == request.ShiftTemplateId && s.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            if (shift == null) return AppResponse<int>.Error("Shift not found");

            // Get employees NOT already scheduled for this shift on this day
            var existingSchedules = await workScheduleRepository.GetAllAsync(
                s => s.StoreId == request.StoreId && s.Date.Date == request.Date.Date && s.ShiftId == request.ShiftTemplateId,
                cancellationToken: cancellationToken);
            var scheduledEmpIds = existingSchedules.Select(s => s.EmployeeUserId).ToHashSet();

            var employees = await employeeRepository.GetAllAsync(
                e => e.StoreId == request.StoreId && e.ApplicationUserId.HasValue
                     && (request.Department == null || e.Department == request.Department),
                cancellationToken: cancellationToken);

            var unscheduled = employees.Where(e =>
                !scheduledEmpIds.Contains(e.ApplicationUserId!.Value)
                && !scheduledEmpIds.Contains(e.Id)).ToList();

            if (unscheduled.Count == 0)
                return AppResponse<int>.Success(0);

            var userIds = unscheduled.Where(e => e.ApplicationUserId.HasValue)
                .Select(e => e.ApplicationUserId!.Value).ToList();

            // «Cần thêm người Ca Sáng 12/11» / «07:00–11:00 · Chạm để đăng ký» (hoặc lời nhắn của quản lý).
            var hours = ScheduleNotifyText.Hours(shift.StartTime, shift.EndTime);
            var msg = !string.IsNullOrWhiteSpace(request.Message)
                ? (hours != null ? $"{hours} · {request.Message.Trim()}" : request.Message.Trim())
                : (hours != null ? $"{hours} · Chạm để đăng ký" : "Chạm để đăng ký");

            await notificationService.CreateAndSendToUsersAsync(
                userIds, NotificationType.Info,
                $"Cần thêm người {ScheduleNotifyText.ShiftOnDay(shift, request.Date)}",
                msg,
                relatedEntityType: "WorkSchedule",
                categoryCode: "shift", storeId: request.StoreId,
                fromUserId: request.FromUserId);

            return AppResponse<int>.Success(unscheduled.Count);
        }
        catch (Exception ex)
        {
            return AppResponse<int>.Error(ex.Message);
        }
    }
}

// ══════════════════════════════════════════════
// CRUD for Shift Staffing Quotas
// ══════════════════════════════════════════════
public record GetShiftStaffingQuotasQuery(Guid StoreId) : IQuery<AppResponse<List<ShiftStaffingQuotaDto>>>;

public class GetShiftStaffingQuotasHandler(
    IRepository<ShiftStaffingQuota> quotaRepository,
    IRepository<ShiftTemplate> shiftRepository
) : IQueryHandler<GetShiftStaffingQuotasQuery, AppResponse<List<ShiftStaffingQuotaDto>>>
{
    public async Task<AppResponse<List<ShiftStaffingQuotaDto>>> Handle(GetShiftStaffingQuotasQuery request, CancellationToken cancellationToken)
    {
        try
        {
            var quotas = await quotaRepository.GetAllAsync(
                q => q.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            var shifts = await shiftRepository.GetAllAsync(
                s => s.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            var shiftDict = shifts.ToDictionary(s => s.Id, s => s.Name);

            var result = quotas.Select(q => new ShiftStaffingQuotaDto
            {
                Id = q.Id,
                ShiftTemplateId = q.ShiftTemplateId,
                ShiftName = shiftDict.GetValueOrDefault(q.ShiftTemplateId, ""),
                Department = q.Department,
                MinEmployees = q.MinEmployees,
                MaxEmployees = q.MaxEmployees,
                WarningThreshold = q.WarningThreshold,
                DailyQuotas = StaffingQuotaResolver.ParseDailyQuotas(q.DailyQuotasJson)
                    .Select(d => new ShiftStaffingDailyQuotaDto
                    {
                        DayOfWeek = d.DayOfWeek,
                        MinEmployees = d.MinEmployees,
                        MaxEmployees = d.MaxEmployees,
                    }).ToList(),
            }).ToList();

            return AppResponse<List<ShiftStaffingQuotaDto>>.Success(result);
        }
        catch (Exception ex)
        {
            return AppResponse<List<ShiftStaffingQuotaDto>>.Error(ex.Message);
        }
    }
}

public record UpsertShiftStaffingQuotaCommand(
    Guid StoreId, Guid ShiftTemplateId, string? Department,
    int MinEmployees, int MaxEmployees, int WarningThreshold,
    List<StaffingDailyQuotaDto>? DailyQuotas
) : ICommand<AppResponse<ShiftStaffingQuotaDto>>;

public class UpsertShiftStaffingQuotaHandler(
    IRepository<ShiftStaffingQuota> quotaRepository,
    IRepository<ShiftTemplate> shiftRepository
) : ICommandHandler<UpsertShiftStaffingQuotaCommand, AppResponse<ShiftStaffingQuotaDto>>
{
    public async Task<AppResponse<ShiftStaffingQuotaDto>> Handle(UpsertShiftStaffingQuotaCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var shift = await shiftRepository.GetSingleAsync(
                s => s.Id == request.ShiftTemplateId && s.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            if (shift == null) return AppResponse<ShiftStaffingQuotaDto>.Error("Shift not found");

            var existing = await quotaRepository.GetSingleAsync(
                q => q.StoreId == request.StoreId && q.ShiftTemplateId == request.ShiftTemplateId
                     && ((q.Department == null && request.Department == null) || q.Department == request.Department),
                cancellationToken: cancellationToken);

            var dailyJson = StaffingQuotaResolver.SerializeDailyQuotas(request.DailyQuotas);

            if (existing != null)
            {
                existing.MinEmployees = request.MinEmployees;
                existing.MaxEmployees = request.MaxEmployees;
                existing.WarningThreshold = request.WarningThreshold;
                existing.DailyQuotasJson = dailyJson;
                existing.UpdatedAt = DateTime.Now;
                await quotaRepository.UpdateAsync(existing, cancellationToken);

                return AppResponse<ShiftStaffingQuotaDto>.Success(MapQuotaDto(existing, shift.Name));
            }

            var quota = new ShiftStaffingQuota
            {
                StoreId = request.StoreId,
                ShiftTemplateId = request.ShiftTemplateId,
                Department = request.Department,
                MinEmployees = request.MinEmployees,
                MaxEmployees = request.MaxEmployees,
                WarningThreshold = request.WarningThreshold,
                DailyQuotasJson = dailyJson,
            };
            var created = await quotaRepository.AddAsync(quota, cancellationToken);

            return AppResponse<ShiftStaffingQuotaDto>.Success(MapQuotaDto(created, shift.Name));
        }
        catch (Exception ex)
        {
            return AppResponse<ShiftStaffingQuotaDto>.Error(ex.Message);
        }
    }

    private static ShiftStaffingQuotaDto MapQuotaDto(ShiftStaffingQuota q, string shiftName) =>
        new()
        {
            Id = q.Id,
            ShiftTemplateId = q.ShiftTemplateId,
            ShiftName = shiftName,
            Department = q.Department,
            MinEmployees = q.MinEmployees,
            MaxEmployees = q.MaxEmployees,
            WarningThreshold = q.WarningThreshold,
            DailyQuotas = StaffingQuotaResolver.ParseDailyQuotas(q.DailyQuotasJson)
                .Select(d => new ShiftStaffingDailyQuotaDto
                {
                    DayOfWeek = d.DayOfWeek,
                    MinEmployees = d.MinEmployees,
                    MaxEmployees = d.MaxEmployees,
                }).ToList(),
        };
}

public record DeleteShiftStaffingQuotaCommand(Guid StoreId, Guid Id) : ICommand<AppResponse<bool>>;

public class DeleteShiftStaffingQuotaHandler(
    IRepository<ShiftStaffingQuota> quotaRepository
) : ICommandHandler<DeleteShiftStaffingQuotaCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(DeleteShiftStaffingQuotaCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var quota = await quotaRepository.GetSingleAsync(
                q => q.Id == request.Id && q.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            if (quota == null) return AppResponse<bool>.Error("Quota not found");

            await quotaRepository.DeleteAsync(quota, cancellationToken);
            return AppResponse<bool>.Success(true);
        }
        catch (Exception ex)
        {
            return AppResponse<bool>.Error(ex.Message);
        }
    }
}

/// <summary>
/// Chữ dùng chung cho thông báo ca / lịch / đổi ca: «12/11», «10/11–16/11», «Ca Sáng 07:00–11:00».
/// Ngày lịch (WorkSchedule.Date, ScheduleRegistration.Date, ShiftSwapRequest.*Date) là ngày tường VN — in thẳng.
/// </summary>
internal static class ScheduleNotifyText
{
    public static string Day(DateTime date) =>
        date.ToString("dd/MM", System.Globalization.CultureInfo.InvariantCulture);

    public static string Range(DateTime from, DateTime to) =>
        from.Date == to.Date ? Day(from) : $"{Day(from)}–{Day(to)}";

    /// <summary>«Ca Sáng»; tên đã có chữ «Ca» thì giữ nguyên (tránh «Ca Ca đêm»). Không có tên → null.</summary>
    public static string? ShiftName(ShiftTemplate? shift)
    {
        var name = shift?.Name?.Trim();
        if (string.IsNullOrEmpty(name)) return null;
        return name.StartsWith("Ca ", StringComparison.OrdinalIgnoreCase)
            || name.Equals("Ca", StringComparison.OrdinalIgnoreCase)
            ? name
            : $"Ca {name}";
    }

    public static string? Hours(TimeSpan? start, TimeSpan? end) =>
        start.HasValue && end.HasValue ? $@"{start.Value:hh\:mm}–{end.Value:hh\:mm}" : null;

    /// <summary>«Ca Sáng 07:00–11:00» / «Ngày nghỉ»; giờ ghi đè trên lịch ưu tiên hơn giờ mẫu ca.</summary>
    public static string Slot(ShiftTemplate? shift, TimeSpan? start = null, TimeSpan? end = null, bool isDayOff = false)
    {
        if (isDayOff) return "Ngày nghỉ";
        var parts = new List<string>();
        var name = ShiftName(shift);
        if (name != null) parts.Add(name);
        var hours = Hours(start ?? shift?.StartTime, end ?? shift?.EndTime);
        if (hours != null) parts.Add(hours);
        return parts.Count > 0 ? string.Join(' ', parts) : "Ca làm việc";
    }

    /// <summary>«Ca Sáng 12/11» — dùng khi cần ghép ca với ngày (đổi ca).</summary>
    public static string ShiftOnDay(ShiftTemplate? shift, DateTime date)
    {
        var name = ShiftName(shift) ?? Hours(shift?.StartTime, shift?.EndTime);
        return string.IsNullOrEmpty(name) ? $"ca {Day(date)}" : $"{name} {Day(date)}";
    }

    public static string EmployeeName(Employee? employee, string fallback = "Nhân viên")
    {
        var name = $"{employee?.LastName} {employee?.FirstName}".Trim();
        return string.IsNullOrWhiteSpace(name) ? fallback : name;
    }
}
