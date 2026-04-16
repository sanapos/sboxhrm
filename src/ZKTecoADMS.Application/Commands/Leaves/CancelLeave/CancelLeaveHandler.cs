using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Leaves.CancelLeave;

public class CancelLeaveHandler(
    IRepository<Leave> leaveRepository,
    IRepository<LeaveApprovalRecord> approvalRecordRepository,
    ISystemNotificationService notificationService
    )
    : ICommandHandler<CancelLeaveCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(CancelLeaveCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var leave = await leaveRepository.GetSingleAsync(
                filter: l => l.Id == request.LeaveId && l.StoreId == request.StoreId,
                cancellationToken: cancellationToken);

            if (leave == null)
            {
                return AppResponse<bool>.Error("Leave not found");
            }

            // Verify ownership (managers can cancel any)
            if (!request.IsManager && leave.EmployeeUserId != request.ApplicationUserId)
            {
                return AppResponse<bool>.Error("You are not authorized to cancel this leave request");
            }

            // Only pending leaves can be cancelled
            if (leave.Status != LeaveStatus.Pending)
            {
                return AppResponse<bool>.Error($"Cannot cancel leave with status: {leave.Status}");
            }

            leave.Status = LeaveStatus.Cancelled;
            await leaveRepository.UpdateAsync(leave, cancellationToken);

            // Cancel all pending approval records
            var approvalRecords = await approvalRecordRepository.GetAllAsync(
                filter: r => r.LeaveId == leave.Id && r.Status == ApprovalStatus.Pending,
                cancellationToken: cancellationToken);
            foreach (var record in approvalRecords)
            {
                record.Status = ApprovalStatus.Cancelled;
                record.ActionDate = DateTime.Now;
                await approvalRecordRepository.UpdateAsync(record, cancellationToken);
            }

            // Notify manager that employee cancelled
            try
            {
                await notificationService.CreateAndSendAsync(
                    leave.ManagerId, NotificationType.Info,
                    "Đơn nghỉ phép đã hủy",
                    $"Nhân viên đã hủy đơn nghỉ phép từ {leave.StartDate:dd/MM/yyyy} đến {leave.EndDate:dd/MM/yyyy}",
                    relatedEntityId: leave.Id, relatedEntityType: "Leave",
                    fromUserId: request.ApplicationUserId, categoryCode: "leave", storeId: request.StoreId);
            }
            catch { }

            return AppResponse<bool>.Success(true);
        }
        catch (Exception ex)
        {
            return AppResponse<bool>.Error(ex.Message);
        }
    }
}
