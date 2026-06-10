using Microsoft.AspNetCore.Identity;
using ZKTecoADMS.Application.DTOs.WorkSchedules;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Interfaces;
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

            var existingSchedules = await workScheduleRepository.GetAllAsync(
                ws => ws.EmployeeUserId == employee.Id && ws.Date.Date == request.Date.Date && ws.StoreId == request.StoreId,
                cancellationToken: cancellationToken);

            if (WorkScheduleDuplicateHelper.AnyConflict(
                    existingSchedules, employee.Id, request.Date, request.ShiftId, request.IsDayOff))
            {
                return AppResponse<WorkScheduleDto>.Error(
                    request.IsDayOff
                        ? "Nhân viên đã có ngày nghỉ trong ngày này"
                        : "Nhân viên đã được xếp ca này trong ngày");
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
                var existingKeys = existingSchedules
                    .Select(ws => (ws.Date.Date, ws.ShiftId))
                    .ToHashSet();

                for (var date = request.StartDate.Date; date <= request.EndDate.Date; date = date.AddDays(1))
                {
                    if (!request.WorkDays.Contains(date.DayOfWeek)) continue;
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
                        filter: e => (e.Id == empId || e.ApplicationUserId == empId) && e.StoreId == request.StoreId,
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
                includeProperties: [nameof(WorkSchedule.Employee)],
                cancellationToken: cancellationToken);
            if (workSchedule == null)
            {
                return AppResponse<bool>.Error("Work schedule not found");
            }

            var scheduleDate = workSchedule.Date;
            var notifyUserId = workSchedule.Employee?.ApplicationUserId;

            await workScheduleRepository.DeleteAsync(workSchedule, cancellationToken);

            // Notify employee about schedule removal
            try
            {
                if (!notifyUserId.HasValue) return AppResponse<bool>.Success(true);

                await notificationService.CreateAndSendAsync(
                    targetUserId: notifyUserId.Value,
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
                    await notificationService.CreateAndSendToUsersAsync(
                        firstApprover, NotificationType.ApprovalRequired,
                        "Đăng ký lịch làm việc mới",
                        $"{employeeName} đăng ký lịch ngày {request.Date:dd/MM/yyyy}" +
                        (approvalLevels > 1 ? $" (cấp 1/{approvalLevels})" : ""),
                        relatedEntityId: created.Id, relatedEntityType: "ScheduleRegistration",
                        fromUserId: employee.ApplicationUserId, categoryCode: "approval",
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
    Guid RegistrationId) : ICommand<AppResponse<bool>>;

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
            var employee = await employeeRepository.GetSingleAsync(
                filter: e => e.Id == registration.EmployeeUserId && e.StoreId == request.StoreId,
                cancellationToken: cancellationToken);

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

            var approvalRecords = await scheduleApprovalRecordRepository.GetAllAsync(
                r => r.ScheduleRegistrationId == registration.Id,
                cancellationToken: cancellationToken);
            foreach (var ar in approvalRecords)
                await scheduleApprovalRecordRepository.DeleteAsync(ar, cancellationToken);

            await registrationRepository.DeleteAsync(registration, cancellationToken);

            // Notify employee about registration deletion
            try
            {
                if (employee?.ApplicationUserId.HasValue == true)
                {
                    await notificationService.CreateAndSendAsync(
                        targetUserId: employee.ApplicationUserId.Value,
                        type: NotificationType.Warning,
                        title: "Xóa đăng ký lịch",
                        message: $"Đăng ký lịch ngày {registrationDate:dd/MM/yyyy} đã bị xóa.",
                        relatedEntityType: "WorkSchedule",
                        categoryCode: "attendance",
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
                    nameof(ScheduleRegistration.ApprovedBy),
                    nameof(ScheduleRegistration.ApprovalRecords)
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

            if (currentRecord == null)
                return AppResponse<ScheduleRegistrationDto>.Error("Không còn bước duyệt nào cần xử lý");

            var approver = await userManager.FindByIdAsync(request.ApprovedById.ToString());
            var isAdmin = approver?.Role is "Admin" or "SuperAdmin";
            var isAssigned = currentRecord.AssignedUserId == request.ApprovedById;
            if (!isAdmin && !isAssigned)
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
                        await notificationService.CreateAndSendAsync(
                            registration.Employee.ApplicationUserId.Value, NotificationType.Warning,
                            "Đăng ký lịch bị từ chối",
                            $"Đăng ký lịch ngày {registration.Date:dd/MM/yyyy} bị từ chối ở cấp {currentRecord.StepOrder}/{registration.TotalApprovalLevels}. " +
                            (string.IsNullOrEmpty(request.RejectionReason) ? "" : $"Lý do: {request.RejectionReason}"),
                            relatedEntityId: registration.Id, relatedEntityType: "ScheduleRegistration",
                            fromUserId: request.ApprovedById, categoryCode: "attendance", storeId: request.StoreId);
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

                await ApplyApprovedScheduleAsync(registration, request.StoreId, workScheduleRepository, cancellationToken);
                await registrationRepository.UpdateAsync(registration, cancellationToken);

                try
                {
                    if (registration.Employee?.ApplicationUserId.HasValue == true)
                    {
                        await notificationService.CreateAndSendAsync(
                            registration.Employee.ApplicationUserId.Value, NotificationType.Success,
                            "Đăng ký lịch đã duyệt",
                            registration.TotalApprovalLevels > 1
                                ? $"Đăng ký lịch ngày {registration.Date:dd/MM/yyyy} đã được phê duyệt qua {registration.TotalApprovalLevels} cấp"
                                : $"Đăng ký lịch ngày {registration.Date:dd/MM/yyyy} đã được duyệt",
                            relatedEntityId: registration.Id, relatedEntityType: "ScheduleRegistration",
                            fromUserId: request.ApprovedById, categoryCode: "approval", storeId: request.StoreId);
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
                        await notificationService.CreateAndSendAsync(
                            nextPending.AssignedUserId.Value, NotificationType.ApprovalRequired,
                            "Đăng ký lịch cần duyệt",
                            $"Đăng ký lịch ngày {registration.Date:dd/MM/yyyy} - cấp {nextPending.StepOrder}/{registration.TotalApprovalLevels}",
                            relatedEntityId: registration.Id, relatedEntityType: "ScheduleRegistration",
                            fromUserId: request.ApprovedById, categoryCode: "approval", storeId: request.StoreId);
                    }

                    if (registration.Employee?.ApplicationUserId.HasValue == true)
                    {
                        await notificationService.CreateAndSendAsync(
                            registration.Employee.ApplicationUserId.Value, NotificationType.Info,
                            "Tiến trình duyệt lịch",
                            $"Đăng ký lịch đã được duyệt cấp {currentRecord.StepOrder}/{registration.TotalApprovalLevels}. Đang chờ cấp {nextPending.StepOrder}",
                            relatedEntityId: registration.Id, relatedEntityType: "ScheduleRegistration",
                            fromUserId: request.ApprovedById, categoryCode: "approval", storeId: request.StoreId);
                    }
                }
                catch { }
            }

            var refreshed = await registrationRepository.GetSingleAsync(
                filter: r => r.Id == registration.Id && r.StoreId == request.StoreId,
                includeProperties: [
                    nameof(ScheduleRegistration.Employee),
                    nameof(ScheduleRegistration.Shift),
                    nameof(ScheduleRegistration.ApprovalRecords)
                ],
                cancellationToken: cancellationToken);

            return AppResponse<ScheduleRegistrationDto>.Success(refreshed!.Adapt<ScheduleRegistrationDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<ScheduleRegistrationDto>.Error(ex.Message);
        }
    }

    private static async Task ApplyApprovedScheduleAsync(
        ScheduleRegistration registration,
        Guid storeId,
        IRepository<WorkSchedule> workScheduleRepository,
        CancellationToken cancellationToken)
    {
        var daySchedules = await workScheduleRepository.GetAllAsync(
            ws => ws.EmployeeUserId == registration.EmployeeUserId
                  && ws.Date.Date == registration.Date.Date
                  && ws.StoreId == storeId,
            cancellationToken: cancellationToken);

        var existingSchedule = daySchedules.FirstOrDefault(ws =>
            WorkScheduleDuplicateHelper.ConflictsWith(
                ws, registration.EmployeeUserId, registration.Date, registration.ShiftId, registration.IsDayOff));

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
                StoreId = storeId,
                EmployeeUserId = registration.EmployeeUserId,
                ShiftId = registration.ShiftId,
                Date = registration.Date,
                IsDayOff = registration.IsDayOff,
                Note = registration.Note
            };
            await workScheduleRepository.AddAsync(workSchedule, cancellationToken);
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
                        categoryCode: "approval", storeId: request.StoreId);
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
