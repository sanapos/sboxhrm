using Microsoft.AspNetCore.Identity;
using ZKTecoADMS.Application.DTOs.ShiftSwaps;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.ShiftSwaps.CreateShiftSwap;

public class CreateShiftSwapHandler(
    IRepository<ShiftSwapRequest> shiftSwapRepository,
    IRepository<Shift> shiftRepository,
    UserManager<ApplicationUser> userManager,
    ISystemNotificationService notificationService
) : ICommandHandler<CreateShiftSwapCommand, AppResponse<ShiftSwapRequestDto>>
{
    public async Task<AppResponse<ShiftSwapRequestDto>> Handle(
        CreateShiftSwapCommand request,
        CancellationToken cancellationToken)
    {
        try
        {
            // Validate requester and target are different
            if (request.RequesterUserId == request.TargetUserId)
            {
                return AppResponse<ShiftSwapRequestDto>.Error("Không thể đổi ca với chính mình");
            }

            // Validate shifts exist
            var requesterShift = await shiftRepository.GetByIdAsync(
                request.RequesterShiftId, cancellationToken: cancellationToken);
            if (requesterShift == null)
            {
                return AppResponse<ShiftSwapRequestDto>.Error("Ca làm việc của bạn không tồn tại");
            }

            var targetShift = await shiftRepository.GetByIdAsync(
                request.TargetShiftId, cancellationToken: cancellationToken);
            if (targetShift == null)
            {
                return AppResponse<ShiftSwapRequestDto>.Error("Ca làm việc của đồng nghiệp không tồn tại");
            }

            // Check for existing pending swap request
            var existingRequest = await shiftSwapRepository.GetSingleAsync(
                filter: r => r.StoreId == request.StoreId
                    && r.RequesterUserId == request.RequesterUserId
                    && r.TargetUserId == request.TargetUserId
                    && r.RequesterDate.Date == request.RequesterDate.Date
                    && r.TargetDate.Date == request.TargetDate.Date
                    && (r.Status == ShiftSwapStatus.Pending || r.Status == ShiftSwapStatus.TargetAccepted),
                cancellationToken: cancellationToken);

            if (existingRequest != null)
            {
                return AppResponse<ShiftSwapRequestDto>.Error("Đã có yêu cầu đổi ca tương tự đang chờ xử lý");
            }

            // Get user names for response
            var requester = await userManager.FindByIdAsync(request.RequesterUserId.ToString());
            var target = await userManager.FindByIdAsync(request.TargetUserId.ToString());

            var swapRequest = new ShiftSwapRequest
            {
                Id = Guid.NewGuid(),
                StoreId = request.StoreId,
                RequesterUserId = request.RequesterUserId,
                TargetUserId = request.TargetUserId,
                RequesterDate = request.RequesterDate.Date,
                RequesterShiftId = request.RequesterShiftId,
                TargetDate = request.TargetDate.Date,
                TargetShiftId = request.TargetShiftId,
                Reason = request.Reason,
                Status = ShiftSwapStatus.Pending,
                TargetAccepted = false,
                IsActive = true,
                CreatedAt = DateTime.UtcNow
            };

            await shiftSwapRepository.AddAsync(swapRequest, cancellationToken);

            try
            {
                var requesterName = requester != null ? $"{requester.LastName} {requester.FirstName}" : "N/A";
                await notificationService.CreateAndSendAsync(
                    request.TargetUserId, NotificationType.ApprovalRequired,
                    "Yêu cầu đổi ca mới",
                    $"{requesterName} gửi yêu cầu đổi ca ngày {request.RequesterDate:dd/MM/yyyy} với bạn",
                    relatedEntityId: swapRequest.Id, relatedEntityType: "ShiftSwap",
                    fromUserId: request.RequesterUserId, categoryCode: "attendance", storeId: request.StoreId);
            }
            catch { /* Notification failure should not affect main operation */ }

            var dto = new ShiftSwapRequestDto
            {
                Id = swapRequest.Id,
                StoreId = swapRequest.StoreId,
                RequesterUserId = swapRequest.RequesterUserId,
                RequesterName = requester != null ? $"{requester.LastName} {requester.FirstName}" : "N/A",
                RequesterDate = swapRequest.RequesterDate,
                RequesterShiftId = swapRequest.RequesterShiftId,
                RequesterShiftName = FormatShiftName(requesterShift),
                TargetUserId = swapRequest.TargetUserId,
                TargetName = target != null ? $"{target.LastName} {target.FirstName}" : "N/A",
                TargetDate = swapRequest.TargetDate,
                TargetShiftId = swapRequest.TargetShiftId,
                TargetShiftName = FormatShiftName(targetShift),
                Reason = swapRequest.Reason,
                Status = swapRequest.Status,
                StatusText = GetStatusText(swapRequest.Status),
                TargetAccepted = swapRequest.TargetAccepted,
                CreatedAt = swapRequest.CreatedAt
            };

            return AppResponse<ShiftSwapRequestDto>.Success(dto);
        }
        catch (Exception ex)
        {
            return AppResponse<ShiftSwapRequestDto>.Error($"Lỗi khi tạo yêu cầu đổi ca: {ex.Message}");
        }
    }

    private static string GetStatusText(ShiftSwapStatus status)
    {
        return status switch
        {
            ShiftSwapStatus.Pending => "Chờ xác nhận",
            ShiftSwapStatus.TargetAccepted => "Chờ quản lý duyệt",
            ShiftSwapStatus.Approved => "Đã duyệt",
            ShiftSwapStatus.RejectedByTarget => "Đồng nghiệp từ chối",
            ShiftSwapStatus.RejectedByManager => "Quản lý từ chối",
            ShiftSwapStatus.Cancelled => "Đã hủy",
            _ => "Không xác định"
        };
    }

    private static string FormatShiftName(Shift shift)
    {
        if (shift.Description != null)
            return shift.Description;
        return $"{shift.StartTime:HH:mm} - {shift.EndTime:HH:mm}";
    }
}
