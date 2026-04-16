using ZKTecoADMS.Application.DTOs.Shifts;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Shifts.RejectShift;

public class RejectShiftHandler(IShiftService shiftService, ISystemNotificationService notificationService) 
    : ICommandHandler<RejectShiftCommand, AppResponse<ShiftDto>>
{
    public async Task<AppResponse<ShiftDto>> Handle(RejectShiftCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var rejectedShift = await shiftService.RejectShiftAsync(
                request.StoreId,
                request.Id,
                request.RejectedByUserId,
                request.RejectionReason,
                cancellationToken);

            try
            {
                var message = $"Ca làm việc ngày {rejectedShift.StartTime:dd/MM/yyyy} đã bị từ chối";
                if (!string.IsNullOrEmpty(request.RejectionReason))
                    message += $". Lý do: {request.RejectionReason}";
                await notificationService.CreateAndSendAsync(
                    rejectedShift.EmployeeUserId, NotificationType.Warning,
                    "Ca làm việc bị từ chối",
                    message,
                    relatedEntityId: rejectedShift.Id, relatedEntityType: "Shift",
                    fromUserId: request.RejectedByUserId, categoryCode: "attendance", storeId: request.StoreId);
            }
            catch { /* Notification failure should not affect main operation */ }
            
            return AppResponse<ShiftDto>.Success(rejectedShift.Adapt<ShiftDto>());
        }
        catch (ArgumentException ex)
        {
            return AppResponse<ShiftDto>.Error(ex.Message);
        }
        catch (InvalidOperationException ex)
        {
            return AppResponse<ShiftDto>.Error(ex.Message);
        }
    }
}
