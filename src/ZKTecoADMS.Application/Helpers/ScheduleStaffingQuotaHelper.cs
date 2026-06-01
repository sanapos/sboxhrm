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

        if (quota == null || quota.MaxEmployees <= 0)
            return null;

        var workDate = registration.Date.Date;
        var shiftId = registration.ShiftId.Value;

        var workSchedules = (await workScheduleRepository.GetAllAsync(
            ws => ws.StoreId == storeId
                  && ws.Date.Date == workDate
                  && ws.ShiftId == shiftId
                  && !ws.IsDayOff
                  && ws.Deleted == null,
            includeProperties: ["Employee"],
            cancellationToken: cancellationToken)).ToList();

        var pendingRegs = (await registrationRepository.GetAllAsync(
            r => r.StoreId == storeId
                 && r.Date.Date == workDate
                 && r.ShiftId == shiftId
                 && !r.IsDayOff
                 && r.Status == ScheduleRegistrationStatus.Pending
                 && r.Id != registration.Id,
            includeProperties: ["Employee"],
            cancellationToken: cancellationToken)).ToList();

        bool InQuotaScope(Employee? emp)
        {
            if (string.IsNullOrWhiteSpace(quota.Department))
                return true;
            return emp != null
                   && !string.IsNullOrWhiteSpace(emp.Department)
                   && string.Equals(emp.Department, quota.Department, StringComparison.OrdinalIgnoreCase);
        }

        var scheduledCount = workSchedules.Count(ws => InQuotaScope(ws.Employee));
        var pendingCount = pendingRegs.Count(r => InQuotaScope(r.Employee));

        if (scheduledCount + pendingCount + 1 > quota.MaxEmployees)
        {
            return $"Ca đã đủ định mức tối đa {quota.MaxEmployees} nhân viên ngày {workDate:dd/MM/yyyy} "
                   + $"(hiện {scheduledCount} đã xếp + {pendingCount} chờ duyệt).";
        }

        return null;
    }
}
