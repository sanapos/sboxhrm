using MediatR;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.AttendanceCorrections;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Commands.AttendanceCorrections;

// Create Attendance Correction Request Command
public record CreateAttendanceCorrectionCommand(
    Guid StoreId,
    Guid RequestedByUserId,
    Guid? EmployeeUserId,
    string? EmployeeName,
    string? EmployeeCode,
    string? Pin,
    Guid? AttendanceId,
    CorrectionAction Action,
    DateTime? OldDate,
    TimeSpan? OldTime,
    DateTime? NewDate,
    TimeSpan? NewTime,
    string? NewPunchType,
    string? Reason) : ICommand<AppResponse<AttendanceCorrectionRequestDto>>;

public class CreateAttendanceCorrectionHandler(
    IRepository<AttendanceCorrectionRequest> correctionRepository,
    IRepository<ApprovalRecord> approvalRecordRepository,
    UserManager<ApplicationUser> userManager,
    IRepository<Attendance> attendanceRepository,
    IRepository<Employee> employeeRepository,
    IRepository<Device> deviceRepository,
    IRepository<DeviceUser> deviceUserRepository,
    IAttendanceDeletePreparer attendanceDeletePreparer,
    IRepository<PenaltyTicket> penaltyTicketRepository,
    IRepository<PaymentTransaction> paymentTransactionRepository,
    IRepository<CashTransaction> cashTransactionRepository,
    IRepository<AppSettings> appSettingsRepository,
    ISystemNotificationService notificationService,
    ZKTecoADMS.Application.Interfaces.INotificationTargetResolver targetResolver,
    IModulePermissionService modulePermissionService,
    IAttendanceService attendanceService
) : ICommandHandler<CreateAttendanceCorrectionCommand, AppResponse<AttendanceCorrectionRequestDto>>
{
    public async Task<AppResponse<AttendanceCorrectionRequestDto>> Handle(CreateAttendanceCorrectionCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var (resolvedUserId, resolvedEmployee, resolveError) =
                await AttendanceCorrectionEmployeeResolver.ResolveAsync(
                    employeeRepository,
                    deviceUserRepository,
                    request.StoreId,
                    request.RequestedByUserId,
                    request.EmployeeCode,
                    request.Pin,
                    cancellationToken);
            if (resolveError != null)
                return AppResponse<AttendanceCorrectionRequestDto>.Error(resolveError);
            if (resolvedUserId == null)
                return AppResponse<AttendanceCorrectionRequestDto>.Error("Không tìm thấy nhân viên");

            Attendance? targetLog = null;
            if (request.Action is CorrectionAction.Edit or CorrectionAction.Delete)
            {
                targetLog = await AttendanceLogResolveHelper.FindLogForCorrectionAsync(
                    attendanceRepository,
                    deviceUserRepository,
                    employeeRepository,
                    request.StoreId,
                    request.EmployeeCode,
                    request.Pin,
                    request.AttendanceId,
                    request.OldDate,
                    request.OldTime,
                    resolvedEmployee?.Id,
                    cancellationToken);

                if (targetLog == null)
                {
                    return AppResponse<AttendanceCorrectionRequestDto>.Error(
                        "Không tìm thấy bản ghi chấm công. Kiểm tra PIN/giờ hoặc tải lại dữ liệu rồi thử lại.");
                }
            }

            var attendanceIdForRequest = targetLog?.Id ?? request.AttendanceId;

            // FK to ApplicationUser: NV có tài khoản → user NV; không có → user người tạo (Admin/QL)
            var employeeUserId = resolvedEmployee?.ApplicationUserId ?? request.RequestedByUserId;
            if (resolvedEmployee?.ApplicationUserId is Guid empUserId)
            {
                var userExists = await userManager.FindByIdAsync(empUserId.ToString());
                if (userExists == null)
                    employeeUserId = request.RequestedByUserId;
            }

            var employeeCodeForRecord = !string.IsNullOrWhiteSpace(request.EmployeeCode)
                ? request.EmployeeCode
                : resolvedEmployee?.EmployeeCode;

            var requester = await userManager.FindByIdAsync(request.RequestedByUserId.ToString());
            if (requester == null)
                return AppResponse<AttendanceCorrectionRequestDto>.Error(
                    "Không tìm thấy tài khoản người gửi yêu cầu");

            // Check allow_manual_correction setting
            var allowCorrectionSetting = await appSettingsRepository.GetSingleAsync(
                s => s.Key == "allow_manual_correction" && s.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            var canBypassSetting = await AttendanceCorrectionPrivilegeHelper
                .CanBypassManualCorrectionSettingAsync(
                    userManager, modulePermissionService, request.RequestedByUserId,
                    request.StoreId, cancellationToken);
            if (allowCorrectionSetting?.Value == "false" && !canBypassSetting)
                return AppResponse<AttendanceCorrectionRequestDto>.Error("Tính năng chấm công bù đã bị tắt. Liên hệ quản trị viên để được hỗ trợ.");

            string? oldDevice = null;
            string? oldType = null;
            var oldDateForRecord = request.OldDate;
            var oldTimeForRecord = request.OldTime;

            if (request.Action != CorrectionAction.Add && targetLog != null)
            {
                oldDevice = targetLog.DeviceId.ToString();
                oldType = targetLog.AttendanceState.ToString();
                oldDateForRecord ??= targetLog.AttendanceTime.Date;
                oldTimeForRecord ??= targetLog.AttendanceTime.TimeOfDay;
            }

            // Read approval levels from settings (default 1)
            var approvalLevels = await GetApprovalLevelsAsync(request.StoreId, cancellationToken);

            var correction = new AttendanceCorrectionRequest
            {
                StoreId = request.StoreId,
                EmployeeUserId = employeeUserId,
                EmployeeName = request.EmployeeName ??
                    (resolvedEmployee != null
                        ? $"{resolvedEmployee.LastName} {resolvedEmployee.FirstName}".Trim()
                        : null),
                EmployeeCode = employeeCodeForRecord ?? string.Empty,
                AttendanceId = attendanceIdForRequest,
                Action = request.Action,
                OldDate = oldDateForRecord,
                OldTime = oldTimeForRecord,
                OldDevice = oldDevice,
                OldType = oldType,
                NewDate = request.NewDate,
                NewTime = request.NewTime,
                NewPunchType = NormalizePunchType(request.NewPunchType),
                Reason = request.Reason,
                Status = CorrectionStatus.Pending,
                TotalApprovalLevels = approvalLevels,
                CurrentApprovalStep = 0
            };

            var created = await correctionRepository.AddAsync(correction, cancellationToken);

            // Build approval chain and create ApprovalRecord for each level
            var approvalChain = await BuildApprovalChainAsync(
                employeeUserId, resolvedEmployee, request.StoreId, approvalLevels, cancellationToken);
            foreach (var record in approvalChain)
            {
                record.CorrectionRequestId = created.Id;
                record.StoreId = request.StoreId;
                await approvalRecordRepository.AddAsync(record, cancellationToken);
            }

            var result = await correctionRepository.GetByIdAsync(created.Id,
                [nameof(AttendanceCorrectionRequest.EmployeeUser)],
                cancellationToken: cancellationToken);

            var autoApprove = await AttendanceCorrectionPrivilegeHelper
                .CanAutoApproveCorrectionsAsync(
                    userManager, modulePermissionService, request.RequestedByUserId,
                    request.StoreId, cancellationToken);

            if (autoApprove)
            {
                const string autoNote = "Tự động duyệt — tài khoản quyền quản trị";
                var applier = new AttendanceCorrectionApplyHelper(
                    correctionRepository,
                    approvalRecordRepository,
                    attendanceRepository,
                    employeeRepository,
                    deviceRepository,
                    deviceUserRepository,
                    attendanceDeletePreparer,
                    penaltyTicketRepository,
                    paymentTransactionRepository,
                    cashTransactionRepository,
                    userManager,
                    notificationService,
                    attendanceService);

                var autoResult = await applier.AutoApproveAndApplyAsync(
                    created.Id,
                    request.StoreId,
                    request.RequestedByUserId,
                    autoNote,
                    cancellationToken);

                if (!autoResult.IsSuccess)
                    return autoResult;

                result = await correctionRepository.GetByIdAsync(created.Id,
                    [nameof(AttendanceCorrectionRequest.EmployeeUser)],
                    cancellationToken: cancellationToken);
            }
            else
            {
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
                        .ToHashSet();

                    if (resolvedEmployee?.ApplicationUserId is Guid empAppUserId)
                    {
                        var hierarchyTargets = await targetResolver.ResolveManagersAsync(
                            empAppUserId, request.StoreId, hierarchyLevels: 2, cancellationToken);
                        foreach (var t in hierarchyTargets)
                            firstLevelTargets.Add(t);
                        firstLevelTargets.Remove(empAppUserId);
                    }

                    firstLevelTargets.Remove(request.RequestedByUserId);

                    if (firstLevelTargets.Count > 0)
                    {
                        await notificationService.CreateAndSendToUsersAsync(
                            firstLevelTargets, NotificationType.ApprovalRequired,
                            "Yêu cầu chỉnh công mới",
                            $"{request.EmployeeName ?? "Nhân viên"} yêu cầu {actionText} chấm công" +
                            (approvalLevels > 1 ? $" (cấp 1/{approvalLevels})" : ""),
                            relatedEntityId: created.Id, relatedEntityType: "AttendanceCorrection",
                            fromUserId: employeeUserId, categoryCode: "approval", storeId: request.StoreId);
                    }
                }
                catch { /* Notification failure should not affect main operation */ }
            }

            return AppResponse<AttendanceCorrectionRequestDto>.Success(result!.Adapt<AttendanceCorrectionRequestDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<AttendanceCorrectionRequestDto>.Error(DbExceptionMessageHelper.ToUserMessage(ex));
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
        Guid employeeUserId, Employee? targetEmployee, Guid storeId, int totalLevels, CancellationToken ct)
    {
        var records = new List<ApprovalRecord>();

        var employee = targetEmployee ?? await employeeRepository.GetSingleAsync(
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

    private static string? NormalizePunchType(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw))
            return null;
        if (raw.Equals("CheckOut", StringComparison.OrdinalIgnoreCase) || raw == "1")
            return "CheckOut";
        return "CheckIn";
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
    IAttendanceDeletePreparer attendanceDeletePreparer,
    IRepository<PenaltyTicket> penaltyTicketRepository,
    IRepository<PaymentTransaction> paymentTransactionRepository,
    IRepository<CashTransaction> cashTransactionRepository,
    UserManager<ApplicationUser> userManager,
    ISystemNotificationService notificationService,
    IAttendanceService attendanceService,
    IModulePermissionService modulePermissionService
) : ICommandHandler<ApproveAttendanceCorrectionCommand, AppResponse<AttendanceCorrectionRequestDto>>
{
    private AttendanceCorrectionApplyHelper ApplyHelper => new(
        correctionRepository,
        approvalRecordRepository,
        attendanceRepository,
        employeeRepository,
        deviceRepository,
        deviceUserRepository,
        attendanceDeletePreparer,
        penaltyTicketRepository,
        paymentTransactionRepository,
        cashTransactionRepository,
        userManager,
        notificationService,
        attendanceService);

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
            {
                // Trạng thái mồ côi: mọi bước đã duyệt nhưng phiếu vẫn Pending (thường do lỗi khi áp dụng lần trước)
                if (allRecords.Count > 0 &&
                    allRecords.All(r => r.Status == ApprovalStatus.Approved))
                {
                    if (!request.IsApproved)
                        return AppResponse<AttendanceCorrectionRequestDto>.Error(
                            "Yêu cầu đã được duyệt đủ cấp, không thể từ chối");

                    var canFinalize = await AttendanceCorrectionPrivilegeHelper
                        .CanApproveCorrectionStepAsync(
                            userManager, modulePermissionService, request.ApprovedById,
                            request.StoreId, cancellationToken);
                    if (!canFinalize)
                        return AppResponse<AttendanceCorrectionRequestDto>.Error(
                            "Bạn không có quyền hoàn tất yêu cầu này");

                    correction.CurrentApprovalStep = allRecords.Max(r => r.StepOrder);
                    return await ApplyHelper.FinalizeApprovedAsync(
                        correction, request.ApprovedById, request.ApproverNote, cancellationToken);
                }

                return AppResponse<AttendanceCorrectionRequestDto>.Error(
                    "Không còn bước duyệt nào cần xử lý");
            }

            // Verify permission: assigned approver, quản trị, hoặc quyền module duyệt
            var isAssigned = currentRecord.AssignedUserId == request.ApprovedById;
            var canApproveStep = isAssigned || await AttendanceCorrectionPrivilegeHelper
                .CanApproveCorrectionStepAsync(
                    userManager, modulePermissionService, request.ApprovedById,
                    request.StoreId, cancellationToken);

            if (!canApproveStep)
                return AppResponse<AttendanceCorrectionRequestDto>.Error("Bạn không có quyền duyệt bước này");

            var approver = await userManager.FindByIdAsync(request.ApprovedById.ToString());

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
                return await ApplyHelper.FinalizeApprovedAsync(
                    correction, request.ApprovedById, request.ApproverNote, cancellationToken);
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
    IRepository<Employee> employeeRepository,
    IRepository<DeviceUser> deviceUserRepository,
    IRepository<Device> deviceRepository,
    IRepository<PenaltyTicket> penaltyTicketRepository,
    IRepository<PaymentTransaction> paymentTransactionRepository,
    IRepository<CashTransaction> cashTransactionRepository,
    ISystemNotificationService notificationService,
    IAttendanceService attendanceService
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

            var revertError = await RevertCorrectionAsync(correction, cancellationToken);
            if (revertError != null)
                return AppResponse<AttendanceCorrectionRequestDto>.Error(revertError);

            correction.Status = CorrectionStatus.Pending;
            correction.ApprovedById = null;
            correction.ApprovedDate = null;
            correction.ApproverNote = null;
            correction.CurrentApprovalStep = 0;

            await correctionRepository.UpdateAsync(correction, cancellationToken);

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

            await RecalculatePenaltiesAfterUndoAsync(correction, cancellationToken);

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

            var refreshed = await correctionRepository.GetByIdAsync(
                correction.Id,
                [nameof(AttendanceCorrectionRequest.EmployeeUser), nameof(AttendanceCorrectionRequest.ApprovedBy)],
                cancellationToken: cancellationToken);

            return AppResponse<AttendanceCorrectionRequestDto>.Success(
                (refreshed ?? correction).Adapt<AttendanceCorrectionRequestDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<AttendanceCorrectionRequestDto>.Error(
                string.IsNullOrWhiteSpace(ex.Message)
                    ? "Không thể hoàn duyệt yêu cầu"
                    : ex.Message);
        }
    }

    /// <returns>Error message if revert failed; null if OK.</returns>
    private async Task<string?> RevertCorrectionAsync(
        AttendanceCorrectionRequest correction,
        CancellationToken cancellationToken)
    {
        switch (correction.Action)
        {
            case CorrectionAction.Add:
                if (!correction.AttendanceId.HasValue)
                    return null;

                var addedId = correction.AttendanceId.Value;
                await AttendanceCorrectionPenaltyHelper.CancelPenaltiesForAttendanceAsync(
                    addedId, correction.Id,
                    penaltyTicketRepository, paymentTransactionRepository, cashTransactionRepository,
                    cancellationToken);

                var violationDate = (correction.NewDate ?? correction.OldDate)?.Date;
                if (violationDate.HasValue)
                {
                    var employee = await AttendanceCorrectionEmployeeResolver.ResolveEmployeeEntityAsync(
                        employeeRepository, deviceUserRepository,
                        correction.StoreId, correction.EmployeeCode, correction.EmployeeUserId,
                        cancellationToken);
                    if (employee != null)
                    {
                        await AttendanceCorrectionPenaltyHelper.CancelDayLevelPenaltiesAsync(
                            employee.Id, violationDate.Value, correction.Id,
                            penaltyTicketRepository, paymentTransactionRepository, cashTransactionRepository,
                            cancellationToken);
                    }
                }

                correction.AttendanceId = null;
                await correctionRepository.UpdateAsync(correction, cancellationToken);

                var addedAttendance = await attendanceRepository.GetByIdAsync(addedId, cancellationToken: cancellationToken);
                if (addedAttendance != null)
                    await attendanceRepository.DeleteAsync(addedAttendance, cancellationToken);
                return null;

            case CorrectionAction.Edit:
                if (!correction.AttendanceId.HasValue)
                    return "Không tìm thấy bản ghi chấm công để khôi phục";
                if (!correction.OldDate.HasValue || !correction.OldTime.HasValue)
                    return "Thiếu giờ cũ, không thể hoàn duyệt chỉnh sửa";

                var edited = await attendanceRepository.GetByIdAsync(
                    correction.AttendanceId.Value, cancellationToken: cancellationToken);
                if (edited == null)
                    return "Bản ghi chấm công đã bị xóa, không thể hoàn duyệt";

                edited.AttendanceTime = correction.OldDate.Value.Date.Add(correction.OldTime.Value);
                edited.Note = AppendUndoNote(edited.Note, correction.Id);
                await attendanceRepository.UpdateAsync(edited, cancellationToken);
                return null;

            case CorrectionAction.Delete:
                if (!correction.OldDate.HasValue || !correction.OldTime.HasValue)
                    return "Thiếu giờ cũ, không thể khôi phục chấm công đã xóa";

                if (correction.AttendanceId.HasValue)
                {
                    var existing = await attendanceRepository.GetByIdAsync(
                        correction.AttendanceId.Value, cancellationToken: cancellationToken);
                    if (existing != null)
                        return null;
                }

                var restored = await BuildRestoredAttendanceAsync(correction, cancellationToken);
                if (restored == null)
                    return "Không thể khôi phục chấm công (thiếu thiết bị hoặc nhân viên)";

                await attendanceRepository.AddAsync(restored, cancellationToken);
                correction.AttendanceId = restored.Id;
                return null;

            default:
                return null;
        }
    }

    private async Task<Attendance?> BuildRestoredAttendanceAsync(
        AttendanceCorrectionRequest correction,
        CancellationToken cancellationToken)
    {
        var employee = await AttendanceCorrectionEmployeeResolver.ResolveEmployeeEntityAsync(
            employeeRepository, deviceUserRepository,
            correction.StoreId, correction.EmployeeCode, correction.EmployeeUserId,
            cancellationToken);
        if (employee == null)
            return null;

        var device = correction.StoreId.HasValue
            ? await deviceRepository.GetSingleAsync(
                d => d.StoreId == correction.StoreId.Value, cancellationToken: cancellationToken)
            : await deviceRepository.GetSingleAsync(d => true, cancellationToken: cancellationToken);
        if (device == null)
            return null;
        var deviceId = device.Id;

        var deviceUser = await deviceUserRepository.GetSingleAsync(
            du => du.EmployeeId == employee.Id && du.DeviceId == deviceId,
            cancellationToken: cancellationToken);

        var empName = $"{employee.LastName} {employee.FirstName}".Trim();
        if (string.IsNullOrWhiteSpace(empName))
            empName = employee.EmployeeCode ?? "NV";

        if (deviceUser == null)
        {
            var preferredPin = (employee.EmployeeCode ?? correction.EmployeeCode ?? "0").Trim();
            if (preferredPin.Length > 20)
                preferredPin = preferredPin[..20];
            if (string.IsNullOrWhiteSpace(preferredPin))
                preferredPin = "0";

            var pinOwner = await deviceUserRepository.GetSingleAsync(
                du => du.DeviceId == deviceId && du.Pin == preferredPin,
                cancellationToken: cancellationToken);
            if (pinOwner != null && (pinOwner.EmployeeId == null || pinOwner.EmployeeId == employee.Id))
            {
                if (pinOwner.EmployeeId == null)
                {
                    pinOwner.EmployeeId = employee.Id;
                    if (string.IsNullOrWhiteSpace(pinOwner.Name))
                        pinOwner.Name = empName;
                    await deviceUserRepository.UpdateAsync(pinOwner, cancellationToken);
                }
                deviceUser = pinOwner;
            }
            else if (pinOwner == null)
            {
                deviceUser = new DeviceUser
                {
                    Id = Guid.NewGuid(),
                    Pin = preferredPin,
                    Name = empName.Length > 200 ? empName[..200] : empName,
                    DeviceId = deviceId,
                    EmployeeId = employee.Id,
                    IsActive = true,
                    GroupId = 1,
                    CreatedAt = DateTime.UtcNow
                };
                await deviceUserRepository.AddAsync(deviceUser, cancellationToken);
            }
            else
            {
                var onDevice = await deviceUserRepository.GetAllAsync(
                    du => du.DeviceId == deviceId, cancellationToken: cancellationToken);
                var used = onDevice.Select(u => u.Pin).ToHashSet(StringComparer.Ordinal);
                var allocated = DeviceUserPinAllocator.AllocateSequential(used);
                deviceUser = new DeviceUser
                {
                    Id = Guid.NewGuid(),
                    Pin = allocated,
                    Name = empName.Length > 200 ? empName[..200] : empName,
                    DeviceId = deviceId,
                    EmployeeId = employee.Id,
                    IsActive = true,
                    GroupId = 1,
                    CreatedAt = DateTime.UtcNow
                };
                await deviceUserRepository.AddAsync(deviceUser, cancellationToken);
            }
        }

        var pin = deviceUser.Pin;
        var punchState = ResolvePunchStateFromOldType(correction.OldType);
        var punchTime = correction.OldDate!.Value.Date.Add(correction.OldTime!.Value);

        return new Attendance
        {
            Id = correction.AttendanceId ?? Guid.NewGuid(),
            EmployeeId = deviceUser.Id,
            DeviceId = deviceId,
            PIN = pin,
            AttendanceTime = punchTime,
            VerifyMode = VerifyModes.Manual,
            AttendanceState = punchState,
            Note = $"Khôi phục sau hoàn duyệt [YC:{correction.Id}]",
            CreatedAt = DateTime.UtcNow
        };
    }

    private async Task RecalculatePenaltiesAfterUndoAsync(
        AttendanceCorrectionRequest correction,
        CancellationToken cancellationToken)
    {
        if (correction.Action == CorrectionAction.Delete)
            return;

        var employee = await AttendanceCorrectionEmployeeResolver.ResolveEmployeeEntityAsync(
            employeeRepository, deviceUserRepository,
            correction.StoreId, correction.EmployeeCode, correction.EmployeeUserId,
            cancellationToken);
        if (employee == null || !correction.StoreId.HasValue)
            return;

        var workDate = (correction.NewDate ?? correction.OldDate)?.Date;
        if (!workDate.HasValue)
            return;

        try
        {
            await attendanceService.RecalculatePenaltiesForEmployeeDateAsync(
                correction.StoreId.Value, employee.Id, workDate.Value, cancellationToken);
        }
        catch
        {
            // Penalty recalc failure must not roll back undo
        }
    }

    private static AttendanceStates ResolvePunchStateFromOldType(string? oldType)
    {
        if (string.Equals(oldType, "CheckOut", StringComparison.OrdinalIgnoreCase)
            || oldType == "1")
            return AttendanceStates.CheckOut;
        return AttendanceStates.CheckIn;
    }

    private static string AppendUndoNote(string? existing, Guid correctionId)
    {
        var addition = $"Hoàn duyệt chỉnh sửa [YC:{correctionId}]";
        if (string.IsNullOrWhiteSpace(existing))
            return addition;
        if (existing.Contains(addition, StringComparison.Ordinal))
            return existing;
        return $"{existing} | {addition}";
    }
}
