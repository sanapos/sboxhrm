using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Shifts.DeleteShift;

public class DeleteShiftHandler(
    IRepository<Shift> repository,
    IRepository<Employee> employeeRepository,
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
            var shiftStart = VnTimeHelper.AttendanceWallClock(shift.StartTime);
            var shiftEnd = VnTimeHelper.AttendanceWallClock(shift.EndTime);
            await repository.DeleteAsync(shift, cancellationToken);

            // Notify employee + 2-level dept managers + store admins per the org chart.
            try
            {
                if (employeeUserId != Guid.Empty)
                {
                    // Cùng nhóm người nhận như trước (NV + quản lý 2 cấp + admin), nhưng tách câu:
                    // NV: «Ca 12/11 của bạn đã bị xóa» / «07:00–15:00 · Ca đang chờ duyệt»
                    // Quản lý: «Đã xóa ca của Nguyễn Văn An» / «12/11 · 07:00–15:00»
                    var hours = $"{shiftStart:HH:mm}–{shiftEnd:HH:mm}";
                    await notificationService.CreateAndSendAsync(
                        employeeUserId, NotificationType.Warning,
                        $"Ca {shiftStart:dd/MM} của bạn đã bị xóa",
                        $"{hours} · Ca đang chờ duyệt",
                        relatedEntityId: request.Id, relatedEntityType: "Shift",
                        categoryCode: "shift", storeId: request.StoreId);

                    var managers = (await targetResolver.ResolveManagersAsync(
                            employeeUserId, request.StoreId, hierarchyLevels: 2, cancellationToken))
                        .Where(id => id != employeeUserId)
                        .ToList();
                    if (managers.Count > 0)
                    {
                        var employee = await employeeRepository.GetSingleAsync(
                            e => e.ApplicationUserId == employeeUserId && e.StoreId == request.StoreId,
                            cancellationToken: cancellationToken);
                        var name = $"{employee?.LastName} {employee?.FirstName}".Trim();
                        await notificationService.CreateAndSendToUsersAsync(
                            managers, NotificationType.Warning,
                            string.IsNullOrEmpty(name) ? "Đã xóa ca chờ duyệt" : $"Đã xóa ca của {name}",
                            $"{shiftStart:dd/MM} · {hours}",
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
