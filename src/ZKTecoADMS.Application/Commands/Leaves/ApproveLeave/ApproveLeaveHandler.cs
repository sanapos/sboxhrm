using Microsoft.AspNetCore.Identity;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Leaves.ApproveLeave;

public class ApproveLeaveHandler(
    IRepository<Leave> leaveRepository,
    IRepository<LeaveApprovalRecord> approvalRecordRepository,
    UserManager<ApplicationUser> userManager,
    ISystemNotificationService notificationService
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
                // Legacy leave with no approval records - approve directly
                leave.Status = LeaveStatus.Approved;
                leave.UpdatedAt = DateTime.Now;
                await leaveRepository.UpdateAsync(leave, cancellationToken);
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
                currentStep.ActionDate = DateTime.Now;
                currentStep.Note = "Đã phê duyệt";
                await approvalRecordRepository.UpdateAsync(currentStep, cancellationToken);

                leave.CurrentApprovalStep = currentStep.StepOrder;
                leave.UpdatedAt = DateTime.Now;

                // Check if this was the last step
                var nextStep = approvalRecords.FirstOrDefault(r => r.StepOrder > currentStep.StepOrder && r.Status == ApprovalStatus.Pending);

                if (nextStep == null)
                {
                    // All steps approved - finalize
                    leave.Status = LeaveStatus.Approved;
                    await leaveRepository.UpdateAsync(leave, cancellationToken);

                    // Notify employee - fully approved
                    try
                    {
                        await notificationService.CreateAndSendAsync(
                            leave.EmployeeUserId, NotificationType.Success,
                            "Đơn nghỉ phép đã duyệt",
                            $"Đơn nghỉ phép từ {leave.StartDate:dd/MM/yyyy} đến {leave.EndDate:dd/MM/yyyy} đã được phê duyệt hoàn tất" +
                            (leave.TotalApprovalLevels > 1 ? $" ({leave.TotalApprovalLevels}/{leave.TotalApprovalLevels} cấp)" : ""),
                            relatedEntityId: leave.Id, relatedEntityType: "Leave",
                            fromUserId: request.ApprovedByUserId, categoryCode: "approval", storeId: request.StoreId);
                    }
                    catch { }
                }
                else
                {
                    // More steps remaining - notify next approver
                    await leaveRepository.UpdateAsync(leave, cancellationToken);

                    try
                    {
                        if (nextStep.AssignedUserId.HasValue)
                        {
                            await notificationService.CreateAndSendAsync(
                                nextStep.AssignedUserId.Value, NotificationType.ApprovalRequired,
                                "Đơn nghỉ phép cần phê duyệt",
                                $"Đơn nghỉ phép cần phê duyệt (Bước {nextStep.StepOrder}/{leave.TotalApprovalLevels}) từ {leave.StartDate:dd/MM/yyyy} đến {leave.EndDate:dd/MM/yyyy}",
                                relatedEntityId: leave.Id, relatedEntityType: "Leave",
                                fromUserId: request.ApprovedByUserId, categoryCode: "leave", storeId: request.StoreId);
                        }

                        // Progress notification to employee
                        await notificationService.CreateAndSendAsync(
                            leave.EmployeeUserId, NotificationType.Info,
                            "Tiến trình duyệt nghỉ phép",
                            $"Đơn nghỉ phép đã được duyệt bước {currentStep.StepOrder}/{leave.TotalApprovalLevels} ({currentStep.StepName}) bởi {approverName}",
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
}
