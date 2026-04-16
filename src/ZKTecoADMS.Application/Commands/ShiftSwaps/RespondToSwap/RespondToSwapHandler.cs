using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.ShiftSwaps.RespondToSwap;

public class RespondToSwapHandler(
    IRepository<ShiftSwapRequest> shiftSwapRepository,
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
