using ZKTecoADMS.Application.Helpers;
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
                return AppResponse<bool>.Error("Yêu cầu đổi ca không tồn tại");

            if (swapRequest.Status != ShiftSwapStatus.TargetAccepted)
                return AppResponse<bool>.Error("Yêu cầu đổi ca chưa được đồng nghiệp chấp nhận");

            if (request.Approve)
            {
                var swapped = await SwapWorkSchedules(swapRequest, cancellationToken);
                if (!swapped.IsSuccess)
                    return swapped;

                swapRequest.Status = ShiftSwapStatus.Approved;
                swapRequest.ApprovedByManagerId = request.ManagerId;
                swapRequest.ManagerApprovalDate = DateTime.UtcNow;
                swapRequest.Note = request.Note;
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
            catch { }

            return AppResponse<bool>.Success(true);
        }
        catch (Exception ex)
        {
            return AppResponse<bool>.Error($"Lỗi khi xử lý yêu cầu đổi ca: {ex.Message}");
        }
    }

    private async Task<AppResponse<bool>> SwapWorkSchedules(
        ShiftSwapRequest swapRequest,
        CancellationToken cancellationToken)
    {
        var requesterEmployee = await ShiftSwapScheduleHelper.FindEmployeeByUserAsync(
            employeeRepository, swapRequest.StoreId, swapRequest.RequesterUserId, cancellationToken);
        var targetEmployee = await ShiftSwapScheduleHelper.FindEmployeeByUserAsync(
            employeeRepository, swapRequest.StoreId, swapRequest.TargetUserId, cancellationToken);

        if (requesterEmployee == null || targetEmployee == null)
            return AppResponse<bool>.Error("Không tìm thấy hồ sơ nhân viên để hoán đổi lịch");

        var requesterSchedule = await ShiftSwapScheduleHelper.FindAssignedShiftAsync(
            workScheduleRepository, swapRequest.StoreId, requesterEmployee.Id,
            swapRequest.RequesterDate, swapRequest.RequesterShiftId, cancellationToken);
        var targetSchedule = await ShiftSwapScheduleHelper.FindAssignedShiftAsync(
            workScheduleRepository, swapRequest.StoreId, targetEmployee.Id,
            swapRequest.TargetDate, swapRequest.TargetShiftId, cancellationToken);

        if (requesterSchedule == null || targetSchedule == null)
            return AppResponse<bool>.Error(
                "Không hoán đổi được: một trong hai người không còn ca đã xếp trên lịch");

        var requesterAlreadyHasTarget = await ShiftSwapScheduleHelper.FindAssignedShiftAsync(
            workScheduleRepository, swapRequest.StoreId, requesterEmployee.Id,
            swapRequest.TargetDate, swapRequest.TargetShiftId, cancellationToken);
        if (requesterAlreadyHasTarget != null && requesterAlreadyHasTarget.Id != requesterSchedule.Id)
            return AppResponse<bool>.Error("Người yêu cầu đã có ca đích trong ngày đó");

        var targetAlreadyHasRequester = await ShiftSwapScheduleHelper.FindAssignedShiftAsync(
            workScheduleRepository, swapRequest.StoreId, targetEmployee.Id,
            swapRequest.RequesterDate, swapRequest.RequesterShiftId, cancellationToken);
        if (targetAlreadyHasRequester != null && targetAlreadyHasRequester.Id != targetSchedule.Id)
            return AppResponse<bool>.Error("Đồng nghiệp đã có ca của người yêu cầu trong ngày đó");

        requesterSchedule.Date = swapRequest.TargetDate.Date;
        requesterSchedule.ShiftId = swapRequest.TargetShiftId;
        requesterSchedule.UpdatedAt = DateTime.UtcNow;
        await workScheduleRepository.UpdateAsync(requesterSchedule, cancellationToken);

        targetSchedule.Date = swapRequest.RequesterDate.Date;
        targetSchedule.ShiftId = swapRequest.RequesterShiftId;
        targetSchedule.UpdatedAt = DateTime.UtcNow;
        await workScheduleRepository.UpdateAsync(targetSchedule, cancellationToken);

        return AppResponse<bool>.Success(true);
    }
}
