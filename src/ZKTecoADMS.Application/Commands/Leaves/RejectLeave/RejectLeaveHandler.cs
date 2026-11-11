using Microsoft.AspNetCore.Identity;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Leaves.RejectLeave;

public class RejectLeaveHandler(
    IRepository<Leave> leaveRepository,
    IRepository<LeaveApprovalRecord> approvalRecordRepository,
    UserManager<ApplicationUser> userManager,
    ISystemNotificationService notificationService
    )
    : ICommandHandler<RejectLeaveCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(RejectLeaveCommand request, CancellationToken cancellationToken)
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
                return AppResponse<bool>.Error($"Cannot reject leave with status: {leave.Status}");
            }

            // Get approver info
            var rejector = await userManager.FindByIdAsync(request.RejectedByUserId.ToString());
            var rejectorName = rejector?.FullName ?? rejector?.Email ?? "Unknown";

            // Update approval records
            var approvalRecords = (await approvalRecordRepository.GetAllAsync(
                filter: r => r.LeaveId == leave.Id,
                cancellationToken: cancellationToken))
                .OrderBy(r => r.StepOrder).ToList();

            if (approvalRecords.Count > 0)
            {
                // Find current pending step and mark rejected
                var currentStep = approvalRecords.FirstOrDefault(r => r.Status == ApprovalStatus.Pending);
                if (currentStep != null)
                {
                    // Validate: only the assigned approver or Admin/SuperAdmin can reject this step
                    if (currentStep.AssignedUserId.HasValue && currentStep.AssignedUserId != request.RejectedByUserId)
                    {
                        var rejectorRole = rejector?.Role ?? "";
                        if (rejectorRole != nameof(Roles.Admin) && rejectorRole != nameof(Roles.SuperAdmin))
                        {
                            return AppResponse<bool>.Error(
                                $"Bước {currentStep.StepOrder} ({currentStep.StepName}) được gán cho {currentStep.AssignedUserName}. " +
                                $"Chỉ người được gán hoặc Admin mới có thể từ chối bước này.");
                        }
                    }

                    currentStep.Status = ApprovalStatus.Rejected;
                    currentStep.ActualUserId = request.RejectedByUserId;
                    currentStep.ActualUserName = rejectorName;
                    currentStep.ActionDate = DateTime.UtcNow;
                    currentStep.Note = request.RejectionReason;
                    await approvalRecordRepository.UpdateAsync(currentStep, cancellationToken);
                }

                // Cancel all remaining pending steps
                foreach (var record in approvalRecords.Where(r => r.Status == ApprovalStatus.Pending))
                {
                    record.Status = ApprovalStatus.Cancelled;
                    record.ActionDate = DateTime.UtcNow;
                    await approvalRecordRepository.UpdateAsync(record, cancellationToken);
                }
            }

            leave.Status = LeaveStatus.Rejected;
            leave.UpdatedAt = DateTime.UtcNow;
            leave.RejectionReason = request.RejectionReason;

            await leaveRepository.UpdateAsync(leave, cancellationToken);

            try
            {
                // Người từ chối đã có trong tên người gửi (trước đây «bởi Unknown - …» khi thiếu tên); lý do lên trước.
                var range = leave.StartDate.Date == leave.EndDate.Date
                    ? $"{leave.StartDate:dd/MM}"
                    : $"{leave.StartDate:dd/MM}–{leave.EndDate:dd/MM}";
                var reason = string.IsNullOrWhiteSpace(request.RejectionReason)
                    ? string.Empty
                    : $" · Lý do: {request.RejectionReason.Trim()}";
                await notificationService.CreateAndSendAsync(
                    leave.EmployeeUserId, NotificationType.Warning,
                    "Đơn nghỉ phép bị từ chối",
                    $"Nghỉ {range}{reason}",
                    relatedEntityId: leave.Id, relatedEntityType: "Leave",
                    fromUserId: request.RejectedByUserId, categoryCode: "approval", storeId: request.StoreId);
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
