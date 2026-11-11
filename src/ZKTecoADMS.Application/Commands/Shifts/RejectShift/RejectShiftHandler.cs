using ZKTecoADMS.Application.DTOs.Shifts;
using ZKTecoADMS.Application.Helpers;
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
                // «Ca 12/11 bị từ chối» / «Lê Thị Hoa: 07:00–15:00 · Lý do: Đủ người»
                var start = VnTimeHelper.AttendanceWallClock(rejectedShift.StartTime);
                var end = VnTimeHelper.AttendanceWallClock(rejectedShift.EndTime);
                var message = $"{start:HH:mm}–{end:HH:mm}";
                if (!string.IsNullOrWhiteSpace(request.RejectionReason))
                    message += $" · Lý do: {request.RejectionReason.Trim()}";
                await notificationService.CreateAndSendAsync(
                    rejectedShift.EmployeeUserId, NotificationType.Warning,
                    $"Ca {start:dd/MM} bị từ chối",
                    message,
                    relatedEntityId: rejectedShift.Id, relatedEntityType: "Shift",
                    fromUserId: request.RejectedByUserId, categoryCode: "shift", storeId: request.StoreId);
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
