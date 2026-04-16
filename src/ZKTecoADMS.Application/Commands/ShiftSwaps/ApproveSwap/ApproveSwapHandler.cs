using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.ShiftSwaps.ApproveSwap;

public class ApproveSwapHandler(
    IRepository<ShiftSwapRequest> shiftSwapRepository,
    IRepository<WorkSchedule> workScheduleRepository,
    IRepository<Employee> employeeRepository,
    ISystemNotificationService notificationService
) : ICommandHandler<ApproveSwapCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(
        ApproveSwapCommand request,
        CancellationToken cancellationToken)
    {
        try
        {
            var swapRequest = await shiftSwapRepository.GetSingleAsync(
                filter: r => r.Id == request.SwapRequestId && r.StoreId == request.StoreId,
                cancellationToken: cancellationToken);

            if (swapRequest == null)
            {
                return AppResponse<bool>.Error("Yêu cầu đổi ca không tồn tại");
            }

            // Check if target has accepted
            if (swapRequest.Status != ShiftSwapStatus.TargetAccepted)
            {
                return AppResponse<bool>.Error("Yêu cầu đổi ca chưa được đồng nghiệp chấp nhận");
            }

            if (request.Approve)
            {
                swapRequest.Status = ShiftSwapStatus.Approved;
                swapRequest.ApprovedByManagerId = request.ManagerId;
                swapRequest.ManagerApprovalDate = DateTime.UtcNow;
                swapRequest.Note = request.Note;

                // Swap the work schedules
                await SwapWorkSchedules(swapRequest, cancellationToken);
            }
            else
            {
                swapRequest.Status = ShiftSwapStatus.RejectedByManager;
                swapRequest.RejectionReason = request.RejectionReason;
                swapRequest.ApprovedByManagerId = request.ManagerId;
                swapRequest.ManagerApprovalDate = DateTime.UtcNow;
            }

            swapRequest.UpdatedAt = DateTime.UtcNow;
            await shiftSwapRepository.UpdateAsync(swapRequest, cancellationToken);

            try
            {
                var notifType = request.Approve ? NotificationType.Success : NotificationType.Warning;
                var notifTitle = request.Approve ? "Yêu cầu đổi ca đã duyệt" : "Yêu cầu đổi ca bị từ chối";
                var notifMsg = request.Approve
                    ? "Yêu cầu đổi ca của bạn đã được quản lý phê duyệt"
                    : $"Yêu cầu đổi ca của bạn đã bị quản lý từ chối. Lý do: {request.RejectionReason}";
                await notificationService.CreateAndSendAsync(
                    swapRequest.RequesterUserId, notifType, notifTitle, notifMsg,
                    relatedEntityId: swapRequest.Id, relatedEntityType: "ShiftSwap",
                    fromUserId: request.ManagerId, categoryCode: "approval", storeId: request.StoreId);
                await notificationService.CreateAndSendAsync(
                    swapRequest.TargetUserId, notifType, notifTitle, notifMsg,
                    relatedEntityId: swapRequest.Id, relatedEntityType: "ShiftSwap",
                    fromUserId: request.ManagerId, categoryCode: "approval", storeId: request.StoreId);
            }
            catch { /* Notification failure should not affect main operation */ }

            return AppResponse<bool>.Success(true);
        }
        catch (Exception ex)
        {
            return AppResponse<bool>.Error($"Lỗi khi xử lý yêu cầu đổi ca: {ex.Message}");
        }
    }

    private async Task SwapWorkSchedules(ShiftSwapRequest swapRequest, CancellationToken cancellationToken)
    {
        // Convert ApplicationUserId to Employee.Id (WorkSchedule.EmployeeId references Employee table, not ApplicationUser)
        var requesterEmployee = await employeeRepository.GetSingleAsync(
            filter: e => e.ApplicationUserId == swapRequest.RequesterUserId && e.StoreId == swapRequest.StoreId,
            cancellationToken: cancellationToken);
        var targetEmployee = await employeeRepository.GetSingleAsync(
            filter: e => e.ApplicationUserId == swapRequest.TargetUserId && e.StoreId == swapRequest.StoreId,
            cancellationToken: cancellationToken);

        if (requesterEmployee == null || targetEmployee == null)
        {
            return; // Cannot swap if employees not found
        }

        // Find requester's work schedule for that date
        var requesterSchedule = await workScheduleRepository.GetSingleAsync(
            filter: ws => ws.StoreId == swapRequest.StoreId
                && ws.EmployeeUserId == requesterEmployee.ApplicationUserId
                && ws.Date.Date == swapRequest.RequesterDate.Date,
            cancellationToken: cancellationToken);

        // Find target's work schedule for that date
        var targetSchedule = await workScheduleRepository.GetSingleAsync(
            filter: ws => ws.StoreId == swapRequest.StoreId
                && ws.EmployeeUserId == targetEmployee.ApplicationUserId
                && ws.Date.Date == swapRequest.TargetDate.Date,
            cancellationToken: cancellationToken);

        // Update schedules if they exist, or create new ones
        if (requesterSchedule != null)
        {
            // Swap requester to target's shift/date
            requesterSchedule.Date = swapRequest.TargetDate;
            requesterSchedule.ShiftId = swapRequest.TargetShiftId;
            requesterSchedule.UpdatedAt = DateTime.UtcNow;
            await workScheduleRepository.UpdateAsync(requesterSchedule, cancellationToken);
        }
        else
        {
            // Create new schedule for requester
            var newRequesterSchedule = new WorkSchedule
            {
                Id = Guid.NewGuid(),
                StoreId = swapRequest.StoreId,
                EmployeeUserId = requesterEmployee.ApplicationUserId!.Value,
                Date = swapRequest.TargetDate,
                ShiftId = swapRequest.TargetShiftId,
                CreatedAt = DateTime.UtcNow
            };
            await workScheduleRepository.AddAsync(newRequesterSchedule, cancellationToken);
        }

        if (targetSchedule != null)
        {
            // Swap target to requester's shift/date
            targetSchedule.Date = swapRequest.RequesterDate;
            targetSchedule.ShiftId = swapRequest.RequesterShiftId;
            targetSchedule.UpdatedAt = DateTime.UtcNow;
            await workScheduleRepository.UpdateAsync(targetSchedule, cancellationToken);
        }
        else
        {
            // Create new schedule for target
            var newTargetSchedule = new WorkSchedule
            {
                Id = Guid.NewGuid(),
                StoreId = swapRequest.StoreId,
                EmployeeUserId = targetEmployee.ApplicationUserId!.Value,
                Date = swapRequest.RequesterDate,
                ShiftId = swapRequest.RequesterShiftId,
                CreatedAt = DateTime.UtcNow
            };
            await workScheduleRepository.AddAsync(newTargetSchedule, cancellationToken);
        }
    }
}
