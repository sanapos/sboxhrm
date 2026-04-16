using Microsoft.AspNetCore.Identity;
using ZKTecoADMS.Application.DTOs.WorkSchedules;
using ZKTecoADMS.Application.Interfaces;
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
    ISystemNotificationService notificationService
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

            // Check if there's already a schedule for this user on this date
            var existingSchedules = await workScheduleRepository.GetAllAsync(
                ws => ws.EmployeeUserId == employee.Id && ws.Date.Date == request.Date.Date && ws.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            
            if (existingSchedules.Any())
            {
                return AppResponse<WorkScheduleDto>.Error("There's already a schedule for this user on this date");
            }

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
            var result = await workScheduleRepository.GetSingleAsync(
                filter: w => w.Id == created.Id && w.StoreId == request.StoreId,
                includeProperties: [nameof(WorkSchedule.Employee), nameof(WorkSchedule.Shift)], 
                cancellationToken: cancellationToken);
            
            try
            {
                if (employee.ApplicationUserId.HasValue)
                {
                    await notificationService.CreateAndSendAsync(
                        employee.ApplicationUserId.Value, NotificationType.Info,
                        "Lịch làm việc mới",
                        $"Bạn được xếp lịch làm việc ngày {request.Date:dd/MM/yyyy}",
                        relatedEntityId: created.Id, relatedEntityType: "WorkSchedule",
                        categoryCode: "attendance", storeId: request.StoreId);
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
    ISystemNotificationService notificationService
) : ICommandHandler<BulkCreateWorkSchedulesCommand, AppResponse<List<WorkScheduleDto>>>
{
    public async Task<AppResponse<List<WorkScheduleDto>>> Handle(BulkCreateWorkSchedulesCommand request, CancellationToken cancellationToken)
    {
        try
        {
            if (request.ShiftId.HasValue)
            {
                var shift = await shiftRepository.GetSingleAsync(
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
                var existingDates = existingSchedules.Select(ws => ws.Date.Date).ToHashSet();

                for (var date = request.StartDate.Date; date <= request.EndDate.Date; date = date.AddDays(1))
                {
                    if (!request.WorkDays.Contains(date.DayOfWeek)) continue;
                    if (existingDates.Contains(date)) continue;

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
            }

            // Reload all created schedules with includes
            var createdIds = schedulesToCreate.Select(s => s.Id).ToList();
            var results = await workScheduleRepository.GetAllAsync(
                filter: ws => createdIds.Contains(ws.Id) && ws.StoreId == request.StoreId,
                includeProperties: [nameof(WorkSchedule.Employee), nameof(WorkSchedule.Shift)],
                cancellationToken: cancellationToken);
            
            try
            {
                var affectedEmployeeIds = request.EmployeeUserIds.Distinct();
                var targetUserIds = new List<Guid>();
                foreach (var empId in affectedEmployeeIds)
                {
                    var emp = await employeeRepository.GetSingleAsync(
                        filter: e => e.Id == empId && e.StoreId == request.StoreId,
                        cancellationToken: cancellationToken);
                    if (emp?.ApplicationUserId.HasValue == true)
                        targetUserIds.Add(emp.ApplicationUserId.Value);
                }
                if (targetUserIds.Count > 0)
                {
                    await notificationService.CreateAndSendToUsersAsync(
                        targetUserIds, NotificationType.Info,
                        "Lịch làm việc mới",
                        $"Bạn được xếp lịch làm việc từ {request.StartDate:dd/MM/yyyy} đến {request.EndDate:dd/MM/yyyy}",
                        relatedEntityType: "WorkSchedule",
                        categoryCode: "attendance", storeId: request.StoreId);
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
    ISystemNotificationService notificationService
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

            workSchedule.ShiftId = request.ShiftId;
            workSchedule.StartTime = request.StartTime;
            workSchedule.EndTime = request.EndTime;
            workSchedule.IsDayOff = request.IsDayOff;
            workSchedule.Note = request.Note;

            await workScheduleRepository.UpdateAsync(workSchedule, cancellationToken);

            try
            {
                if (workSchedule.Employee?.ApplicationUserId.HasValue == true)
                {
                    await notificationService.CreateAndSendAsync(
                        workSchedule.Employee.ApplicationUserId.Value, NotificationType.Info,
                        "Cập nhật lịch làm việc",
                        $"Lịch làm việc ngày {workSchedule.Date:dd/MM/yyyy} đã được cập nhật",
                        relatedEntityId: workSchedule.Id, relatedEntityType: "WorkSchedule",
                        categoryCode: "attendance", storeId: request.StoreId);
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
    ISystemNotificationService notificationService
) : ICommandHandler<DeleteWorkScheduleCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(DeleteWorkScheduleCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var workSchedule = await workScheduleRepository.GetSingleAsync(
                filter: w => w.Id == request.Id && w.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            if (workSchedule == null)
            {
                return AppResponse<bool>.Error("Work schedule not found");
            }

            var employeeUserId = workSchedule.EmployeeUserId;
            var scheduleDate = workSchedule.Date;

            await workScheduleRepository.DeleteAsync(workSchedule, cancellationToken);

            // Notify employee about schedule removal
            try
            {
                await notificationService.CreateAndSendAsync(
                    targetUserId: employeeUserId,
                    type: NotificationType.Warning,
                    title: "Xóa lịch làm việc",
                    message: $"Lịch làm việc ngày {scheduleDate:dd/MM/yyyy} đã bị xóa.",
                    relatedEntityType: "WorkSchedule",
                    categoryCode: "attendance",
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

            var registration = new ScheduleRegistration
            {
                StoreId = request.StoreId,
                EmployeeUserId = employee.Id,
                Date = request.Date.Date,
                ShiftId = request.ShiftId,
                IsDayOff = request.IsDayOff,
                Note = request.Note,
                Status = ScheduleRegistrationStatus.Pending
            };

            var created = await registrationRepository.AddAsync(registration, cancellationToken);
            var result = await registrationRepository.GetSingleAsync(
                filter: r => r.Id == created.Id && r.StoreId == request.StoreId,
                includeProperties: [nameof(ScheduleRegistration.Employee), nameof(ScheduleRegistration.Shift)], 
                cancellationToken: cancellationToken);
            
            // Notify managers about new schedule registration
            try
            {
                var employeeName = employee.ApplicationUserId.HasValue 
                    ? $"{employee.LastName} {employee.FirstName}".Trim()
                    : "Nhân viên";
                var managers = await userManager.GetUsersInRoleAsync(nameof(Roles.Manager));
                var admins = await userManager.GetUsersInRoleAsync(nameof(Roles.Admin));
                var targetUsers = managers.Concat(admins)
                    .Where(u => u.StoreId == request.StoreId && u.Id != employee.ApplicationUserId)
                    .Select(u => u.Id)
                    .Distinct()
                    .ToList();
                if (targetUsers.Count > 0)
                {
                    await notificationService.CreateAndSendToUsersAsync(
                        targetUsers, NotificationType.ApprovalRequired,
                        "Đăng ký lịch làm việc mới",
                        $"{employeeName} đăng ký lịch ngày {request.Date:dd/MM/yyyy}",
                        relatedEntityId: created.Id, relatedEntityType: "ScheduleRegistration",
                        fromUserId: employee.ApplicationUserId, categoryCode: "attendance", storeId: request.StoreId);
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
    Guid RegistrationId) : ICommand<AppResponse<bool>>;

public class DeleteScheduleRegistrationHandler(
    IRepository<ScheduleRegistration> registrationRepository,
    IRepository<WorkSchedule> workScheduleRepository,
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

            var employeeUserId = registration.EmployeeUserId;
            var registrationDate = registration.Date;

            // If approved, also delete the associated work schedule
            if (registration.Status == ScheduleRegistrationStatus.Approved)
            {
                var workSchedules = await workScheduleRepository.GetAllAsync(
                    ws => ws.EmployeeUserId == registration.EmployeeUserId
                          && ws.Date.Date == registration.Date.Date
                          && ws.ShiftId == registration.ShiftId
                          && ws.StoreId == request.StoreId,
                    cancellationToken: cancellationToken);

                foreach (var ws in workSchedules)
                {
                    await workScheduleRepository.DeleteAsync(ws, cancellationToken);
                }
            }

            await registrationRepository.DeleteAsync(registration, cancellationToken);

            // Notify employee about registration deletion
            try
            {
                await notificationService.CreateAndSendAsync(
                    targetUserId: employeeUserId,
                    type: NotificationType.Warning,
                    title: "Xóa đăng ký lịch",
                    message: $"Đăng ký lịch ngày {registrationDate:dd/MM/yyyy} đã bị xóa.",
                    relatedEntityType: "WorkSchedule",
                    categoryCode: "attendance",
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

// Approve Schedule Registration Command
public record ApproveScheduleRegistrationCommand(
    Guid StoreId,
    Guid RequestId,
    Guid ApprovedById,
    bool IsApproved,
    string? RejectionReason) : ICommand<AppResponse<ScheduleRegistrationDto>>;

public class ApproveScheduleRegistrationHandler(
    IRepository<ScheduleRegistration> registrationRepository,
    IRepository<WorkSchedule> workScheduleRepository,
    ISystemNotificationService notificationService
) : ICommandHandler<ApproveScheduleRegistrationCommand, AppResponse<ScheduleRegistrationDto>>
{
    public async Task<AppResponse<ScheduleRegistrationDto>> Handle(ApproveScheduleRegistrationCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var registration = await registrationRepository.GetSingleAsync(
                filter: r => r.Id == request.RequestId && r.StoreId == request.StoreId,
                includeProperties: [nameof(ScheduleRegistration.Employee), nameof(ScheduleRegistration.Shift), nameof(ScheduleRegistration.ApprovedBy)], 
                cancellationToken: cancellationToken);
            
            if (registration == null)
            {
                return AppResponse<ScheduleRegistrationDto>.Error("Schedule registration not found");
            }

            if (registration.Status != ScheduleRegistrationStatus.Pending)
            {
                return AppResponse<ScheduleRegistrationDto>.Error("This registration has already been processed");
            }

            registration.Status = request.IsApproved ? ScheduleRegistrationStatus.Approved : ScheduleRegistrationStatus.Rejected;
            registration.ApprovedById = request.ApprovedById;
            registration.ApprovedDate = DateTime.UtcNow;
            registration.RejectionReason = request.IsApproved ? null : request.RejectionReason;

            // If approved, create or update the work schedule
            if (request.IsApproved)
            {
                var existingSchedule = await workScheduleRepository.GetSingleAsync(
                    filter: ws => ws.EmployeeUserId == registration.EmployeeUserId
                                  && ws.Date.Date == registration.Date.Date
                                  && ws.StoreId == request.StoreId,
                    cancellationToken: cancellationToken);

                if (existingSchedule != null)
                {
                    existingSchedule.ShiftId = registration.ShiftId;
                    existingSchedule.IsDayOff = registration.IsDayOff;
                    existingSchedule.Note = registration.Note;
                    await workScheduleRepository.UpdateAsync(existingSchedule, cancellationToken);
                }
                else
                {
                    var workSchedule = new WorkSchedule
                    {
                        StoreId = request.StoreId,
                        EmployeeUserId = registration.EmployeeUserId,
                        ShiftId = registration.ShiftId,
                        Date = registration.Date,
                        IsDayOff = registration.IsDayOff,
                        Note = registration.Note
                    };
                    await workScheduleRepository.AddAsync(workSchedule, cancellationToken);
                }
            }

            await registrationRepository.UpdateAsync(registration, cancellationToken);

            try
            {
                if (registration.Employee?.ApplicationUserId.HasValue == true)
                {
                    var statusText = request.IsApproved ? "được duyệt" : "bị từ chối";
                    var notifType = request.IsApproved ? NotificationType.Success : NotificationType.Warning;
                    var message = $"Đăng ký lịch ngày {registration.Date:dd/MM/yyyy} đã {statusText}";
                    if (!request.IsApproved && !string.IsNullOrEmpty(request.RejectionReason))
                        message += $". Lý do: {request.RejectionReason}";
                    await notificationService.CreateAndSendAsync(
                        registration.Employee.ApplicationUserId.Value, notifType,
                        "Kết quả đăng ký lịch",
                        message,
                        relatedEntityId: registration.Id, relatedEntityType: "ScheduleRegistration",
                        fromUserId: request.ApprovedById, categoryCode: "attendance", storeId: request.StoreId);
                }
            }
            catch { /* Notification failure should not affect main operation */ }
            
            return AppResponse<ScheduleRegistrationDto>.Success(registration.Adapt<ScheduleRegistrationDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<ScheduleRegistrationDto>.Error(ex.Message);
        }
    }
}

// Undo Schedule Registration Approval Command
public record UndoScheduleRegistrationApprovalCommand(
    Guid StoreId,
    Guid RegistrationId) : ICommand<AppResponse<bool>>;

public class UndoScheduleRegistrationApprovalHandler(
    IRepository<ScheduleRegistration> registrationRepository,
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

            // Set back to Pending
            registration.Status = ScheduleRegistrationStatus.Pending;
            registration.ApprovedById = null;
            registration.ApprovedDate = null;
            registration.RejectionReason = null;
            registration.UpdatedAt = DateTime.Now;
            await registrationRepository.UpdateAsync(registration, cancellationToken);

            // If was approved, delete the associated work schedule
            if (wasApproved)
            {
                var workSchedules = await workScheduleRepository.GetAllAsync(
                    ws => ws.EmployeeUserId == registration.EmployeeUserId
                          && ws.Date.Date == registration.Date.Date
                          && ws.ShiftId == registration.ShiftId
                          && ws.StoreId == request.StoreId,
                    cancellationToken: cancellationToken);

                foreach (var ws in workSchedules)
                {
                    await workScheduleRepository.DeleteAsync(ws, cancellationToken);
                }
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
                        "Hoàn tác duyệt lịch",
                        $"Đăng ký lịch ngày {registration.Date:dd/MM/yyyy} đã bị hoàn tác về trạng thái chờ duyệt",
                        relatedEntityId: registration.Id, relatedEntityType: "ScheduleRegistration",
                        categoryCode: "attendance", storeId: request.StoreId);
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
                "Nhắc nhở đăng ký lịch làm việc",
                $"Bạn chưa đăng ký lịch làm việc cho tuần {request.FromDate:dd/MM} - {request.ToDate:dd/MM/yyyy}. Vui lòng đăng ký sớm.",
                relatedEntityType: "WorkSchedule",
                categoryCode: "attendance", storeId: request.StoreId,
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

            var msg = !string.IsNullOrEmpty(request.Message) ? request.Message
                : $"Cần bổ sung nhân viên cho ca {shift.Name} ({shift.StartTime:hh\\:mm}-{shift.EndTime:hh\\:mm}) ngày {request.Date:dd/MM/yyyy}. Vui lòng đăng ký nếu có thể.";

            await notificationService.CreateAndSendToUsersAsync(
                userIds, NotificationType.Info,
                $"Yêu cầu bổ sung ca {shift.Name}",
                msg,
                relatedEntityType: "WorkSchedule",
                categoryCode: "attendance", storeId: request.StoreId,
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
    int MinEmployees, int MaxEmployees, int WarningThreshold
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

            if (existing != null)
            {
                existing.MinEmployees = request.MinEmployees;
                existing.MaxEmployees = request.MaxEmployees;
                existing.WarningThreshold = request.WarningThreshold;
                existing.UpdatedAt = DateTime.Now;
                await quotaRepository.UpdateAsync(existing, cancellationToken);

                return AppResponse<ShiftStaffingQuotaDto>.Success(new ShiftStaffingQuotaDto
                {
                    Id = existing.Id, ShiftTemplateId = existing.ShiftTemplateId,
                    ShiftName = shift.Name, Department = existing.Department,
                    MinEmployees = existing.MinEmployees, MaxEmployees = existing.MaxEmployees,
                    WarningThreshold = existing.WarningThreshold,
                });
            }

            var quota = new ShiftStaffingQuota
            {
                StoreId = request.StoreId,
                ShiftTemplateId = request.ShiftTemplateId,
                Department = request.Department,
                MinEmployees = request.MinEmployees,
                MaxEmployees = request.MaxEmployees,
                WarningThreshold = request.WarningThreshold,
            };
            var created = await quotaRepository.AddAsync(quota, cancellationToken);

            return AppResponse<ShiftStaffingQuotaDto>.Success(new ShiftStaffingQuotaDto
            {
                Id = created.Id, ShiftTemplateId = created.ShiftTemplateId,
                ShiftName = shift.Name, Department = created.Department,
                MinEmployees = created.MinEmployees, MaxEmployees = created.MaxEmployees,
                WarningThreshold = created.WarningThreshold,
            });
        }
        catch (Exception ex)
        {
            return AppResponse<ShiftStaffingQuotaDto>.Error(ex.Message);
        }
    }
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
