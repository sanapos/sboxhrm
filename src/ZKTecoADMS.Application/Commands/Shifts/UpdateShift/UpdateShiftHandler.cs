using ZKTecoADMS.Application.DTOs.Shifts;
using ZKTecoADMS.Application.Helpers;
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
                    // Sửa giờ chấm vào / ra của ca (không đổi giờ ca).
                    // «Giờ chấm ca 12/11 đã sửa» / «Lê Thị Hoa: Vào 08:00 · Ra 17:00»
                    var day = VnTimeHelper.AttendanceWallClock(updatedShift.StartTime);
                    var parts = new List<string>();
                    if (request.CheckInTime.HasValue)
                        parts.Add($"Vào {VnTimeHelper.AttendanceWallClock(request.CheckInTime.Value):HH:mm}");
                    if (request.CheckOutTime.HasValue)
                        parts.Add($"Ra {VnTimeHelper.AttendanceWallClock(request.CheckOutTime.Value):HH:mm}");
                    await notificationService.CreateAndSendAsync(
                        updatedShift.EmployeeUserId, NotificationType.Info,
                        $"Giờ chấm ca {day:dd/MM} đã sửa",
                        parts.Count > 0 ? string.Join(" · ", parts) : "Giờ chấm công của ca đã được cập nhật",
                        relatedEntityId: updatedShift.Id, relatedEntityType: "Shift",
                        fromUserId: request.UpdatedByUserId, categoryCode: "shift", storeId: request.StoreId);
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
