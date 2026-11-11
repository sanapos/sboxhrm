using ScheduleNotifyText = ZKTecoADMS.Application.Commands.WorkSchedules.ScheduleNotifyText;
using ZKTecoADMS.Application.Notifications;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.ShiftSwaps.RespondToSwap;

public class RespondToSwapHandler(
    IRepository<ShiftSwapRequest> shiftSwapRepository,
    IRepository<Employee> employeeRepository,
    ISystemNotificationService notificationService
) : ICommandHandler<RespondToSwapCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(
        RespondToSwapCommand request,
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

            // Verify the respondent is the target user
            if (swapRequest.TargetUserId != request.TargetUserId)
            {
                return AppResponse<bool>.Error("Bạn không có quyền phản hồi yêu cầu này");
            }

            // Check if already responded
            if (swapRequest.Status != ShiftSwapStatus.Pending)
            {
                return AppResponse<bool>.Error("Yêu cầu đổi ca đã được xử lý");
            }

            if (request.Accept)
            {
                var vnToday = DateTime.UtcNow.AddHours(7).Date;
                if (swapRequest.RequesterDate.Date < vnToday || swapRequest.TargetDate.Date < vnToday)
                    return AppResponse<bool>.Error("Ca đổi đã qua ngày, không thể chấp nhận");

                swapRequest.TargetAccepted = true;
                swapRequest.Status = ShiftSwapStatus.TargetAccepted;
                swapRequest.TargetResponseDate = DateTime.UtcNow;
            }
            else
            {
                swapRequest.Status = ShiftSwapStatus.RejectedByTarget;
                swapRequest.RejectionReason = request.RejectionReason;
                swapRequest.TargetResponseDate = DateTime.UtcNow;
            }

            swapRequest.UpdatedAt = DateTime.UtcNow;
            await shiftSwapRepository.UpdateAsync(swapRequest, cancellationToken);

            try
            {
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

                // Người gửi = đồng nghiệp (tên ở tiêu đề nên formatter không chèn lại vào body).
                // Đồng ý:  «Trần Thị Bình đồng ý đổi ca» / «Ca Sáng 12/11 ⇄ Ca Chiều 14/11 · Chờ quản lý duyệt»
                // Từ chối: «Trần Thị Bình từ chối đổi ca» / «Bạn giữ Ca Sáng 12/11 như cũ · Lý do: Bận việc»
                var notifType = request.Accept ? NotificationType.Success : NotificationType.Warning;
                var who = string.IsNullOrWhiteSpace(targetName) ? "Đồng nghiệp" : targetName;
                var notifTitle = request.Accept ? $"{who} đồng ý đổi ca" : $"{who} từ chối đổi ca";
                var notifMsg = request.Accept
                    ? $"{requesterSlot} ⇄ {targetSlot} · Chờ quản lý duyệt"
                    : string.IsNullOrEmpty(reason)
                        ? $"Bạn giữ {requesterSlot} như cũ"
                        : $"Bạn giữ {requesterSlot} như cũ · Lý do: {reason}";
                await notificationService.CreateAndSendAsync(
                    swapRequest.RequesterUserId, notifType, notifTitle, notifMsg,
                    relatedEntityId: swapRequest.Id, relatedEntityType: "ShiftSwap",
                    fromUserId: request.TargetUserId, categoryCode: "shift", storeId: request.StoreId);

                // Đồng nghiệp đã đồng ý → báo quản lý trực tiếp của người yêu cầu để duyệt.
                if (request.Accept)
                {
                    var requesterEmp = await employeeRepository.GetSingleAsync(
                        e => e.ApplicationUserId == swapRequest.RequesterUserId && e.StoreId == request.StoreId,
                        cancellationToken: cancellationToken);
                    if (requesterEmp?.DirectManagerEmployeeId != null)
                    {
                        var mgr = await employeeRepository.GetSingleAsync(
                            e => e.Id == requesterEmp.DirectManagerEmployeeId.Value, cancellationToken: cancellationToken);
                        if (mgr?.ApplicationUserId != null)
                        {
                            // «Cần duyệt đổi ca» / «Nguyễn Văn An · Ca Sáng 12/11 ⇄ Ca Chiều 14/11 với Trần Thị Bình (đã đồng ý)»
                            var requesterLabel = string.IsNullOrWhiteSpace(requesterName) ? "Nhân viên" : requesterName;
                            var partnerText = string.IsNullOrWhiteSpace(targetName)
                                ? " (đồng nghiệp đã đồng ý)"
                                : $" với {targetName} (đã đồng ý)";
                            await notificationService.CreateAndSendAsync(
                                mgr.ApplicationUserId.Value, NotificationType.ApprovalRequired,
                                "Cần duyệt đổi ca",
                                $"{requesterLabel} · {requesterSlot} ⇄ {targetSlot}{partnerText}",
                                relatedEntityId: swapRequest.Id, relatedEntityType: "ShiftSwap",
                                fromUserId: swapRequest.RequesterUserId, categoryCode: "shift", storeId: request.StoreId);
                        }
                    }
                }
            }
            catch { /* Notification failure should not affect main operation */ }

            return AppResponse<bool>.Success(true);
        }
        catch (Exception ex)
        {
            return AppResponse<bool>.Error($"Lỗi khi phản hồi yêu cầu đổi ca: {ex.Message}");
        }
    }
}
