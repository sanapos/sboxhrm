using Microsoft.AspNetCore.Identity;
using ZKTecoADMS.Application.Notifications;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Leaves.CancelLeave;

public class CancelLeaveHandler(
    IRepository<Leave> leaveRepository,
    IRepository<LeaveApprovalRecord> approvalRecordRepository,
    ISystemNotificationService notificationService,
    UserManager<ApplicationUser> userManager
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
                return AppResponse<bool>.Error("Không tìm thấy đơn nghỉ phép");
            }

            // Verify ownership (managers can cancel any)
            if (!request.IsManager && leave.EmployeeUserId != request.ApplicationUserId)
            {
                return AppResponse<bool>.Error("Bạn chỉ được hủy đơn nghỉ của chính mình");
            }

            // Only pending leaves can be cancelled
            if (leave.Status != LeaveStatus.Pending)
            {
                return AppResponse<bool>.Error("Chỉ hủy được đơn đang chờ duyệt");
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
                record.ActionDate = DateTime.UtcNow;
                await approvalRecordRepository.UpdateAsync(record, cancellationToken);
            }

            // Báo quản lý (và NV nếu người khác hủy hộ). Trước đây message «Nhân viên đã hủy…» thêm tên người gửi
            // thành «An: Nhân viên đã hủy…», và quản lý tự hủy cũng tự nhận «Nhân viên đã hủy».
            try
            {
                var range = leave.StartDate.Date == leave.EndDate.Date
                    ? $"{leave.StartDate:dd/MM}"
                    : $"{leave.StartDate:dd/MM}–{leave.EndDate:dd/MM}";
                var cancelledBy = request.ApplicationUserId;

                if (leave.ManagerId != Guid.Empty && leave.ManagerId != cancelledBy)
                {
                    var employeeUser = await userManager.FindByIdAsync(leave.EmployeeUserId.ToString());
                    var employeeName = NotificationPushFormatter.FormatUserDisplayName(employeeUser);
                    if (string.IsNullOrWhiteSpace(employeeName)) employeeName = "nhân viên";
                    await notificationService.CreateAndSendAsync(
                        leave.ManagerId, NotificationType.Info,
                        "Đơn nghỉ phép đã hủy",
                        $"Đơn nghỉ {range} của {employeeName} · Không cần duyệt nữa",
                        relatedEntityId: leave.Id, relatedEntityType: "Leave",
                        fromUserId: cancelledBy, categoryCode: "leave", storeId: request.StoreId);
                }

                if (leave.EmployeeUserId != cancelledBy)
                {
                    await notificationService.CreateAndSendAsync(
                        leave.EmployeeUserId, NotificationType.Info,
                        "Đơn nghỉ phép đã hủy",
                        $"Đơn nghỉ {range} của bạn đã bị hủy",
                        relatedEntityId: leave.Id, relatedEntityType: "Leave",
                        fromUserId: cancelledBy, categoryCode: "leave", storeId: request.StoreId);
                }
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
