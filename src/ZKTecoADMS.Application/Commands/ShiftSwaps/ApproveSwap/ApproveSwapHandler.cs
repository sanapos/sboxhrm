using ScheduleNotifyText = ZKTecoADMS.Application.Commands.WorkSchedules.ScheduleNotifyText;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Notifications;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.ShiftSwaps.ApproveSwap;

public class ApproveSwapHandler(
    IRepository<ShiftSwapRequest> shiftSwapRepository,
    IRepository<WorkSchedule> workScheduleRepository,
    IRepository<Employee> employeeRepository,
    IRepository<ShiftStaffingQuota> quotaRepository,
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

            if (request.ManagerId == swapRequest.RequesterUserId || request.ManagerId == swapRequest.TargetUserId)
                return AppResponse<bool>.Error("Bạn là một bên của yêu cầu đổi ca này nên không thể tự duyệt");

            if (request.Approve)
            {
                var vnToday = DateTime.UtcNow.AddHours(7).Date;
                if (swapRequest.RequesterDate.Date < vnToday || swapRequest.TargetDate.Date < vnToday)
                    return AppResponse<bool>.Error("Ca đổi đã qua ngày, không thể duyệt — hãy từ chối yêu cầu này");

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
                // Mỗi bên một câu, theo góc nhìn của mình (trước đây người được đổi cũng nhận «Yêu cầu đổi ca của bạn…»).
                // Người gửi = quản lý → formatter thêm «Lê Thị Hoa: » trước body.
                // Duyệt:    «Đổi ca với Trần Thị Bình đã duyệt» / «Bạn chuyển sang Ca Chiều 14/11, thay cho Ca Sáng 12/11»
                // Từ chối:  «Đổi ca với Trần Thị Bình bị từ chối» / «Bạn giữ Ca Sáng 12/11 như cũ · Lý do: Đủ người»
                var info = await shiftSwapRepository.GetSingleAsync(
                    r => r.Id == swapRequest.Id,
                    includeProperties: [
                        nameof(ShiftSwapRequest.RequesterUser), nameof(ShiftSwapRequest.TargetUser),
                        nameof(ShiftSwapRequest.RequesterShift), nameof(ShiftSwapRequest.TargetShift)
                    ],
                    cancellationToken: cancellationToken);
                var requesterSlot = ScheduleNotifyText.ShiftOnDay(info?.RequesterShift, swapRequest.RequesterDate);
                var targetSlot = ScheduleNotifyText.ShiftOnDay(info?.TargetShift, swapRequest.TargetDate);
                var requesterName = NotificationPushFormatter.FormatUserDisplayName(info?.RequesterUser);
                var targetName = NotificationPushFormatter.FormatUserDisplayName(info?.TargetUser);
                var reason = request.RejectionReason?.Trim();
                var notifType = request.Approve ? NotificationType.Success : NotificationType.Warning;
                var result = request.Approve ? "đã duyệt" : "bị từ chối";

                string Title(string otherName) => string.IsNullOrWhiteSpace(otherName)
                    ? $"Đổi ca {result}"
                    : $"Đổi ca với {otherName} {result}";
                string Body(string mySlot, string theirSlot) => request.Approve
                    ? $"Bạn chuyển sang {theirSlot}, thay cho {mySlot}"
                    : string.IsNullOrEmpty(reason)
                        ? $"Bạn giữ {mySlot} như cũ"
                        : $"Bạn giữ {mySlot} như cũ · Lý do: {reason}";

                await notificationService.CreateAndSendAsync(
                    swapRequest.RequesterUserId, notifType,
                    Title(targetName), Body(requesterSlot, targetSlot),
                    relatedEntityId: swapRequest.Id, relatedEntityType: "ShiftSwap",
                    fromUserId: request.ManagerId, categoryCode: "shift", storeId: request.StoreId);
                await notificationService.CreateAndSendAsync(
                    swapRequest.TargetUserId, notifType,
                    Title(requesterName), Body(targetSlot, requesterSlot),
                    relatedEntityId: swapRequest.Id, relatedEntityType: "ShiftSwap",
                    fromUserId: request.ManagerId, categoryCode: "shift", storeId: request.StoreId);
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

        var quotaError = await ScheduleStaffingQuotaHelper.GetSwapQuotaMessageAsync(
            quotaRepository, workScheduleRepository, requesterEmployee, targetEmployee,
            swapRequest.RequesterDate, swapRequest.RequesterShiftId,
            swapRequest.TargetDate, swapRequest.TargetShiftId, swapRequest.StoreId, cancellationToken);
        if (quotaError != null)
            return AppResponse<bool>.Error(quotaError);

        // Giờ ghi đè (StartTime/EndTime) thuộc ca cũ → bỏ để ca mới dùng giờ của mẫu ca.
        requesterSchedule.Date = swapRequest.TargetDate.Date;
        requesterSchedule.ShiftId = swapRequest.TargetShiftId;
        requesterSchedule.StartTime = null;
        requesterSchedule.EndTime = null;
        requesterSchedule.UpdatedAt = DateTime.UtcNow;
        targetSchedule.Date = swapRequest.RequesterDate.Date;
        targetSchedule.ShiftId = swapRequest.RequesterShiftId;
        targetSchedule.StartTime = null;
        targetSchedule.EndTime = null;
        targetSchedule.UpdatedAt = DateTime.UtcNow;
        // Một lần SaveChanges — không còn cảnh một người đổi được, người kia không.
        await workScheduleRepository.UpdateRangeAsync([requesterSchedule, targetSchedule], cancellationToken);

        return AppResponse<bool>.Success(true);
    }
}
