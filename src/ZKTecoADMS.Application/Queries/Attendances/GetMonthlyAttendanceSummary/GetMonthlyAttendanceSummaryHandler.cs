using ZKTecoADMS.Application.DTOs.Attendances;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Queries.Attendances.GetMonthlyAttendanceSummary;

public class GetMonthlyAttendanceSummaryHandler(
    IRepository<DeviceUser> employeeRepository,
    IRepository<Attendance> attendanceRepository,
    IRepository<Shift> shiftRepository
) : IQueryHandler<GetMonthlyAttendanceSummaryQuery, AppResponse<List<MonthlyAttendanceSummaryDto>>>
{
    public async Task<AppResponse<List<MonthlyAttendanceSummaryDto>>> Handle(
        GetMonthlyAttendanceSummaryQuery request,
        CancellationToken cancellationToken)
    {
        if (request.EmployeeIds == null || !request.EmployeeIds.Any())
        {
            return AppResponse<List<MonthlyAttendanceSummaryDto>>.Error("No employee IDs provided");
        }

        var results = new List<MonthlyAttendanceSummaryDto>();
        
        foreach (var employeeId in request.EmployeeIds)
        {
            var summary = await ProcessEmployeeSummary(employeeId, request.Year, request.Month, cancellationToken);
            if (summary != null)
            {
                results.Add(summary);
            }
        }

        return AppResponse<List<MonthlyAttendanceSummaryDto>>.Success(results);
    }

    private async Task<MonthlyAttendanceSummaryDto?> ProcessEmployeeSummary(
        Guid employeeId,
        int year,
        int month,
        CancellationToken cancellationToken)
    {
        // Get employee
        var employee = await employeeRepository.GetByIdAsync(
            employeeId,
            new[] { "ApplicationUser" },
            cancellationToken);

        if (employee == null)
        {
            return null;
        }

        var startDate = new DateTime(year, month, 1);
        var endDate = startDate.AddMonths(1).AddDays(-1);

        // Get all attendances for the month
        var allAttendances = await attendanceRepository.GetAllAsync(
            filter: a => a.EmployeeId == employeeId &&
                        a.AttendanceTime >= startDate &&
                        a.AttendanceTime <= endDate.AddDays(1),
            includeProperties: new[] { "Device" },
            cancellationToken: cancellationToken);

        var attendances = allAttendances
            .OrderBy(a => a.AttendanceTime)
            .ToList();

        // Get all shifts for the month
        List<Shift> shifts = [];
        var allShifts = await shiftRepository.GetAllAsync(
            filter: s => s.StartTime >= startDate &&
                        s.StartTime <= endDate.AddDays(1) &&
                        s.Status == ShiftStatus.Approved,
            includeProperties: new[] { "Leave" },
            cancellationToken: cancellationToken);
        
        shifts = allShifts.OrderBy(s => s.StartTime).ToList();

        // Group attendances by date and find check-in/out pairs
        var dailyRecords = new List<DailyAttendanceDto>();
        
        for (var date = startDate; date <= endDate; date = date.AddDays(1))
        {
            var dayAttendances = attendances
                .Where(a => a.AttendanceTime.Date == date.Date)
                .OrderBy(a => a.AttendanceTime)
                .ToList();

            var dayShift = new List<Shift>().FirstOrDefault(s => s.StartTime.Date == date.Date);

            var attendanceRecords = new List<AttendanceRecordDto>();
            
            // Group attendances into check-in/out pairs
            for (int i = 0; i < dayAttendances.Count; i++)
            {
                var checkIn = dayAttendances[i];
                DateTime? checkOut = null;
                
                // Look for the next attendance as potential check-out
                if (i + 1 < dayAttendances.Count)
                {
                    var nextAttendance = dayAttendances[i + 1];
                    // If next attendance is within reasonable time (same work period), consider it as check-out
                    if ((nextAttendance.AttendanceTime - checkIn.AttendanceTime).TotalHours < 12)
                    {
                        checkOut = nextAttendance.AttendanceTime;
                        i++; // Skip the next one as we've used it as check-out
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

            var dailyRecord = new DailyAttendanceDto
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
            };

            dailyRecords.Add(dailyRecord);
        }

        var result = new MonthlyAttendanceSummaryDto
        {
            EmployeeId = employeeId,
            EmployeeName = employee.Name,
            Year = year,
            Month = month,
            DailyRecords = dailyRecords
        };

        return result;
    }


}
