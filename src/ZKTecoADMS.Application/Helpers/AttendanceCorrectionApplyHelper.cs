using Mapster;
using Microsoft.AspNetCore.Identity;
using ZKTecoADMS.Application.DTOs.AttendanceCorrections;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Helpers;

/// <summary>Áp dụng chỉnh công sau khi duyệt (dùng chung Create tự duyệt + Approve).</summary>
public sealed class AttendanceCorrectionApplyHelper(
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
    IAttendanceService attendanceService)
{
    public async Task<AppResponse<AttendanceCorrectionRequestDto>> AutoApproveAndApplyAsync(
        Guid correctionId,
        Guid storeId,
        Guid approverUserId,
        string approverNote,
        CancellationToken cancellationToken = default)
    {
        var correction = await correctionRepository.GetSingleAsync(
            c => c.Id == correctionId && c.StoreId == storeId,
            includeProperties: [nameof(AttendanceCorrectionRequest.EmployeeUser)],
            cancellationToken: cancellationToken);

        if (correction == null)
            return AppResponse<AttendanceCorrectionRequestDto>.Error("Không tìm thấy yêu cầu chỉnh công");

        if (correction.Status == CorrectionStatus.Approved)
            return AppResponse<AttendanceCorrectionRequestDto>.Success(
                correction.Adapt<AttendanceCorrectionRequestDto>());

        var records = (await approvalRecordRepository.GetAllAsync(
            r => r.CorrectionRequestId == correctionId,
            cancellationToken: cancellationToken))
            .OrderBy(r => r.StepOrder)
            .ToList();

        var approver = await userManager.FindByIdAsync(approverUserId.ToString());
        var approverName = approver?.FullName ?? approver?.Email;

        foreach (var rec in records.Where(r => r.Status == ApprovalStatus.Pending))
        {
            rec.Status = ApprovalStatus.Approved;
            rec.ActualUserId = approverUserId;
            rec.ActualUserName = approverName;
            rec.Note = approverNote;
            rec.ActionDate = DateTime.UtcNow;
            await approvalRecordRepository.UpdateAsync(rec, cancellationToken);
        }

        correction.CurrentApprovalStep = records.Count > 0 ? records.Max(r => r.StepOrder) : 1;
        return await FinalizeApprovedAsync(correction, approverUserId, approverNote, cancellationToken);
    }

    public async Task<AppResponse<AttendanceCorrectionRequestDto>> FinalizeApprovedAsync(
        AttendanceCorrectionRequest correction,
        Guid approvedById,
        string? approverNote,
        CancellationToken cancellationToken = default)
    {
        correction.Status = CorrectionStatus.Approved;
        correction.ApprovedById = approvedById;
        correction.ApprovedDate = DateTime.UtcNow;
        if (!string.IsNullOrWhiteSpace(approverNote))
            correction.ApproverNote = approverNote;

        if (!await IsCorrectionAlreadyAppliedAsync(correction, cancellationToken))
        {
            var applyError = await TryApplyCorrectionAsync(correction, cancellationToken);
            if (applyError != null)
                return AppResponse<AttendanceCorrectionRequestDto>.Error(applyError);

            await PostApplyPenaltyCleanupAsync(correction, cancellationToken);
            await RecalculatePenaltiesAfterApprovalAsync(correction, cancellationToken);
        }

        await correctionRepository.UpdateAsync(correction, cancellationToken);

        try
        {
            await notificationService.CreateAndSendAsync(
                correction.EmployeeUserId, NotificationType.Success,
                "Yêu cầu chỉnh công đã duyệt",
                correction.TotalApprovalLevels > 1
                    ? $"Yêu cầu chỉnh sửa chấm công đã được phê duyệt qua {correction.TotalApprovalLevels} cấp"
                    : "Yêu cầu chỉnh sửa chấm công của bạn đã được phê duyệt",
                relatedEntityId: correction.Id, relatedEntityType: "AttendanceCorrection",
                fromUserId: approvedById, categoryCode: "approval", storeId: correction.StoreId);
        }
        catch { }

        return AppResponse<AttendanceCorrectionRequestDto>.Success(
            correction.Adapt<AttendanceCorrectionRequestDto>());
    }

    public async Task<bool> IsCorrectionAlreadyAppliedAsync(
        AttendanceCorrectionRequest correction,
        CancellationToken cancellationToken)
    {
        switch (correction.Action)
        {
            case CorrectionAction.Delete:
                var deleteTarget = await AttendanceLogResolveHelper.FindLogForCorrectionAsync(
                    attendanceRepository,
                    deviceUserRepository,
                    employeeRepository,
                    correction.StoreId,
                    correction.EmployeeCode,
                    pin: null,
                    correction.AttendanceId,
                    correction.OldDate,
                    correction.OldTime,
                    cancellationToken: cancellationToken);
                return deleteTarget == null;

            case CorrectionAction.Edit:
                if (!correction.AttendanceId.HasValue ||
                    !correction.NewDate.HasValue ||
                    !correction.NewTime.HasValue)
                    return false;
                var edited = await attendanceRepository.GetByIdAsync(
                    correction.AttendanceId.Value, cancellationToken: cancellationToken);
                if (edited == null)
                    return false;
                var expectedTime = correction.NewDate.Value.Date.Add(correction.NewTime.Value);
                return edited.AttendanceTime == expectedTime
                    || (edited.Note != null && edited.Note.Contains($"[YC:{correction.Id}]"));

            case CorrectionAction.Add:
                if (correction.AttendanceId.HasValue)
                {
                    var added = await attendanceRepository.GetByIdAsync(
                        correction.AttendanceId.Value, cancellationToken: cancellationToken);
                    if (added != null)
                        return true;
                }
                var marker = $"[YC:{correction.Id}]";
                var byNote = await attendanceRepository.GetSingleAsync(
                    a => a.Note != null && a.Note.Contains(marker),
                    cancellationToken: cancellationToken);
                return byNote != null;

            default:
                return false;
        }
    }

    /// <summary>null = success; otherwise error message.</summary>
    private async Task<string?> TryApplyCorrectionAsync(
        AttendanceCorrectionRequest correction,
        CancellationToken cancellationToken)
    {
        try
        {
            await ApplyCorrectionAsync(correction, cancellationToken);
            return null;
        }
        catch (Exception ex)
        {
            return DbExceptionMessageHelper.ToUserMessage(ex);
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
                    var employee = await AttendanceCorrectionEmployeeResolver.ResolveEmployeeEntityAsync(
                        employeeRepository,
                        deviceUserRepository,
                        correction.StoreId,
                        correction.EmployeeCode,
                        correction.EmployeeUserId,
                        cancellationToken);

                    var device = correction.StoreId.HasValue
                        ? await deviceRepository.GetSingleAsync(
                            d => d.StoreId == correction.StoreId.Value,
                            cancellationToken: cancellationToken)
                        : await deviceRepository.GetSingleAsync(
                            d => true, cancellationToken: cancellationToken);
                    var deviceId = device?.Id ?? Guid.Empty;
                    if (deviceId == Guid.Empty)
                        throw new InvalidOperationException(
                            "Không tìm thấy thiết bị chấm công để ghi bản ghi mới");

                    DeviceUser? deviceUser = null;
                    if (employee != null)
                    {
                        deviceUser = await deviceUserRepository.GetSingleAsync(
                            du => du.EmployeeId == employee.Id && du.DeviceId == deviceId,
                            cancellationToken: cancellationToken);
                    }

                    var empName = employee != null
                        ? $"{employee.LastName} {employee.FirstName}".Trim()
                        : (correction.EmployeeCode ?? "NV");
                    if (string.IsNullOrWhiteSpace(empName))
                        empName = correction.EmployeeCode ?? "NV";

                    if (deviceUser == null)
                    {
                        var preferredPin = (employee?.EmployeeCode ?? correction.EmployeeCode ?? "0").Trim();
                        if (preferredPin.Length > 20)
                            preferredPin = preferredPin[..20];
                        if (string.IsNullOrWhiteSpace(preferredPin))
                            preferredPin = "0";

                        var pinOwner = await deviceUserRepository.GetSingleAsync(
                            du => du.DeviceId == deviceId && du.Pin == preferredPin,
                            cancellationToken: cancellationToken);

                        if (pinOwner != null
                            && employee != null
                            && (pinOwner.EmployeeId == null || pinOwner.EmployeeId == employee.Id))
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
                                EmployeeId = employee?.Id,
                                IsActive = true,
                                GroupId = 1,
                                Privilege = 0,
                                VerifyMode = 0,
                                CreatedAt = DateTime.UtcNow
                            };
                            await deviceUserRepository.AddAsync(deviceUser, cancellationToken);
                        }
                        else
                        {
                            var onDevice = await deviceUserRepository.GetAllAsync(
                                du => du.DeviceId == deviceId,
                                cancellationToken: cancellationToken);
                            var used = onDevice.Select(u => u.Pin).ToHashSet(StringComparer.Ordinal);
                            var allocated = DeviceUserPinAllocator.AllocateSequential(used);
                            deviceUser = new DeviceUser
                            {
                                Id = Guid.NewGuid(),
                                Pin = allocated,
                                Name = empName.Length > 200 ? empName[..200] : empName,
                                DeviceId = deviceId,
                                EmployeeId = employee?.Id,
                                IsActive = true,
                                GroupId = 1,
                                Privilege = 0,
                                VerifyMode = 0,
                                CreatedAt = DateTime.UtcNow
                            };
                            await deviceUserRepository.AddAsync(deviceUser, cancellationToken);
                        }
                    }

                    var pin = deviceUser.Pin;
                    string? workCode = empName.Length > 10 ? empName.Substring(0, 10) : empName;

                    var punchState = ResolvePunchState(correction.NewPunchType);

                    var newAttendance = new Attendance
                    {
                        Id = Guid.NewGuid(),
                        EmployeeId = deviceUser.Id, // chỉ FK DeviceUser, không gán Employee.Id
                        DeviceId = deviceId,
                        PIN = pin,
                        AttendanceTime = correction.NewDate.Value.Date.Add(correction.NewTime.Value),
                        VerifyMode = VerifyModes.Manual,
                        AttendanceState = punchState,
                        WorkCode = workCode,
                        Note = $"Duyệt thêm chấm công ({punchState}) [YC:{correction.Id}]",
                        CreatedAt = DateTime.UtcNow
                    };
                    await attendanceRepository.AddAsync(newAttendance, cancellationToken);
                    correction.AttendanceId = newAttendance.Id;
                }
                break;

            case CorrectionAction.Edit:
                if (!correction.AttendanceId.HasValue)
                    throw new InvalidOperationException("Thiếu mã bản ghi chấm công cần sửa");
                var attendanceEdit = await attendanceRepository.GetByIdAsync(
                    correction.AttendanceId.Value, cancellationToken: cancellationToken);
                if (attendanceEdit == null)
                    throw new InvalidOperationException("Không tìm thấy bản ghi chấm công cần sửa");
                if (correction.NewDate.HasValue && correction.NewTime.HasValue)
                {
                    attendanceEdit.AttendanceTime =
                        correction.NewDate.Value.Date.Add(correction.NewTime.Value);
                    attendanceEdit.Note = $"Điều chỉnh giờ chấm công [YC:{correction.Id}]";
                    await attendanceRepository.UpdateAsync(attendanceEdit, cancellationToken);
                }
                break;

            case CorrectionAction.Delete:
                var attendanceDel = await AttendanceLogResolveHelper.FindLogForCorrectionAsync(
                    attendanceRepository,
                    deviceUserRepository,
                    employeeRepository,
                    correction.StoreId,
                    correction.EmployeeCode,
                    pin: null,
                    correction.AttendanceId,
                    correction.OldDate,
                    correction.OldTime,
                    cancellationToken: cancellationToken);
                if (attendanceDel == null)
                    break;
                correction.AttendanceId = attendanceDel.Id;
                correction.OldDate ??= attendanceDel.AttendanceTime.Date;
                correction.OldTime ??= attendanceDel.AttendanceTime.TimeOfDay;
                if (string.IsNullOrEmpty(correction.OldType))
                    correction.OldType = attendanceDel.AttendanceState.ToString();

                await AttendanceCorrectionPenaltyHelper.CancelPenaltiesForAttendanceAsync(
                    attendanceDel.Id, correction.Id,
                    penaltyTicketRepository, paymentTransactionRepository, cashTransactionRepository,
                    cancellationToken);

                await attendanceDeletePreparer.PrepareForDeleteAsync(
                    attendanceDel.Id, cancellationToken);

                await attendanceRepository.DeleteAsync(attendanceDel, cancellationToken);
                break;
        }
    }

    private async Task PostApplyPenaltyCleanupAsync(
        AttendanceCorrectionRequest correction,
        CancellationToken cancellationToken)
    {
        var employee = await AttendanceCorrectionEmployeeResolver.ResolveEmployeeEntityAsync(
            employeeRepository,
            deviceUserRepository,
            correction.StoreId,
            correction.EmployeeCode,
            correction.EmployeeUserId,
            cancellationToken);
        if (employee == null)
            return;

        var violationDate = (correction.NewDate ?? correction.OldDate)?.Date;
        if (violationDate.HasValue)
        {
            await AttendanceCorrectionPenaltyHelper.CancelDayLevelPenaltiesAsync(
                employee.Id, violationDate.Value, correction.Id,
                penaltyTicketRepository, paymentTransactionRepository, cashTransactionRepository,
                cancellationToken);
        }

        if (correction.AttendanceId.HasValue)
        {
            await AttendanceCorrectionPenaltyHelper.CancelPenaltiesForAttendanceAsync(
                correction.AttendanceId.Value, correction.Id,
                penaltyTicketRepository, paymentTransactionRepository, cashTransactionRepository,
                cancellationToken);
        }
    }

    private async Task RecalculatePenaltiesAfterApprovalAsync(
        AttendanceCorrectionRequest correction,
        CancellationToken cancellationToken)
    {
        if (correction.Action == CorrectionAction.Delete)
            return;

        var employee = await AttendanceCorrectionEmployeeResolver.ResolveEmployeeEntityAsync(
            employeeRepository,
            deviceUserRepository,
            correction.StoreId,
            correction.EmployeeCode,
            correction.EmployeeUserId,
            cancellationToken);
        if (employee == null)
            return;

        var workDate = (correction.NewDate ?? correction.OldDate)?.Date;
        if (!workDate.HasValue || !correction.StoreId.HasValue)
            return;

        try
        {
            await attendanceService.RecalculatePenaltiesForEmployeeDateAsync(
                correction.StoreId.Value, employee.Id, workDate.Value, cancellationToken);
        }
        catch { }
    }

    private static AttendanceStates ResolvePunchState(string? punchType)
    {
        if (string.Equals(punchType, "CheckOut", StringComparison.OrdinalIgnoreCase)
            || punchType == "1")
            return AttendanceStates.CheckOut;
        return AttendanceStates.CheckIn;
    }
}
