using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Notifications;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Leaves.ForceDeleteLeave;

public class ForceDeleteLeaveHandler(
    IRepository<Leave> leaveRepository,
    IAnnualLeaveBalanceService annualLeaveBalance,
    ISystemNotificationService notificationService)
    : ICommandHandler<ForceDeleteLeaveCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(ForceDeleteLeaveCommand request, CancellationToken cancellationToken)
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

            // Only owner or manager can force-delete
            if (!request.IsManager && leave.EmployeeUserId != request.ApplicationUserId)
            {
                return AppResponse<bool>.Error("You are not authorized to delete this leave request");
            }

            var restoreBalance = leave.Status == LeaveStatus.Approved && leave.AnnualBalanceApplied;
            var balanceRestored = restoreBalance && leave.AnnualLeaveDaysDeducted > 0;
            if (restoreBalance)
                await annualLeaveBalance.RestoreAsync(leave, cancellationToken);

            // Trước đây chuỗi viết «($range)» (thiếu ngoặc nhọn) → điện thoại hiện nguyên chữ «$range».
            var range = FormatRange(leave.StartDate, leave.EndDate);
            var employeeName = NotificationPushFormatter.FormatUserDisplayName(leave.EmployeeUser);
            if (string.IsNullOrWhiteSpace(employeeName)) employeeName = "nhân viên";
            var employeeId = leave.EmployeeUserId;
            var managerId = leave.ManagerId;

            // Chỉ cần tên để báo — không kéo tài khoản NV vào lệnh xóa.
            leave.EmployeeUser = null!;
            await leaveRepository.DeleteAsync(leave, cancellationToken);

            try
            {
                // Người tự xóa đơn thì không cần tự báo cho mình.
                if (employeeId != request.ApplicationUserId)
                {
                    await notificationService.CreateAndSendAsync(
                        employeeId,
                        NotificationType.Warning,
                        "Đơn nghỉ phép đã bị xóa",
                        $"Đơn nghỉ {range} của bạn đã bị xóa" +
                        (balanceRestored ? " · Đã hoàn lại ngày phép" : ""),
                        relatedEntityId: request.LeaveId,
                        relatedEntityType: "Leave",
                        fromUserId: request.ApplicationUserId,
                        categoryCode: "leave",
                        storeId: request.StoreId);
                }

                if (managerId != employeeId && managerId != request.ApplicationUserId)
                {
                    await notificationService.CreateAndSendAsync(
                        managerId,
                        NotificationType.Info,
                        "Đơn nghỉ phép đã bị xóa",
                        $"Đơn nghỉ {range} của {employeeName} đã bị xóa",
                        relatedEntityId: request.LeaveId,
                        relatedEntityType: "Leave",
                        fromUserId: request.ApplicationUserId,
                        categoryCode: "leave",
                        storeId: request.StoreId);
                }
            }
            catch { /* best-effort */ }

            return AppResponse<bool>.Success(true);
        }
        catch (Exception ex)
        {
            return AppResponse<bool>.Error(ex.Message);
        }
    }

    /// <summary>«12/11» (một ngày) hoặc «12/11–13/11».</summary>
    private static string FormatRange(DateTime start, DateTime end) =>
        start.Date == end.Date ? $"{start:dd/MM}" : $"{start:dd/MM}–{end:dd/MM}";
}
