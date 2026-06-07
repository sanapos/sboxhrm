using ZKTecoADMS.Application.Interfaces;
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

            if (leave.Status == LeaveStatus.Approved && leave.AnnualBalanceApplied)
                await annualLeaveBalance.RestoreAsync(leave, cancellationToken);

            var range =
                $"{leave.StartDate:dd/MM/yyyy} – {leave.EndDate:dd/MM/yyyy}";
            var employeeId = leave.EmployeeUserId;
            var managerId = leave.ManagerId;

            await leaveRepository.DeleteAsync(leave, cancellationToken);

            try
            {
                await notificationService.CreateAndSendAsync(
                    employeeId,
                    NotificationType.Warning,
                    "Đơn nghỉ phép đã bị xóa",
                    $"Đơn nghỉ phép ($range) đã bị xóa khỏi hệ thống.",
                    relatedEntityId: request.LeaveId,
                    relatedEntityType: "Leave",
                    fromUserId: request.ApplicationUserId,
                    categoryCode: "leave",
                    storeId: request.StoreId);

                if (managerId != employeeId)
                {
                    await notificationService.CreateAndSendAsync(
                        managerId,
                        NotificationType.Info,
                        "Đơn nghỉ phép đã bị xóa",
                        $"Đơn nghỉ phép ($range) đã bị xóa khỏi hệ thống.",
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
}
