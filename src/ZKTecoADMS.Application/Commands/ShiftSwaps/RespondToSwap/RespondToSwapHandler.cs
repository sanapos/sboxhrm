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
                var notifType = request.Accept ? NotificationType.Success : NotificationType.Warning;
                var notifTitle = request.Accept ? "Đồng nghiệp chấp nhận đổi ca" : "Đồng nghiệp từ chối đổi ca";
                var notifMsg = request.Accept
                    ? "Yêu cầu đổi ca của bạn đã được đồng nghiệp chấp nhận, đang chờ quản lý duyệt"
                    : $"Yêu cầu đổi ca của bạn đã bị đồng nghiệp từ chối. Lý do: {request.RejectionReason}";
                await notificationService.CreateAndSendAsync(
                    swapRequest.RequesterUserId, notifType, notifTitle, notifMsg,
                    relatedEntityId: swapRequest.Id, relatedEntityType: "ShiftSwap",
                    fromUserId: request.TargetUserId, categoryCode: "attendance", storeId: request.StoreId);

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
                            await notificationService.CreateAndSendAsync(
                                mgr.ApplicationUserId.Value, NotificationType.ApprovalRequired,
                                "Đổi ca cần duyệt",
                                $"Yêu cầu đổi ca ngày {swapRequest.RequesterDate:dd/MM/yyyy} ⇄ {swapRequest.TargetDate:dd/MM/yyyy} đã được đồng nghiệp chấp nhận, chờ bạn duyệt",
                                relatedEntityId: swapRequest.Id, relatedEntityType: "ShiftSwap",
                                fromUserId: swapRequest.RequesterUserId, categoryCode: "approval", storeId: request.StoreId);
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
