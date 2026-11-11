using Microsoft.AspNetCore.Identity;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Notifications;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Leaves.ApproveLeave;

public class ApproveLeaveHandler(
    IRepository<Leave> leaveRepository,
    IRepository<LeaveApprovalRecord> approvalRecordRepository,
    UserManager<ApplicationUser> userManager,
    ISystemNotificationService notificationService,
    IAnnualLeaveBalanceService annualLeaveBalance
    )
    : ICommandHandler<ApproveLeaveCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(ApproveLeaveCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var leave = await leaveRepository.GetSingleAsync(
                filter: l => l.Id == request.LeaveId && l.StoreId == request.StoreId,
                includeProperties: [nameof(Leave.EmployeeUser)],
                cancellationToken: cancellationToken);

            if (leave == null)
            {
                return AppResponse<bool>.Error("Leave not found");
            }

            if (request.CountAsWork.HasValue)
            {
                leave.CountAsWork = request.CountAsWork.Value;
            }

            if (leave.Status != LeaveStatus.Pending)
            {
                return AppResponse<bool>.Error($"Cannot approve leave with status: {leave.Status}");
            }

            // Get approval records ordered by step
            var approvalRecords = (await approvalRecordRepository.GetAllAsync(
                filter: r => r.LeaveId == leave.Id,
                cancellationToken: cancellationToken))
                .OrderBy(r => r.StepOrder).ToList();

            // Get approver info
            var approver = await userManager.FindByIdAsync(request.ApprovedByUserId.ToString());
            var approverName = approver?.FullName ?? approver?.Email ?? "Unknown";

            if (approvalRecords.Count == 0)
            {
                var finalizeLegacy = await FinalizeApprovalAsync(
                    leave, request, cancellationToken);
                if (!finalizeLegacy.IsSuccess)
                    return finalizeLegacy;
            }
            else
            {
                // Find current pending step
                var currentStep = approvalRecords.FirstOrDefault(r => r.Status == ApprovalStatus.Pending);
                if (currentStep == null)
                {
                    return AppResponse<bool>.Error("Không có bước duyệt nào đang chờ");
                }

                // Validate: only the assigned approver or Admin/SuperAdmin can approve this step
                if (currentStep.AssignedUserId.HasValue && currentStep.AssignedUserId != request.ApprovedByUserId)
                {
                    var approverRole = approver?.Role ?? "";
                    if (approverRole != nameof(Roles.Admin) && approverRole != nameof(Roles.SuperAdmin))
                    {
                        return AppResponse<bool>.Error(
                            $"Bước {currentStep.StepOrder} ({currentStep.StepName}) được gán cho {currentStep.AssignedUserName}. " +
                            $"Chỉ người được gán hoặc Admin mới có thể phê duyệt bước này.");
                    }
                }

                // Mark step as approved
                currentStep.Status = ApprovalStatus.Approved;
                currentStep.ActualUserId = request.ApprovedByUserId;
                currentStep.ActualUserName = approverName;
                currentStep.ActionDate = DateTime.UtcNow;
                currentStep.Note = "Đã phê duyệt";
                await approvalRecordRepository.UpdateAsync(currentStep, cancellationToken);

                leave.CurrentApprovalStep = currentStep.StepOrder;
                leave.UpdatedAt = DateTime.UtcNow;

                // Check if this was the last step
                var nextStep = approvalRecords.FirstOrDefault(r => r.StepOrder > currentStep.StepOrder && r.Status == ApprovalStatus.Pending);

                if (nextStep == null)
                {
                    var finalize = await FinalizeApprovalAsync(
                        leave, request, cancellationToken);
                    if (!finalize.IsSuccess)
                    {
                        // Bước cuối đã lưu «Đã duyệt» trước khi trừ phép: trả lại «Chờ» để duyệt lại được
                        // sau khi bổ sung phép — nếu không đơn kẹt ở chờ duyệt mà không còn bước nào để duyệt.
                        currentStep.Status = ApprovalStatus.Pending;
                        currentStep.ActualUserId = null;
                        currentStep.ActualUserName = null;
                        currentStep.ActionDate = null;
                        currentStep.Note = null;
                        await approvalRecordRepository.UpdateAsync(currentStep, cancellationToken);
                        return finalize;
                    }
                }
                else
                {
                    // More steps remaining - notify next approver
                    await leaveRepository.UpdateAsync(leave, cancellationToken);

                    try
                    {
                        var range = FormatRange(leave.StartDate, leave.EndDate);
                        var approverDisplay = NotificationPushFormatter.FormatUserDisplayName(approver);
                        if (string.IsNullOrWhiteSpace(approverDisplay)) approverDisplay = "Quản lý";

                        if (nextStep.AssignedUserId.HasValue)
                        {
                            // Người gửi = NV xin nghỉ (trước đây là người duyệt trước → đọc thành «Hoa: …» như Hoa xin nghỉ).
                            var employeeName = NotificationPushFormatter.FormatUserDisplayName(leave.EmployeeUser);
                            if (string.IsNullOrWhiteSpace(employeeName)) employeeName = "Nhân viên";
                            await notificationService.CreateAndSendAsync(
                                nextStep.AssignedUserId.Value, NotificationType.ApprovalRequired,
                                "Cần duyệt nghỉ phép",
                                $"{employeeName} xin nghỉ {range} · Bước {nextStep.StepOrder}/{leave.TotalApprovalLevels} · {approverDisplay} đã duyệt bước {currentStep.StepOrder}",
                                relatedEntityId: leave.Id, relatedEntityType: "Leave",
                                fromUserId: leave.EmployeeUserId, categoryCode: "leave", storeId: request.StoreId);
                        }

                        // Progress notification to employee
                        await notificationService.CreateAndSendAsync(
                            leave.EmployeeUserId, NotificationType.Info,
                            $"Nghỉ phép: xong bước {currentStep.StepOrder}/{leave.TotalApprovalLevels}",
                            $"Nghỉ {range} · {approverDisplay} đã duyệt, chờ bước {nextStep.StepOrder}",
                            relatedEntityId: leave.Id, relatedEntityType: "Leave",
                            fromUserId: request.ApprovedByUserId, categoryCode: "approval", storeId: request.StoreId);
                    }
                    catch { }
                }
            }

            return AppResponse<bool>.Success(true);
        }
        catch (Exception ex)
        {
            return AppResponse<bool>.Error(ex.Message);
        }
    }

    private async Task<AppResponse<bool>> FinalizeApprovalAsync(
        Leave leave,
        ApproveLeaveCommand request,
        CancellationToken cancellationToken)
    {
        var deduct = await annualLeaveBalance.TryApplyDeductionAsync(leave, cancellationToken);
        if (!deduct.IsSuccess)
            return AppResponse<bool>.Error(deduct.Message ?? "Không thể trừ phép năm.");

        leave.Status = LeaveStatus.Approved;
        leave.UpdatedAt = DateTime.UtcNow;
        await leaveRepository.UpdateAsync(leave, cancellationToken);

        try
        {
            // Trước đây ~150 ký tự, thiếu «.» trước «Đã trừ»; số phép còn lại nằm cuối bị cắt trên banner.
            var daysUsed = leave.AnnualLeaveDaysDeducted;
            var balanceNote = daysUsed > 0
                ? $" · Trừ {daysUsed:0.##} ngày phép năm, còn {deduct.Data:0.##} ngày"
                : string.Empty;
            await notificationService.CreateAndSendAsync(
                leave.EmployeeUserId, NotificationType.Success,
                "Đơn nghỉ phép đã duyệt",
                $"Nghỉ {FormatRange(leave.StartDate, leave.EndDate)}{balanceNote}",
                relatedEntityId: leave.Id, relatedEntityType: "Leave",
                fromUserId: request.ApprovedByUserId, categoryCode: "approval",
                storeId: request.StoreId);
        }
        catch { }

        return AppResponse<bool>.Success(true);
    }

    /// <summary>«12/11» (một ngày) hoặc «12/11–13/11».</summary>
    private static string FormatRange(DateTime start, DateTime end) =>
        start.Date == end.Date ? $"{start:dd/MM}" : $"{start:dd/MM}–{end:dd/MM}";
}
