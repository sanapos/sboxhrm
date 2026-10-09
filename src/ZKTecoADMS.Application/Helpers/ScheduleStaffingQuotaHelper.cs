using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Helpers;

public static class ScheduleStaffingQuotaHelper
{
    /// <summary>
    /// Đổi ca giữa hai nhân viên khác bộ phận làm đổi số người từng bộ phận trong mỗi ca.
    /// Trả thông báo nếu bên nhận ca vượt định mức tối đa của bộ phận mình; cùng bộ phận thì số người không đổi.
    /// </summary>
    public static async Task<string?> GetSwapQuotaMessageAsync(
        IRepository<ShiftStaffingQuota> quotaRepository,
        IRepository<WorkSchedule> workScheduleRepository,
        Employee requester,
        Employee target,
        DateTime requesterDate, Guid requesterShiftId,
        DateTime targetDate, Guid targetShiftId,
        Guid storeId,
        CancellationToken cancellationToken = default)
    {
        if (string.Equals(requester.Department?.Trim(), target.Department?.Trim(), StringComparison.OrdinalIgnoreCase))
            return null;

        // Người yêu cầu sang ca của đồng nghiệp; đồng nghiệp sang ca của người yêu cầu.
        return await MoverExceedsAsync(quotaRepository, workScheduleRepository, requester, targetDate, targetShiftId, storeId, cancellationToken)
            ?? await MoverExceedsAsync(quotaRepository, workScheduleRepository, target, requesterDate, requesterShiftId, storeId, cancellationToken);
    }

    private static async Task<string?> MoverExceedsAsync(
        IRepository<ShiftStaffingQuota> quotaRepository,
        IRepository<WorkSchedule> workScheduleRepository,
        Employee mover, DateTime date, Guid shiftId, Guid storeId, CancellationToken ct)
    {
        var dept = mover.Department;
        if (string.IsNullOrWhiteSpace(dept)) return null;

        var quota = (await quotaRepository.GetAllAsync(
                q => q.StoreId == storeId && q.ShiftTemplateId == shiftId, cancellationToken: ct))
            .FirstOrDefault(q => string.Equals(q.Department, dept, StringComparison.OrdinalIgnoreCase));
        // Định mức chung (không theo bộ phận) giữ nguyên tổng số người → không ảnh hưởng.
        if (quota == null) return null;

        var day = date.Date;
        var (_, max) = StaffingQuotaResolver.ResolveLimitsForDate(quota, day);
        if (max <= 0) return null;

        var rows = await workScheduleRepository.GetAllAsync(
            ws => ws.StoreId == storeId && ws.Date >= day && ws.Date < day.AddDays(1)
                  && ws.ShiftId == shiftId && !ws.IsDayOff,
            includeProperties: ["Employee"], cancellationToken: ct);
        var count = rows.Count(ws => ws.Employee != null
            && string.Equals(ws.Employee.Department, dept, StringComparison.OrdinalIgnoreCase));
        return count + 1 > max
            ? $"Ca ngày {day:dd/MM/yyyy} đã đủ định mức tối đa {max} người của bộ phận {dept} (đã xếp {count}) — không thể nhận thêm."
            : null;
    }

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
