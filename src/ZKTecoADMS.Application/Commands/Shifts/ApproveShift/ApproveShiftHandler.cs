using ZKTecoADMS.Application.DTOs.Shifts;
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
                await notificationService.CreateAndSendAsync(
                    approvedShift.EmployeeUserId, NotificationType.Success,
                    "Ca làm việc được duyệt",
                    $"Ca làm việc ngày {approvedShift.StartTime:dd/MM/yyyy} đã được duyệt",
                    relatedEntityId: approvedShift.Id, relatedEntityType: "Shift",
                    fromUserId: request.ApprovedByUserId, categoryCode: "attendance", storeId: request.StoreId);
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
