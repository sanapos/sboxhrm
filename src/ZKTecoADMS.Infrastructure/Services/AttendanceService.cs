using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Infrastructure.Services;


public class AttendanceService(
    IRepository<Attendance> attendanceRepository,
    IRepository<DeviceUser> employeeRepository,
    IRepository<Shift> shiftRepository,
    IRepository<WorkSchedule> workScheduleRepository,
    IRepository<PenaltySetting> penaltySettingRepository,
    IRepository<PaymentTransaction> paymentTransactionRepository,
    IRepository<Employee> employeeEntityRepository,
    ILogger<AttendanceService> logger
)
    : IAttendanceService
{
    public async Task<IEnumerable<Attendance>> GetAttendanceByDeviceAsync(
        Guid deviceId, DateTime? startDate, DateTime? endDate)
    {
        return await attendanceRepository.GetAllAsync(
            a => a.DeviceId == deviceId && a.AttendanceTime.Date >= startDate && a.AttendanceTime.Date <= endDate,
            orderBy: query => query.OrderByDescending(a => a.AttendanceTime.Date)
        );
    }

    public async Task<IEnumerable<Attendance>> GetAttendanceByEmployeeAsync(
        Guid deviceId, Guid employeeId, DateTime? startDate, DateTime? endDate)
    {
        return await attendanceRepository.GetAllAsync(
            a => a.DeviceId == deviceId && a.AttendanceTime.Date >= startDate && a.AttendanceTime.Date <= endDate && a.EmployeeId == employeeId,
            orderBy: query => query.OrderByDescending(a => a.AttendanceTime.Date)
        );    }

    public async Task<bool> LogExistsAsync(Guid deviceId, string pin, DateTime attendanceTime)
    {
        return await attendanceRepository.ExistsAsync(a => 
            a.DeviceId == deviceId && 
            a.PIN == pin && 
            a.AttendanceTime == attendanceTime);
    }

    public async Task CreateAttendancesAsync(IEnumerable<Attendance> attendances)
    {
        await attendanceRepository.AddRangeAsync(attendances);
    }

    public async Task<bool> UpdateShiftAttendancesAsync(IEnumerable<Attendance> attendances, Device device)
    {
        var attendanceList = attendances.OrderBy(a => a.AttendanceTime).ToList();
        if (attendanceList.Count == 0) return true;

        // Pre-load all DeviceUsers for this device to avoid N+1
        var deviceUsers = (await employeeRepository.GetAllAsync(
            filter: e => e.DeviceId == device.Id
        )).ToDictionary(e => e.Pin, e => e);

        // Pre-load PenaltySetting for this store (single record)
        var penaltySetting = await penaltySettingRepository.GetSingleAsync(
            filter: ps => ps.StoreId == device.StoreId
        );

        // Collect unique dates and employee IDs for batch loading
        var pins = attendanceList.Select(a => a.PIN).Distinct().ToList();
        var employeeIds = deviceUsers.Values
            .Where(du => du.EmployeeId.HasValue && pins.Contains(du.Pin))
            .Select(du => du.EmployeeId!.Value)
            .Distinct()
            .ToList();

        var dates = attendanceList.Select(a => a.AttendanceTime.Date).Distinct().ToList();
        var minDate = dates.Min();
        var maxDate = dates.Max();

        // Pre-load WorkSchedules for all relevant employees and dates
        var schedules = (await workScheduleRepository.GetAllAsync(
            filter: ws => employeeIds.Contains(ws.EmployeeUserId)
                && ws.Date.Date >= minDate && ws.Date.Date <= maxDate
                && ws.Deleted == null
                && ws.StoreId == device.StoreId,
            includeProperties: ["Shift"]
        )).ToList();
        var schedulesByEmployeeDate = schedules
            .GroupBy(ws => (ws.EmployeeUserId, ws.Date.Date))
            .ToDictionary(g => g.Key, g => g.First());

        // Pre-load Employees for ApplicationUserId lookup
        var employees = (await employeeEntityRepository.GetAllAsync(
            filter: e => employeeIds.Contains(e.Id)
        )).ToDictionary(e => e.Id, e => e);

        // Pre-load existing penalty transactions for duplicate checking
        var monthStart = new DateTime(minDate.Year, minDate.Month, 1);
        var existingPenalties = (await paymentTransactionRepository.GetAllAsync(
            filter: pt => pt.EmployeeId.HasValue && employeeIds.Contains(pt.EmployeeId.Value)
                && pt.TransactionDate >= monthStart
                && pt.TransactionDate <= maxDate
                && pt.Type == "Penalty"
        )).ToList();

        foreach (var attendance in attendanceList)
        {
            if (attendance.EmployeeId == null)
            {
                logger.LogWarning("{DeviceSN}:Attendance with ID {AttendanceId} has no associated EmployeeId.", device.SerialNumber, attendance.Id);
                continue;
            }

            if (!deviceUsers.TryGetValue(attendance.PIN, out var employeeUser))
            {
                logger.LogWarning("{DeviceSN}:No employee found for Attendance ID {AttendanceId} with PIN {PIN}.", device.SerialNumber, attendance.Id, attendance.PIN);
                continue;
            }

            try
            {
                await ProcessPenaltyForAttendanceBatchAsync(attendance, employeeUser, device,
                    penaltySetting, schedulesByEmployeeDate, employees, existingPenalties);
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "{DeviceSN}:Error processing penalty for Attendance {AttendanceId}", device.SerialNumber, attendance.Id);
            }
        }
        return true;
    }

    private async Task ProcessPenaltyForAttendanceBatchAsync(
        Attendance attendance, DeviceUser deviceUser, Device device,
        PenaltySetting? penaltySetting,
        Dictionary<(Guid, DateTime), WorkSchedule> schedulesByEmployeeDate,
        Dictionary<Guid, Employee> employees,
        List<PaymentTransaction> existingPenalties)
    {
        if (!deviceUser.EmployeeId.HasValue)
        {
            logger.LogWarning("{DeviceSN}: DeviceUser {Pin} chưa liên kết Employee, bỏ qua phạt.", device.SerialNumber, deviceUser.Pin);
            return;
        }

        var employeeId = deviceUser.EmployeeId.Value;
        var violationDate = attendance.AttendanceTime.Date;

        // Use pre-loaded schedule
        schedulesByEmployeeDate.TryGetValue((employeeId, violationDate), out var schedule);

        if (schedule == null || schedule.IsDayOff)
            return;

        var defaultStart = new TimeSpan(8, 30, 0);
        var defaultEnd = new TimeSpan(18, 0, 0);
        var shiftStart = schedule.StartTime ?? schedule.Shift?.StartTime ?? defaultStart;
        var shiftEnd = schedule.EndTime ?? schedule.Shift?.EndTime ?? defaultEnd;

        if (penaltySetting == null)
            return;

        // Use pre-loaded employee
        employees.TryGetValue(employeeId, out var employee);
        var employeeUserId = employee?.ApplicationUserId;

        var punchTime = attendance.AttendanceTime.TimeOfDay;

        if (attendance.AttendanceState == AttendanceStates.CheckIn)
        {
            if (punchTime > shiftStart)
            {
                var lateMinutes = (int)(punchTime - shiftStart).TotalMinutes;
                if (lateMinutes <= 0) return;

                var (tier, amount) = CalculateLatePenalty(lateMinutes, penaltySetting);
                if (amount <= 0) return;

                // Check duplicate using pre-loaded penalties
                var exists = existingPenalties.Any(
                    pt => pt.EmployeeId == employeeId
                        && pt.TransactionDate.Date == violationDate
                        && pt.Description != null && pt.Description.StartsWith("Đi trễ")
                );
                if (exists) return;

                // Count repeats using pre-loaded penalties
                var repeatCount = existingPenalties.Count(
                    pt => pt.EmployeeId == employeeId
                        && pt.TransactionDate >= new DateTime(violationDate.Year, violationDate.Month, 1)
                        && pt.TransactionDate < violationDate
                        && pt.Description != null
                        && (pt.Description.StartsWith("Đi trễ") || pt.Description.StartsWith("Về sớm"))
                        && pt.Status != "Cancelled"
                );

                var repeatPenalty = CalculateRepeatPenalty(repeatCount + 1, penaltySetting);

                var description = $"Đi trễ {lateMinutes} phút (bậc {tier}: {amount:N0}đ"
                    + (repeatPenalty > 0 ? $", tái phạm lần {repeatCount + 1}: +{repeatPenalty:N0}đ" : "")
                    + ")";

                var transaction = new PaymentTransaction
                {
                    EmployeeId = employeeId,
                    EmployeeUserId = employeeUserId,
                    Type = "Penalty",
                    ForMonth = violationDate.Month,
                    ForYear = violationDate.Year,
                    TransactionDate = violationDate,
                    Amount = -(amount + repeatPenalty),
                    Description = description,
                    Status = "Pending",
                    Note = $"Tự động tạo từ chấm công | Ca: {shiftStart:hh\\:mm}-{shiftEnd:hh\\:mm} | Thực tế: {punchTime:hh\\:mm}"
                };

                await paymentTransactionRepository.AddAsync(transaction);
                existingPenalties.Add(transaction); // Track newly created penalties
                logger.LogInformation("{DeviceSN}: Tạo phiếu phạt đi trễ cho NV {Pin} - {Minutes} phút - {Amount}đ",
                    device.SerialNumber, deviceUser.Pin, lateMinutes, amount + repeatPenalty);
            }
        }
        else if (attendance.AttendanceState == AttendanceStates.CheckOut)
        {
            if (punchTime < shiftEnd)
            {
                var earlyMinutes = (int)(shiftEnd - punchTime).TotalMinutes;
                if (earlyMinutes <= 0) return;

                var (tier, amount) = CalculateEarlyPenalty(earlyMinutes, penaltySetting);
                if (amount <= 0) return;

                var exists = existingPenalties.Any(
                    pt => pt.EmployeeId == employeeId
                        && pt.TransactionDate.Date == violationDate
                        && pt.Description != null && pt.Description.StartsWith("Về sớm")
                );
                if (exists) return;

                var monthStart = new DateTime(violationDate.Year, violationDate.Month, 1);
                var repeatCount = existingPenalties.Count(
                    pt => pt.EmployeeId == employeeId
                        && pt.TransactionDate >= monthStart
                        && pt.TransactionDate < violationDate
                        && pt.Description != null
                        && (pt.Description.StartsWith("Đi trễ") || pt.Description.StartsWith("Về sớm"))
                        && pt.Status != "Cancelled"
                );

                var repeatPenalty = CalculateRepeatPenalty(repeatCount + 1, penaltySetting);

                var description = $"Về sớm {earlyMinutes} phút (bậc {tier}: {amount:N0}đ"
                    + (repeatPenalty > 0 ? $", tái phạm lần {repeatCount + 1}: +{repeatPenalty:N0}đ" : "")
                    + ")";

                var transaction = new PaymentTransaction
                {
                    EmployeeId = employeeId,
                    EmployeeUserId = employeeUserId,
                    Type = "Penalty",
                    ForMonth = violationDate.Month,
                    ForYear = violationDate.Year,
                    TransactionDate = violationDate,
                    Amount = -(amount + repeatPenalty),
                    Description = description,
                    Status = "Pending",
                    Note = $"Tự động tạo từ chấm công | Ca: {shiftStart:hh\\:mm}-{shiftEnd:hh\\:mm} | Thực tế: {punchTime:hh\\:mm}"
                };

                await paymentTransactionRepository.AddAsync(transaction);
                logger.LogInformation("{DeviceSN}: Tạo phiếu phạt về sớm cho NV {Pin} - {Minutes} phút - {Amount}đ",
                    device.SerialNumber, deviceUser.Pin, earlyMinutes, amount + repeatPenalty);
            }
        }
    }

    private static (int tier, decimal amount) CalculateLatePenalty(int lateMinutes, PenaltySetting settings)
    {
        if (lateMinutes >= settings.LateMinutes3)
            return (3, settings.LatePenalty3);
        if (lateMinutes >= settings.LateMinutes2)
            return (2, settings.LatePenalty2);
        if (lateMinutes >= settings.LateMinutes1)
            return (1, settings.LatePenalty1);
        return (0, 0);
    }

    private static (int tier, decimal amount) CalculateEarlyPenalty(int earlyMinutes, PenaltySetting settings)
    {
        if (earlyMinutes >= settings.EarlyMinutes3)
            return (3, settings.EarlyPenalty3);
        if (earlyMinutes >= settings.EarlyMinutes2)
            return (2, settings.EarlyPenalty2);
        if (earlyMinutes >= settings.EarlyMinutes1)
            return (1, settings.EarlyPenalty1);
        return (0, 0);
    }

    private static decimal CalculateRepeatPenalty(int totalViolations, PenaltySetting settings)
    {
        if (totalViolations >= settings.RepeatCount3)
            return settings.RepeatPenalty3;
        if (totalViolations >= settings.RepeatCount2)
            return settings.RepeatPenalty2;
        if (totalViolations >= settings.RepeatCount1)
            return settings.RepeatPenalty1;
        return 0;
    }
}