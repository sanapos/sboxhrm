using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Shifts.DeleteShift;

public class DeleteShiftHandler(
    IRepository<Shift> repository,
    ISystemNotificationService notificationService,
    INotificationTargetResolver targetResolver)
    : ICommandHandler<DeleteShiftCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(DeleteShiftCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var shift = await repository.GetSingleAsync(
                s => s.Id == request.Id && s.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            
            if (shift == null)
            {
                return AppResponse<bool>.Error("Shift not found");
            }

            // Only allow deletion of pending shifts
            if (shift.Status != ShiftStatus.Pending)
            {
                return AppResponse<bool>.Error($"Cannot delete shift with status {shift.Status}");
            }

            var employeeUserId = shift.EmployeeUserId;
            var shiftDate = shift.StartTime;
            await repository.DeleteAsync(shift, cancellationToken);

            // Notify employee + 2-level dept managers + store admins per the org chart.
            try
            {
                if (employeeUserId != Guid.Empty)
                {
                    var targets = await targetResolver.ResolveEmployeeAndManagersAsync(
                        employeeUserId, request.StoreId, hierarchyLevels: 2, cancellationToken);
                    if (targets.Count > 0)
                    {
                        await notificationService.CreateAndSendToUsersAsync(
                            targets, NotificationType.Warning,
                            "Ca làm việc đã bị xóa",
                            $"Ca làm việc ngày {shiftDate:dd/MM/yyyy} đã bị xóa.",
                            relatedEntityId: request.Id, relatedEntityType: "Shift",
                            categoryCode: "shift", storeId: request.StoreId);
                    }
                }
            }
            catch { /* notification is best-effort */ }

            return AppResponse<bool>.Success(true);
        }
        catch (InvalidOperationException ex)
        {
            return AppResponse<bool>.Error(ex.Message);
        }
    }
}
