using ZKTecoADMS.Application.DTOs.Shifts;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Shifts.UpdateShift;

public class UpdateShiftHandler(IShiftService shiftService, ISystemNotificationService notificationService) 
    : ICommandHandler<UpdateShiftCommand, AppResponse<ShiftDto>>
{
    public async Task<AppResponse<ShiftDto>> Handle(UpdateShiftCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var updatedShift = await shiftService.UpdateShiftAsync(
                request.StoreId,
                request.Id,
                request.UpdatedByUserId,
                request.CheckInTime,
                request.CheckOutTime,
                cancellationToken);

            try
            {
                if (updatedShift.EmployeeUserId != request.UpdatedByUserId)
                {
                    await notificationService.CreateAndSendAsync(
                        updatedShift.EmployeeUserId, NotificationType.Info,
                        "Cập nhật ca làm việc",
                        $"Ca làm việc ngày {updatedShift.StartTime:dd/MM/yyyy} đã được cập nhật thời gian",
                        relatedEntityId: updatedShift.Id, relatedEntityType: "Shift",
                        fromUserId: request.UpdatedByUserId, categoryCode: "attendance", storeId: request.StoreId);
                }
            }
            catch { /* Notification failure should not affect main operation */ }

            return AppResponse<ShiftDto>.Success(updatedShift.Adapt<ShiftDto>());
        }
        catch (InvalidOperationException ex)
        {
            return AppResponse<ShiftDto>.Error(ex.Message);
        }
        catch (UnauthorizedAccessException ex)
        {
            return AppResponse<ShiftDto>.Error(ex.Message);
        }
    }
}
