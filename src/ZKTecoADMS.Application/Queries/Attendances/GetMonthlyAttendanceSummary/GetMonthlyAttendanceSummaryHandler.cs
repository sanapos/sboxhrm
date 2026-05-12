using ZKTecoADMS.Application.DTOs.Attendances;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Queries.Attendances.GetMonthlyAttendanceSummary;

public class GetMonthlyAttendanceSummaryHandler(
    IRepository<Employee> employeeRepository,
    IRepository<DeviceUser> deviceUserRepository,
    IRepository<Attendance> attendanceRepository,
    IRepository<Shift> shiftRepository
) : IQueryHandler<GetMonthlyAttendanceSummaryQuery, AppResponse<List<MonthlyAttendanceSummaryDto>>>
{
    public async Task<AppResponse<List<MonthlyAttendanceSummaryDto>>> Handle(
        GetMonthlyAttendanceSummaryQuery request,
        CancellationToken cancellationToken)
    {
        if (request.EmployeeIds == null || !request.EmployeeIds.Any())
            return AppResponse<List<MonthlyAttendanceSummaryDto>>.Error("No employee IDs provided");

        var startDate = new DateTime(request.Year, request.Month, 1);
        var endDate = startDate.AddMonths(1).AddDays(-1);
        var ids = request.EmployeeIds.ToList();

        // ── Bulk query 1: HR employees ──────────────────────────────────────
        var employees = await employeeRepository.GetAllAsync(
            filter: e => ids.Contains(e.Id),
            cancellationToken: cancellationToken);

        // ── Bulk query 2: DeviceUsers linked to these employees ─────────────
        // Attendance.EmployeeId → DeviceUser.Id, DeviceUser.EmployeeId → Employee.Id
        var deviceUsers = await deviceUserRepository.GetAllAsync(
            filter: du => du.EmployeeId != null && ids.Contains(du.EmployeeId.Value),
            cancellationToken: cancellationToken);

        // Map: Employee.Id → DeviceUser.Id list (one employee may have multiple)
        var deviceUserIdsByEmpId = deviceUsers
            .Where(du => du.EmployeeId.HasValue)
            .GroupBy(du => du.EmployeeId!.Value)
            .ToDictionary(g => g.Key, g => g.Select(du => du.Id).ToList());

        var allDeviceUserIds = deviceUsers.Select(du => du.Id).ToList();

        // ── Bulk query 3: all attendances for all device users ──────────────
        var allAttendances = allDeviceUserIds.Any()
            ? await attendanceRepository.GetAllAsync(
                filter: a => a.EmployeeId != null &&
                             allDeviceUserIds.Contains(a.EmployeeId.Value) &&
                             a.AttendanceTime >= startDate &&
                             a.AttendanceTime <= endDate.AddDays(1),
                includeProperties: new[] { "Device" },
                cancellationToken: cancellationToken)
            : new List<Attendance>();

        // Group attendances by DeviceUser.Id for O(1) lookup
        var attendancesByDeviceUserId = allAttendances
            .GroupBy(a => a.EmployeeId!.Value)
            .ToDictionary(g => g.Key, g => g.OrderBy(a => a.AttendanceTime).ToList());

        // ── Bulk query 4: all shifts via ApplicationUser linkage ────────────
        // Shift.EmployeeUserId → ApplicationUser.Id = Employee.ApplicationUserId
        var appUserIds = employees
            .Where(e => e.ApplicationUserId.HasValue)
            .Select(e => e.ApplicationUserId!.Value)
            .ToList();

        var empIdByAppUserId = employees
            .Where(e => e.ApplicationUserId.HasValue)
            .ToDictionary(e => e.ApplicationUserId!.Value, e => e.Id);

        var allShifts = appUserIds.Any()
            ? await shiftRepository.GetAllAsync(
                filter: s => appUserIds.Contains(s.EmployeeUserId) &&
                             s.StartTime >= startDate &&
                             s.StartTime <= endDate.AddDays(1) &&
                             s.Status == ShiftStatus.Approved,
                includeProperties: new[] { "Leave" },
                cancellationToken: cancellationToken)
            : new List<Shift>();

        // Group shifts by (Employee.Id, date) for O(1) lookup
        var shiftsByEmpDate = allShifts
            .Where(s => empIdByAppUserId.ContainsKey(s.EmployeeUserId))
            .GroupBy(s => (empIdByAppUserId[s.EmployeeUserId], s.StartTime.Date))
            .ToDictionary(g => g.Key, g => g.First());

        // ── Process each employee in memory (no DB calls in loop) ───────────
        var results = new List<MonthlyAttendanceSummaryDto>();
        foreach (var empId in ids)
        {
            var employee = employees.FirstOrDefault(e => e.Id == empId);
            if (employee == null) continue;

            // Merge attendance records across all device users for this employee
            var empDeviceUserIds = deviceUserIdsByEmpId.TryGetValue(empId, out var duIds)
                ? duIds
                : new List<Guid>();

            var empAttendances = empDeviceUserIds
                .SelectMany(duId => attendancesByDeviceUserId.TryGetValue(duId, out var atts)
                    ? atts
                    : Enumerable.Empty<Attendance>())
                .OrderBy(a => a.AttendanceTime)
                .ToList();

            var dailyRecords = new List<DailyAttendanceDto>();
            for (var date = startDate; date <= endDate; date = date.AddDays(1))
            {
                var dayAttendances = empAttendances
                    .Where(a => a.AttendanceTime.Date == date.Date)
                    .ToList();

                shiftsByEmpDate.TryGetValue((empId, date.Date), out var dayShift);

                var attendanceRecords = new List<AttendanceRecordDto>();
                for (int i = 0; i < dayAttendances.Count; i++)
                {
                    var checkIn = dayAttendances[i];
                    DateTime? checkOut = null;
                    if (i + 1 < dayAttendances.Count)
                    {
                        var next = dayAttendances[i + 1];
                        if ((next.AttendanceTime - checkIn.AttendanceTime).TotalHours < 12)
                        {
                            checkOut = next.AttendanceTime;
                            i++;
                        }
                    }
                    attendanceRecords.Add(new AttendanceRecordDto
                    {
                        Id = checkIn.Id,
                        CheckInTime = checkIn.AttendanceTime,
                        CheckOutTime = checkOut,
                        DeviceName = checkIn.Device?.DeviceName ?? "Unknown",
                        VerifyMode = checkIn.VerifyMode,
                        AttendanceState = checkIn.AttendanceState
                    });
                }

                dailyRecords.Add(new DailyAttendanceDto
                {
                    Date = date,
                    Attendances = attendanceRecords,
                    HasShift = dayShift != null,
                    IsLeave = dayShift?.Leave != null,
                    Shift = dayShift != null ? new ShiftInfoDto
                    {
                        Id = dayShift.Id,
                        StartTime = dayShift.StartTime,
                        EndTime = dayShift.EndTime,
                        Description = dayShift.Description,
                        Status = dayShift.Status
                    } : null,
                    Leave = dayShift?.Leave != null ? new LeaveInfoDto
                    {
                        Id = dayShift.Leave.Id,
                        Type = dayShift.Leave.Type,
                        Reason = dayShift.Leave.Reason,
                        Status = dayShift.Leave.Status,
                        IsHalfShift = dayShift.Leave.IsHalfShift
                    } : null
                });
            }

            results.Add(new MonthlyAttendanceSummaryDto
            {
                EmployeeId = empId,
                EmployeeName = $"{employee.FirstName} {employee.LastName}",
                Year = request.Year,
                Month = request.Month,
                DailyRecords = dailyRecords
            });
        }

        return AppResponse<List<MonthlyAttendanceSummaryDto>>.Success(results);
    }
}
