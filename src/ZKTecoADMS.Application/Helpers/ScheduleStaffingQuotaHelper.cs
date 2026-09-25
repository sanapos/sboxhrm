using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Helpers;

public static class ScheduleStaffingQuotaHelper
{
    /// <summary>
    /// Returns an error message when approving would exceed MaxEmployees for the shift/day, or null if OK.
    /// </summary>
    public static async Task<string?> GetQuotaExceededMessageAsync(
        IRepository<ShiftStaffingQuota> quotaRepository,
        IRepository<WorkSchedule> workScheduleRepository,
        IRepository<ScheduleRegistration> registrationRepository,
        IRepository<Employee> employeeRepository,
        ScheduleRegistration registration,
        Guid storeId,
        CancellationToken cancellationToken = default)
    {
        if (registration.IsDayOff || registration.ShiftId == null)
            return null;

        var employee = registration.Employee
            ?? await employeeRepository.GetSingleAsync(
                e => e.Id == registration.EmployeeUserId && e.StoreId == storeId,
                cancellationToken: cancellationToken);
        var department = employee?.Department;

        var quotas = (await quotaRepository.GetAllAsync(
            q => q.StoreId == storeId && q.ShiftTemplateId == registration.ShiftId.Value,
            cancellationToken: cancellationToken)).ToList();

        if (quotas.Count == 0)
            return null;

        var quota = quotas.FirstOrDefault(q =>
                !string.IsNullOrWhiteSpace(q.Department)
                && !string.IsNullOrWhiteSpace(department)
                && string.Equals(q.Department, department, StringComparison.OrdinalIgnoreCase))
            ?? quotas.FirstOrDefault(q => string.IsNullOrWhiteSpace(q.Department));

        if (quota == null)
            return null;

        var workDate = registration.Date.Date;
        var dayEnd = workDate.AddDays(1);
        var (minLimit, maxLimit) = StaffingQuotaResolver.ResolveLimitsForDate(quota, workDate);
        if (maxLimit <= 0)
            return null;

        var shiftId = registration.ShiftId.Value;

        var workSchedules = (await workScheduleRepository.GetAllAsync(
            ws => ws.StoreId == storeId
                  && ws.Date >= workDate && ws.Date < dayEnd
                  && ws.ShiftId == shiftId
                  && !ws.IsDayOff,
            includeProperties: ["Employee"],
            cancellationToken: cancellationToken)).ToList();

        // Nhân viên đã có đúng ca này trên lịch → duyệt chỉ cập nhật, không thêm người.
        if (workSchedules.Any(ws => ws.EmployeeUserId == registration.EmployeeUserId))
            return null;

        bool InQuotaScope(Employee? emp)
        {
            if (string.IsNullOrWhiteSpace(quota.Department))
                return true;
            return emp != null
                   && !string.IsNullOrWhiteSpace(emp.Department)
                   && string.Equals(emp.Department, quota.Department, StringComparison.OrdinalIgnoreCase);
        }

        // Chỉ đếm người đã có trên lịch — phiếu chờ khác chưa chiếm chỗ (ai duyệt trước được trước).
        var scheduledCount = workSchedules.Count(ws => InQuotaScope(ws.Employee));
        if (scheduledCount + 1 > maxLimit)
        {
            var deptLabel = string.IsNullOrWhiteSpace(quota.Department) ? "" : $" ({quota.Department})";
            return $"Ca đã đủ định mức tối đa {maxLimit} nhân viên{deptLabel} ngày {workDate:dd/MM/yyyy} "
                   + $"(đã xếp {scheduledCount}, tối thiểu {minLimit}).";
        }

        return null;
    }
}
