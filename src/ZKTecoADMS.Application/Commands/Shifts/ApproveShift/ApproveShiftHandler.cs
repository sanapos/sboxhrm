using ZKTecoADMS.Application.DTOs.Shifts;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Shifts.ApproveShift;

public class ApproveShiftHandler(IShiftService shiftService, ISystemNotificationService notificationService) 
    : ICommandHandler<ApproveShiftCommand, AppResponse<ShiftDto>>
{
    public async Task<AppResponse<ShiftDto>> Handle(ApproveShiftCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var approvedShift = await shiftService.ApproveShiftAsync(
                request.StoreId,
                request.Id, 
                request.ApprovedByUserId, 
                cancellationToken);

            try
            {
                // «Ca 12/11 đã duyệt» / «Lê Thị Hoa: 07:00–15:00»
                var start = VnTimeHelper.AttendanceWallClock(approvedShift.StartTime);
                var end = VnTimeHelper.AttendanceWallClock(approvedShift.EndTime);
                await notificationService.CreateAndSendAsync(
                    approvedShift.EmployeeUserId, NotificationType.Success,
                    $"Ca {start:dd/MM} đã duyệt",
                    $"{start:HH:mm}–{end:HH:mm}",
                    relatedEntityId: approvedShift.Id, relatedEntityType: "Shift",
                    fromUserId: request.ApprovedByUserId, categoryCode: "shift", storeId: request.StoreId);
            }
            catch { /* Notification failure should not affect main operation */ }

            return AppResponse<ShiftDto>.Success(approvedShift.Adapt<ShiftDto>());
        }
        catch (InvalidOperationException ex)
        {
            return AppResponse<ShiftDto>.Error(ex.Message);
        }
    }
}
