using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.AttendanceCorrections;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Commands.AttendanceCorrections;

// Create Attendance Correction Request Command
public record CreateAttendanceCorrectionCommand(
    Guid StoreId,
    Guid EmployeeUserId,
    string? EmployeeName,
    string? EmployeeCode,
    Guid? AttendanceId,
    CorrectionAction Action,
    DateTime? OldDate,
    TimeSpan? OldTime,
    DateTime? NewDate,
    TimeSpan? NewTime,
    string? Reason) : ICommand<AppResponse<AttendanceCorrectionRequestDto>>;

public class CreateAttendanceCorrectionHandler(
    IRepository<AttendanceCorrectionRequest> correctionRepository,
    IRepository<ApprovalRecord> approvalRecordRepository,
    UserManager<ApplicationUser> userManager,
    IRepository<Attendance> attendanceRepository,
    IRepository<Employee> employeeRepository,
    IRepository<AppSettings> appSettingsRepository,
    ISystemNotificationService notificationService
) : ICommandHandler<CreateAttendanceCorrectionCommand, AppResponse<AttendanceCorrectionRequestDto>>
{
    public async Task<AppResponse<AttendanceCorrectionRequestDto>> Handle(CreateAttendanceCorrectionCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var user = await userManager.FindByIdAsync(request.EmployeeUserId.ToString());
            if (user == null)
                return AppResponse<AttendanceCorrectionRequestDto>.Error("User not found");

            string? oldDevice = null;
            string? oldType = null;

            if (request.Action != CorrectionAction.Add && request.AttendanceId.HasValue)
            {
                var attendance = await attendanceRepository.GetByIdAsync(request.AttendanceId.Value,
                    includeProperties: ["Device"], cancellationToken: cancellationToken);
                if (attendance == null)
                    return AppResponse<AttendanceCorrectionRequestDto>.Error("Attendance record not found");
                oldDevice = attendance.Device?.Id.ToString();
                oldType = attendance.AttendanceState.ToString();
            }

            // Read approval levels from settings (default 1)
            var approvalLevels = await GetApprovalLevelsAsync(request.StoreId, cancellationToken);

            var correction = new AttendanceCorrectionRequest
            {
                StoreId = request.StoreId,
                EmployeeUserId = request.EmployeeUserId,
                EmployeeName = request.EmployeeName,
                EmployeeCode = request.EmployeeCode,
                AttendanceId = request.AttendanceId,
                Action = request.Action,
                OldDate = request.OldDate,
                OldTime = request.OldTime,
                OldDevice = oldDevice,
                OldType = oldType,
                NewDate = request.NewDate,
                NewTime = request.NewTime,
                Reason = request.Reason,
                Status = CorrectionStatus.Pending,
                TotalApprovalLevels = approvalLevels,
                CurrentApprovalStep = 0
            };

            var created = await correctionRepository.AddAsync(correction, cancellationToken);

            // Build approval chain and create ApprovalRecord for each level
            var approvalChain = await BuildApprovalChainAsync(request.EmployeeUserId, request.StoreId, approvalLevels, cancellationToken);
            foreach (var record in approvalChain)
            {
                record.CorrectionRequestId = created.Id;
                record.StoreId = request.StoreId;
                await approvalRecordRepository.AddAsync(record, cancellationToken);
            }

            var result = await correctionRepository.GetByIdAsync(created.Id,
                [nameof(AttendanceCorrectionRequest.EmployeeUser)],
                cancellationToken: cancellationToken);

            // Send notification to first-level approver(s) only
            try
            {
                var actionText = request.Action switch
                {
                    CorrectionAction.Add => "thêm",
                    CorrectionAction.Edit => "sửa",
                    CorrectionAction.Delete => "xóa",
                    _ => "chỉnh sửa"
                };

                var firstLevelTargets = approvalChain
                    .Where(r => r.StepOrder == 1 && r.AssignedUserId.HasValue)
                    .Select(r => r.AssignedUserId!.Value)
                    .Where(id => id != request.EmployeeUserId)
                    .Distinct()
                    .ToList();

                if (firstLevelTargets.Count > 0)
                {
                    await notificationService.CreateAndSendToUsersAsync(
                        firstLevelTargets, NotificationType.ApprovalRequired,
                        "Yêu cầu chỉnh công mới",
                        $"{request.EmployeeName ?? "Nhân viên"} yêu cầu {actionText} chấm công" +
                        (approvalLevels > 1 ? $" (cấp 1/{approvalLevels})" : ""),
                        relatedEntityId: created.Id, relatedEntityType: "AttendanceCorrection",
                        fromUserId: request.EmployeeUserId, categoryCode: "approval", storeId: request.StoreId);
                }
            }
            catch { /* Notification failure should not affect main operation */ }

            return AppResponse<AttendanceCorrectionRequestDto>.Success(result!.Adapt<AttendanceCorrectionRequestDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<AttendanceCorrectionRequestDto>.Error(ex.Message);
        }
    }

    /// <summary>
    /// Read attendance_approval_levels setting from AppSettings
    /// </summary>
    private async Task<int> GetApprovalLevelsAsync(Guid storeId, CancellationToken ct)
    {
        try
        {
            var setting = await appSettingsRepository.GetSingleAsync(
                s => s.Key == "attendance_approval_levels" && s.StoreId == storeId, cancellationToken: ct);
            if (setting?.Value != null && int.TryParse(setting.Value, out var levels) && levels >= 1 && levels <= 5)
                return levels;
        }
        catch { }
        return 1; // default 1 level
    }

    /// <summary>
    /// Build approval chain based on DirectManagerEmployeeId hierarchy
    /// Level 1: Direct manager
    /// Level 2: Manager's manager (grandparent)
    /// Level 3: Admin
    /// Fallback: Admin for any level without a specific manager
    /// </summary>
    private async Task<List<ApprovalRecord>> BuildApprovalChainAsync(
        Guid employeeUserId, Guid storeId, int totalLevels, CancellationToken ct)
    {
        var records = new List<ApprovalRecord>();

        // Find the employee
        var employee = await employeeRepository.GetSingleAsync(
            e => e.ApplicationUserId == employeeUserId, cancellationToken: ct);

        // Walk up the manager chain
        var managerChain = new List<(Guid UserId, string Name)>();
        if (employee?.DirectManagerEmployeeId != null)
        {
            var mgr = await employeeRepository.GetSingleAsync(
                e => e.Id == employee.DirectManagerEmployeeId.Value, cancellationToken: ct);
            if (mgr?.ApplicationUserId != null)
            {
                var mgrUser = await userManager.FindByIdAsync(mgr.ApplicationUserId.Value.ToString());
                if (mgrUser != null)
                    managerChain.Add((mgrUser.Id, mgrUser.FullName ?? mgrUser.Email ?? "Manager"));

                // Grandparent manager
                if (mgr.DirectManagerEmployeeId != null)
                {
                    var gp = await employeeRepository.GetSingleAsync(
                        e => e.Id == mgr.DirectManagerEmployeeId.Value, cancellationToken: ct);
                    if (gp?.ApplicationUserId != null)
                    {
                        var gpUser = await userManager.FindByIdAsync(gp.ApplicationUserId.Value.ToString());
                        if (gpUser != null)
                            managerChain.Add((gpUser.Id, gpUser.FullName ?? gpUser.Email ?? "Director"));
                    }
                }
            }
        }

        // Get admin users for this store (fallback + explicit level)
        var admins = await userManager.Users
            .Where(u => u.IsActive && u.Role == "Admin" && u.StoreId == storeId && u.Id != employeeUserId)
            .ToListAsync(ct);
        var adminFirst = admins.FirstOrDefault();

        var levelNames = new[] { "Quản lý trực tiếp", "Quản lý cấp cao", "Admin", "Cấp 4", "Cấp 5" };

        for (int level = 1; level <= totalLevels; level++)
        {
            Guid? assignedUserId = null;
            string? assignedUserName = null;

            if (level - 1 < managerChain.Count)
            {
                // Use manager from chain
                assignedUserId = managerChain[level - 1].UserId;
                assignedUserName = managerChain[level - 1].Name;
            }
            else if (adminFirst != null)
            {
                // Fallback to admin
                assignedUserId = adminFirst.Id;
                assignedUserName = adminFirst.FullName ?? adminFirst.Email;
            }

            records.Add(new ApprovalRecord
            {
                StepOrder = level,
                StepName = level <= levelNames.Length ? levelNames[level - 1] : $"Cấp {level}",
                AssignedUserId = assignedUserId,
                AssignedUserName = assignedUserName,
                Status = ApprovalStatus.Pending
            });
        }

        return records;
    }
}

// Approve Attendance Correction Command (Multi-level)
public record ApproveAttendanceCorrectionCommand(
    Guid StoreId,
    Guid RequestId,
    Guid ApprovedById,
    bool IsApproved,
    string? ApproverNote) : ICommand<AppResponse<AttendanceCorrectionRequestDto>>;

public class ApproveAttendanceCorrectionHandler(
    IRepository<AttendanceCorrectionRequest> correctionRepository,
    IRepository<ApprovalRecord> approvalRecordRepository,
    IRepository<Attendance> attendanceRepository,
    IRepository<Employee> employeeRepository,
    IRepository<Device> deviceRepository,
    IRepository<DeviceUser> deviceUserRepository,
    UserManager<ApplicationUser> userManager,
    ISystemNotificationService notificationService
) : ICommandHandler<ApproveAttendanceCorrectionCommand, AppResponse<AttendanceCorrectionRequestDto>>
{
    public async Task<AppResponse<AttendanceCorrectionRequestDto>> Handle(ApproveAttendanceCorrectionCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var correction = await correctionRepository.GetSingleAsync(
                c => c.Id == request.RequestId && c.StoreId == request.StoreId,
                includeProperties: [nameof(AttendanceCorrectionRequest.EmployeeUser), nameof(AttendanceCorrectionRequest.ApprovedBy)],
                cancellationToken: cancellationToken);

            if (correction == null)
                return AppResponse<AttendanceCorrectionRequestDto>.Error("Correction request not found");

            if (correction.Status != CorrectionStatus.Pending)
                return AppResponse<AttendanceCorrectionRequestDto>.Error("Yêu cầu này đã được xử lý");

            // Get all approval records for this request
            var allRecords = (await approvalRecordRepository.GetAllAsync(
                r => r.CorrectionRequestId == request.RequestId,
                cancellationToken: cancellationToken))
                .OrderBy(r => r.StepOrder).ToList();

            // Find the current pending step
            var currentRecord = allRecords.FirstOrDefault(r => r.Status == ApprovalStatus.Pending);

            // If no approval records exist (legacy/migration), create one
            if (allRecords.Count == 0)
            {
                currentRecord = new ApprovalRecord
                {
                    CorrectionRequestId = request.RequestId,
                    StepOrder = 1,
                    StepName = "Phê duyệt",
                    AssignedUserId = request.ApprovedById,
                    Status = ApprovalStatus.Pending,
                    StoreId = request.StoreId
                };
                await approvalRecordRepository.AddAsync(currentRecord, cancellationToken);
                allRecords.Add(currentRecord);
            }

            if (currentRecord == null)
                return AppResponse<AttendanceCorrectionRequestDto>.Error("Không còn bước duyệt nào cần xử lý");

            // Verify permission: only assigned user, admin, or any manager can approve
            var approver = await userManager.FindByIdAsync(request.ApprovedById.ToString());
            var isAdmin = approver?.Role == "Admin";
            var isAssigned = currentRecord.AssignedUserId == request.ApprovedById;

            if (!isAdmin && !isAssigned)
            {
                // Check if approver is a manager/department head (can approve as delegate)
                var isManager = approver?.Role == "Manager" || approver?.Role == "DepartmentHead";
                if (!isManager)
                    return AppResponse<AttendanceCorrectionRequestDto>.Error("Bạn không có quyền duyệt bước này");
            }

            // Record the approval/rejection
            currentRecord.ActualUserId = request.ApprovedById;
            currentRecord.ActualUserName = approver?.FullName ?? approver?.Email;
            currentRecord.Status = request.IsApproved ? ApprovalStatus.Approved : ApprovalStatus.Rejected;
            currentRecord.Note = request.ApproverNote;
            currentRecord.ActionDate = DateTime.UtcNow;
            await approvalRecordRepository.UpdateAsync(currentRecord, cancellationToken);

            if (!request.IsApproved)
            {
                // REJECTED: Immediately reject the whole request
                correction.Status = CorrectionStatus.Rejected;
                correction.ApprovedById = request.ApprovedById;
                correction.ApprovedDate = DateTime.UtcNow;
                correction.ApproverNote = request.ApproverNote;
                await correctionRepository.UpdateAsync(correction, cancellationToken);

                // Notify employee
                try
                {
                    await notificationService.CreateAndSendAsync(
                        correction.EmployeeUserId, NotificationType.Warning,
                        "Yêu cầu chỉnh công bị từ chối",
                        $"Yêu cầu chỉnh sửa chấm công bị từ chối ở cấp {currentRecord.StepOrder}/{correction.TotalApprovalLevels}. Ghi chú: {request.ApproverNote}",
                        relatedEntityId: correction.Id, relatedEntityType: "AttendanceCorrection",
                        fromUserId: request.ApprovedById, categoryCode: "approval", storeId: request.StoreId);
                }
                catch { }

                return AppResponse<AttendanceCorrectionRequestDto>.Success(correction.Adapt<AttendanceCorrectionRequestDto>());
            }

            // APPROVED this step
            correction.CurrentApprovalStep = currentRecord.StepOrder;

            // Check if all steps are completed
            var nextPending = allRecords.FirstOrDefault(r => r.StepOrder > currentRecord.StepOrder && r.Status == ApprovalStatus.Pending);

            if (nextPending == null)
            {
                // All levels approved → Final approval
                correction.Status = CorrectionStatus.Approved;
                correction.ApprovedById = request.ApprovedById;
                correction.ApprovedDate = DateTime.UtcNow;
                correction.ApproverNote = request.ApproverNote;

                // Apply the actual correction
                await ApplyCorrectionAsync(correction, cancellationToken);
                await correctionRepository.UpdateAsync(correction, cancellationToken);

                // Notify employee: approved
                try
                {
                    await notificationService.CreateAndSendAsync(
                        correction.EmployeeUserId, NotificationType.Success,
                        "Yêu cầu chỉnh công đã duyệt",
                        correction.TotalApprovalLevels > 1
                            ? $"Yêu cầu chỉnh sửa chấm công đã được phê duyệt qua {correction.TotalApprovalLevels} cấp"
                            : "Yêu cầu chỉnh sửa chấm công của bạn đã được phê duyệt",
                        relatedEntityId: correction.Id, relatedEntityType: "AttendanceCorrection",
                        fromUserId: request.ApprovedById, categoryCode: "approval", storeId: request.StoreId);
                }
                catch { }
            }
            else
            {
                // Move to next level
                await correctionRepository.UpdateAsync(correction, cancellationToken);

                // Notify next approver
                try
                {
                    if (nextPending.AssignedUserId.HasValue)
                    {
                        await notificationService.CreateAndSendAsync(
                            nextPending.AssignedUserId, NotificationType.ApprovalRequired,
                            "Yêu cầu chỉnh công cần duyệt",
                            $"{correction.EmployeeName ?? "Nhân viên"} yêu cầu chỉnh công - cấp {nextPending.StepOrder}/{correction.TotalApprovalLevels}",
                            relatedEntityId: correction.Id, relatedEntityType: "AttendanceCorrection",
                            fromUserId: request.ApprovedById, categoryCode: "approval", storeId: request.StoreId);
                    }
                }
                catch { }

                // Also notify employee about step progress
                try
                {
                    await notificationService.CreateAndSendAsync(
                        correction.EmployeeUserId, NotificationType.Info,
                        "Chỉnh công: duyệt cấp " + currentRecord.StepOrder,
                        $"Yêu cầu đã được duyệt cấp {currentRecord.StepOrder}/{correction.TotalApprovalLevels}. Đang chờ cấp {nextPending.StepOrder}",
                        relatedEntityId: correction.Id, relatedEntityType: "AttendanceCorrection",
                        fromUserId: request.ApprovedById, categoryCode: "approval", storeId: request.StoreId);
                }
                catch { }
            }

            return AppResponse<AttendanceCorrectionRequestDto>.Success(correction.Adapt<AttendanceCorrectionRequestDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<AttendanceCorrectionRequestDto>.Error(ex.Message);
        }
    }

    private async Task ApplyCorrectionAsync(
        AttendanceCorrectionRequest correction, 
        CancellationToken cancellationToken)
    {
        switch (correction.Action)
        {
            case CorrectionAction.Add:
                if (correction.NewDate.HasValue && correction.NewTime.HasValue)
                {
                    // Look up Employee for this user
                    var employee = await employeeRepository.GetSingleAsync(
                        e => e.ApplicationUserId == correction.EmployeeUserId,
                        cancellationToken: cancellationToken);

                    // Look up DeviceUser to get proper UID (PIN) and device name
                    DeviceUser? deviceUser = null;
                    if (employee != null)
                    {
                        deviceUser = await deviceUserRepository.GetSingleAsync(
                            du => du.EmployeeId == employee.Id,
                            cancellationToken: cancellationToken);
                    }

                    // Determine DeviceId: prefer DeviceUser's device, fallback to store device
                    Guid deviceId;
                    if (deviceUser != null)
                    {
                        deviceId = deviceUser.DeviceId;
                    }
                    else
                    {
                        var device = await deviceRepository.GetSingleAsync(
                            d => d.StoreId == correction.StoreId,
                            cancellationToken: cancellationToken);
                        deviceId = device?.Id ?? Guid.Empty;
                        if (deviceId == Guid.Empty) break;
                    }

                    // PIN: use DeviceUser.Pin (actual device UID), fallback to EmployeeCode
                    var pin = deviceUser?.Pin ?? correction.EmployeeCode;
                    if (string.IsNullOrEmpty(pin))
                        pin = employee?.EmployeeCode ?? "0";

                    // WorkCode: employee name (max 10 chars)
                    string? workCode = null;
                    if (employee != null)
                    {
                        var empName = $"{employee.LastName} {employee.FirstName}".Trim();
                        workCode = empName.Length > 10 ? empName.Substring(0, 10) : empName;
                    }

                    var newAttendance = new Attendance
                    {
                        Id = Guid.NewGuid(),
                        EmployeeId = deviceUser?.Id, // Link to DeviceUser for proper DeviceUserName
                        DeviceId = deviceId,
                        PIN = pin,
                        AttendanceTime = correction.NewDate.Value.Date.Add(correction.NewTime.Value),
                        VerifyMode = VerifyModes.Manual,
                        AttendanceState = AttendanceStates.CheckIn,
                        WorkCode = workCode,
                        Note = $"Duyệt thêm chấm công [YC:{correction.Id}]",
                        CreatedAt = DateTime.UtcNow
                    };
                    await attendanceRepository.AddAsync(newAttendance, cancellationToken);
                    correction.AttendanceId = newAttendance.Id;
                }
                break;

            case CorrectionAction.Edit:
                if (correction.AttendanceId.HasValue)
                {
                    var attendance = await attendanceRepository.GetByIdAsync(correction.AttendanceId.Value, cancellationToken: cancellationToken);
                    if (attendance != null && correction.NewDate.HasValue && correction.NewTime.HasValue)
                    {
                        attendance.AttendanceTime = correction.NewDate.Value.Date.Add(correction.NewTime.Value);
                        attendance.Note = $"Điều chỉnh giờ chấm công [YC:{correction.Id}]";
                        await attendanceRepository.UpdateAsync(attendance, cancellationToken);
                    }
                }
                break;

            case CorrectionAction.Delete:
                if (correction.AttendanceId.HasValue)
                {
                    var attendance = await attendanceRepository.GetByIdAsync(correction.AttendanceId.Value, cancellationToken: cancellationToken);
                    if (attendance != null)
                    {
                        await attendanceRepository.DeleteAsync(attendance, cancellationToken);
                    }
                }
                break;
        }
    }
}

// Delete Attendance Correction Command
public record DeleteAttendanceCorrectionCommand(Guid StoreId, Guid Id) : ICommand<AppResponse<bool>>;

public class DeleteAttendanceCorrectionHandler(
    IRepository<AttendanceCorrectionRequest> correctionRepository
) : ICommandHandler<DeleteAttendanceCorrectionCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(DeleteAttendanceCorrectionCommand request, CancellationToken cancellationToken)
    {
        try
        {
            // Filter by StoreId for multi-tenant data isolation
            var correction = await correctionRepository.GetSingleAsync(
                c => c.Id == request.Id && c.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            if (correction == null)
            {
                return AppResponse<bool>.Error("Correction request not found");
            }

            if (correction.Status == CorrectionStatus.Approved)
            {
                return AppResponse<bool>.Error("Không thể xóa yêu cầu đã duyệt. Hãy hoàn duyệt trước.");
            }

            await correctionRepository.DeleteAsync(correction, cancellationToken);
            
            return AppResponse<bool>.Success(true);
        }
        catch (Exception ex)
        {
            return AppResponse<bool>.Error(ex.Message);
        }
    }
}

// Undo Approve Attendance Correction Command
public record UndoApproveAttendanceCorrectionCommand(
    Guid StoreId,
    Guid RequestId,
    Guid UserId) : ICommand<AppResponse<AttendanceCorrectionRequestDto>>;

public class UndoApproveAttendanceCorrectionHandler(
    IRepository<AttendanceCorrectionRequest> correctionRepository,
    IRepository<ApprovalRecord> approvalRecordRepository,
    IRepository<Attendance> attendanceRepository,
    ISystemNotificationService notificationService
) : ICommandHandler<UndoApproveAttendanceCorrectionCommand, AppResponse<AttendanceCorrectionRequestDto>>
{
    public async Task<AppResponse<AttendanceCorrectionRequestDto>> Handle(UndoApproveAttendanceCorrectionCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var correction = await correctionRepository.GetSingleAsync(
                c => c.Id == request.RequestId && c.StoreId == request.StoreId,
                includeProperties: [nameof(AttendanceCorrectionRequest.EmployeeUser), nameof(AttendanceCorrectionRequest.ApprovedBy)],
                cancellationToken: cancellationToken);

            if (correction == null)
                return AppResponse<AttendanceCorrectionRequestDto>.Error("Không tìm thấy yêu cầu");

            if (correction.Status != CorrectionStatus.Approved)
                return AppResponse<AttendanceCorrectionRequestDto>.Error("Chỉ có thể hoàn duyệt yêu cầu đã duyệt");

            // Revert the attendance change
            await RevertCorrectionAsync(correction, attendanceRepository, cancellationToken);

            correction.Status = CorrectionStatus.Pending;
            correction.ApprovedById = null;
            correction.ApprovedDate = null;
            correction.ApproverNote = null;
            correction.CurrentApprovalStep = 0;

            await correctionRepository.UpdateAsync(correction, cancellationToken);

            // Reset all approval records to Pending
            try
            {
                var allRecords = await approvalRecordRepository.GetAllAsync(
                    r => r.CorrectionRequestId == request.RequestId, cancellationToken: cancellationToken);
                foreach (var record in allRecords)
                {
                    record.Status = ApprovalStatus.Pending;
                    record.ActualUserId = null;
                    record.ActualUserName = null;
                    record.Note = null;
                    record.ActionDate = null;
                    await approvalRecordRepository.UpdateAsync(record, cancellationToken);
                }
            }
            catch { }

            try
            {
                await notificationService.CreateAndSendAsync(
                    correction.EmployeeUserId, NotificationType.Warning,
                    "Yêu cầu chỉnh công hoàn duyệt",
                    "Yêu cầu chỉnh sửa chấm công đã được hoàn duyệt về trạng thái chờ",
                    relatedEntityId: correction.Id, relatedEntityType: "AttendanceCorrection",
                    fromUserId: request.UserId, categoryCode: "approval", storeId: request.StoreId);
            }
            catch { /* Notification failure should not affect main operation */ }

            return AppResponse<AttendanceCorrectionRequestDto>.Success(correction.Adapt<AttendanceCorrectionRequestDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<AttendanceCorrectionRequestDto>.Error(ex.Message);
        }
    }

    private async Task RevertCorrectionAsync(
        AttendanceCorrectionRequest correction,
        IRepository<Attendance> attendanceRepository,
        CancellationToken cancellationToken)
    {
        switch (correction.Action)
        {
            case CorrectionAction.Add:
                // If we added an attendance on approval, delete it now
                if (correction.AttendanceId.HasValue)
                {
                    var attendance = await attendanceRepository.GetByIdAsync(correction.AttendanceId.Value, cancellationToken: cancellationToken);
                    if (attendance != null)
                    {
                        await attendanceRepository.DeleteAsync(attendance, cancellationToken);
                        correction.AttendanceId = null;
                    }
                }
                break;

            case CorrectionAction.Edit:
                // Revert to old time
                if (correction.AttendanceId.HasValue && correction.OldDate.HasValue && correction.OldTime.HasValue)
                {
                    var attendance = await attendanceRepository.GetByIdAsync(correction.AttendanceId.Value, cancellationToken: cancellationToken);
                    if (attendance != null)
                    {
                        attendance.AttendanceTime = correction.OldDate.Value.Date.Add(correction.OldTime.Value);
                        await attendanceRepository.UpdateAsync(attendance, cancellationToken);
                    }
                }
                break;

            case CorrectionAction.Delete:
                // Cannot undo a delete - the attendance data is gone
                break;
        }
    }
}
