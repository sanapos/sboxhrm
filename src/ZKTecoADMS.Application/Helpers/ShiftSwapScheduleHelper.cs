using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Helpers;

internal static class ShiftSwapScheduleHelper
{
    public static async Task<Employee?> FindEmployeeByUserAsync(
        IRepository<Employee> employeeRepository,
        Guid storeId,
        Guid applicationUserId,
        CancellationToken cancellationToken)
        => await employeeRepository.GetSingleAsync(
            e => e.ApplicationUserId == applicationUserId && e.StoreId == storeId,
            cancellationToken: cancellationToken);

    public static async Task<WorkSchedule?> FindAssignedShiftAsync(
        IRepository<WorkSchedule> workScheduleRepository,
        Guid storeId,
        Guid employeeId,
        DateTime date,
        Guid shiftId,
        CancellationToken cancellationToken)
    {
        var dayStart = date.Date;
        var dayEnd = dayStart.AddDays(1);
        var rows = await workScheduleRepository.GetAllAsync(
            ws => ws.StoreId == storeId
                  && ws.EmployeeUserId == employeeId
                  && ws.Date >= dayStart && ws.Date < dayEnd
                  && ws.ShiftId == shiftId
                  && !ws.IsDayOff,
            cancellationToken: cancellationToken);
        return rows.FirstOrDefault();
    }
}
