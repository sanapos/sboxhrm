using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.ShiftSwaps.CancelSwap;

public class CancelSwapHandler(
    IRepository<ShiftSwapRequest> shiftSwapRepository,
    ISystemNotificationService notificationService
) : ICommandHandler<CancelSwapCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(
        CancelSwapCommand request,
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

            // Verify the canceller is the requester
            if (swapRequest.RequesterUserId != request.RequesterUserId)
            {
                return AppResponse<bool>.Error("Bạn không có quyền hủy yêu cầu này");
            }

            // Can only cancel pending or target accepted requests
            if (swapRequest.Status != ShiftSwapStatus.Pending && 
                swapRequest.Status != ShiftSwapStatus.TargetAccepted)
            {
                return AppResponse<bool>.Error("Không thể hủy yêu cầu đã được xử lý");
            }

            swapRequest.Status = ShiftSwapStatus.Cancelled;
            swapRequest.UpdatedAt = DateTime.UtcNow;

            await shiftSwapRepository.UpdateAsync(swapRequest, cancellationToken);

            try
            {
                await notificationService.CreateAndSendAsync(
                    swapRequest.TargetUserId, NotificationType.Info,
                    "Yêu cầu đổi ca đã hủy",
                    "Yêu cầu đổi ca đã bị hủy bởi người gửi",
                    relatedEntityId: swapRequest.Id, relatedEntityType: "ShiftSwap",
                    fromUserId: request.RequesterUserId, categoryCode: "attendance", storeId: request.StoreId);
            }
            catch { /* Notification failure should not affect main operation */ }

            return AppResponse<bool>.Success(true);
        }
        catch (Exception ex)
        {
            return AppResponse<bool>.Error($"Lỗi khi hủy yêu cầu đổi ca: {ex.Message}");
        }
    }
}
