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
    IRepository<PenaltyTicket> penaltyTicketRepository,
    IRepository<EmployeeBenefit> employeeBenefitRepository,
    IRepository<ShiftTemplate> shiftTemplateRepository,
    IRepository<AppSettings> appSettingsRepository,
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

        // Load store's day_end_time to correctly determine logical working date for overnight shifts.
        // E.g. if day_end_time = 05:00, a punch at 03:00 May 3 belongs to the working day May 2.
        var dayEndSetting = await appSettingsRepository.GetSingleAsync(
            s => s.StoreId == device.StoreId && s.Key == "day_end_time"
        );
        var storesDayEnd = TimeSpan.Zero;
        if (dayEndSetting?.Value != null && TimeSpan.TryParse(dayEndSetting.Value, out var parsedDayEnd))
            storesDayEnd = parsedDayEnd;

        // Collect unique dates and employee IDs for batch loading
        var pins = attendanceList.Select(a => a.PIN).Distinct().ToList();
        var employeeIds = deviceUsers.Values
            .Where(du => du.EmployeeId.HasValue && pins.Contains(du.Pin))
            .Select(du => du.EmployeeId!.Value)
            .Distinct()
            .ToList();

        // Compute logical dates: for overnight shifts, a punch before day_end_time
        // belongs to the PREVIOUS calendar day.
        var dates = attendanceList.Select(a => GetLogicalDate(a.AttendanceTime, storesDayEnd)).Distinct().ToList();
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

        // Pre-load existing PenaltyTickets to avoid duplicate auto-creation per (employee, date, type)
        // and to compute next sequential TicketCode per day.
        var existingTickets = (await penaltyTicketRepository.GetAllAsync(
            filter: t => employeeIds.Contains(t.EmployeeId)
                && t.ViolationDate >= minDate
                && t.ViolationDate <= maxDate
        )).ToList();

        // Pre-load store-wide ticket counts for current day window so we can generate
        // sequential TicketCode (PP-YYYYMMDD-XXXX) without N+1 round-trips.
        var ticketCountsByDate = (await penaltyTicketRepository.GetAllAsync(
            filter: t => t.StoreId == device.StoreId
                && t.ViolationDate >= minDate
                && t.ViolationDate <= maxDate
        )).GroupBy(t => t.ViolationDate.Date)
          .ToDictionary(g => g.Key, g => g.Count());

        // Pre-load Benefits (SalaryProfile) for fallback when WorkSchedule is missing.
        // The "Tổng hợp theo ca" tab uses these to determine shift assignment.
        var employeeBenefits = (await employeeBenefitRepository.GetAllAsync(
            filter: eb => employeeIds.Contains(eb.EmployeeId)
                && eb.EffectiveDate <= maxDate
                && (eb.EndDate == null || eb.EndDate >= minDate),
            includeProperties: ["Benefit"]
        )).GroupBy(eb => eb.EmployeeId)
          .ToDictionary(g => g.Key, g => g.OrderByDescending(x => x.EffectiveDate).First());

        // Pre-load ShiftTemplates for this store, indexed by normalized name.
        var shiftTemplatesByName = (await shiftTemplateRepository.GetAllAsync(
            filter: st => st.StoreId == device.StoreId && st.IsActive
        )).GroupBy(st => NormalizeShiftName(st.Name))
          .ToDictionary(g => g.Key, g => g.First());

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
                    penaltySetting, schedulesByEmployeeDate, employees, existingPenalties,
                    existingTickets, ticketCountsByDate,
                    employeeBenefits, shiftTemplatesByName, storesDayEnd);
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "{DeviceSN}:Error processing penalty for Attendance {AttendanceId}", device.SerialNumber, attendance.Id);
            }
        }
        return true;
    }

    /// <summary>
    /// Returns the logical working date for a punch: if the punch falls before the store's
    /// day_end_time cutoff (e.g. 05:00), it belongs to the PREVIOUS calendar day.
    /// </summary>
    private static DateTime GetLogicalDate(DateTime punchTime, TimeSpan storesDayEnd)
    {
        // AttendanceTime is stored as UTC (EnableLegacyTimestampBehavior = true, Kind = Unspecified).
        // Convert to Vietnam local time (UTC+7) before extracting the calendar date so that
        // early-morning punches (00:00–06:59 VN = 17:00–23:59 UTC previous day) are assigned
        // to the correct VN working day, not yesterday's UTC date.
        var vnTime = punchTime.AddHours(7);
        if (storesDayEnd > TimeSpan.Zero && vnTime.TimeOfDay < storesDayEnd)
            return vnTime.Date.AddDays(-1);
        return vnTime.Date;
    }

    private async Task ProcessPenaltyForAttendanceBatchAsync(
        Attendance attendance, DeviceUser deviceUser, Device device,
        PenaltySetting? penaltySetting,
        Dictionary<(Guid, DateTime), WorkSchedule> schedulesByEmployeeDate,
        Dictionary<Guid, Employee> employees,
        List<PaymentTransaction> existingPenalties,
        List<PenaltyTicket> existingTickets,
        Dictionary<DateTime, int> ticketCountsByDate,
        Dictionary<Guid, EmployeeBenefit> employeeBenefits,
        Dictionary<string, ShiftTemplate> shiftTemplatesByName,
        TimeSpan storesDayEnd)
    {
        if (!deviceUser.EmployeeId.HasValue)
        {
            logger.LogWarning("{DeviceSN}: DeviceUser {Pin} chưa liên kết Employee, bỏ qua phạt.", device.SerialNumber, deviceUser.Pin);
            return;
        }

        var employeeId = deviceUser.EmployeeId.Value;
        // Use logical date so that overnight punches (before day_end_time) are assigned
        // to the correct working day rather than the calendar date.
        var violationDate = GetLogicalDate(attendance.AttendanceTime, storesDayEnd);
        var punchTime = attendance.AttendanceTime.TimeOfDay;

        // Use pre-loaded schedule (keyed by logical date)
        schedulesByEmployeeDate.TryGetValue((employeeId, violationDate), out var schedule);

        TimeSpan shiftStart;
        TimeSpan shiftEnd;
        Guid? shiftIdForTicket;

        if (schedule != null)
        {
            if (schedule.IsDayOff) return;
            var defaultStart = new TimeSpan(8, 30, 0);
            var defaultEnd = new TimeSpan(18, 0, 0);
            shiftStart = schedule.StartTime ?? schedule.Shift?.StartTime ?? defaultStart;
            shiftEnd = schedule.EndTime ?? schedule.Shift?.EndTime ?? defaultEnd;
            shiftIdForTicket = schedule.ShiftId;
        }
        else
        {
            // Fallback: use Employee's SalaryProfile (Benefit) shifts.
            var fallback = ResolveFallbackShift(employeeId, violationDate, punchTime,
                attendance.AttendanceState, employeeBenefits, shiftTemplatesByName);
            if (fallback == null) return;
            shiftStart = fallback.Value.start;
            shiftEnd = fallback.Value.end;
            shiftIdForTicket = null;
        }

        if (penaltySetting == null)
            return;

        // Use pre-loaded employee
        employees.TryGetValue(employeeId, out var employee);
        var employeeUserId = employee?.ApplicationUserId;

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

                // Also create a PenaltyTicket so it appears in "Phiếu phạt" UI for manager review.
                await CreatePenaltyTicketAsync(employeeId, device.StoreId, violationDate,
                    PenaltyTicketType.Late, tier, lateMinutes, amount + repeatPenalty,
                    repeatCount + 1, repeatPenalty, shiftStart, shiftEnd, punchTime,
                    attendance, shiftIdForTicket, description, existingTickets, ticketCountsByDate);

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
                existingPenalties.Add(transaction);

                // Also create a PenaltyTicket so it appears in "Phiếu phạt" UI for manager review.
                await CreatePenaltyTicketAsync(employeeId, device.StoreId, violationDate,
                    PenaltyTicketType.EarlyLeave, tier, earlyMinutes, amount + repeatPenalty,
                    repeatCount + 1, repeatPenalty, shiftStart, shiftEnd, punchTime,
                    attendance, shiftIdForTicket, description, existingTickets, ticketCountsByDate);

                logger.LogInformation("{DeviceSN}: Tạo phiếu phạt về sớm cho NV {Pin} - {Minutes} phút - {Amount}đ",
                    device.SerialNumber, deviceUser.Pin, earlyMinutes, amount + repeatPenalty);
            }
        }
    }

    /// <summary>
    /// Creates a PenaltyTicket auto-generated from attendance, mirroring the PaymentTransaction
    /// penalty so the manager can review/cancel it before auto-approval. Idempotent: skips if a
    /// ticket already exists for the same (employee, date, type).
    /// </summary>
    private async Task CreatePenaltyTicketAsync(
        Guid employeeId,
        Guid? storeId,
        DateTime violationDate,
        PenaltyTicketType type,
        int tier,
        int minutesLateOrEarly,
        decimal totalAmount,
        int repeatCountInMonth,
        decimal repeatSurcharge,
        TimeSpan shiftStart,
        TimeSpan shiftEnd,
        TimeSpan punchTime,
        Attendance attendance,
        Guid? shiftId,
        string description,
        List<PenaltyTicket> existingTickets,
        Dictionary<DateTime, int> ticketCountsByDate)
    {
        // Idempotency: one ticket per (employee, date, type).
        if (existingTickets.Any(t => t.EmployeeId == employeeId
                && t.ViolationDate.Date == violationDate.Date
                && t.Type == type
                && t.Status != PenaltyTicketStatus.Cancelled))
        {
            return;
        }

        var dateKey = violationDate.Date;
        var nextSeq = (ticketCountsByDate.TryGetValue(dateKey, out var c) ? c : 0) + 1;
        var ticketCode = $"PP-{violationDate:yyyyMMdd}-{nextSeq:D4}";

        var ticket = new PenaltyTicket
        {
            Id = Guid.NewGuid(),
            TicketCode = ticketCode,
            EmployeeId = employeeId,
            Type = type,
            Status = PenaltyTicketStatus.Pending,
            Amount = totalAmount,
            ViolationDate = violationDate.Date,
            MinutesLateOrEarly = minutesLateOrEarly,
            ShiftStartTime = shiftStart,
            ShiftEndTime = shiftEnd,
            ActualPunchTime = attendance.AttendanceTime,
            PenaltyTier = tier,
            RepeatCountInMonth = repeatSurcharge > 0 ? repeatCountInMonth : null,
            Description = description,
            ShiftId = shiftId,
            AttendanceId = attendance.Id,
            StoreId = storeId,
            CreatedAt = DateTime.Now,
        };

        await penaltyTicketRepository.AddAsync(ticket);
        existingTickets.Add(ticket);
        ticketCountsByDate[dateKey] = nextSeq;
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

    /// <summary>
    /// Khi không có WorkSchedule cho nhân viên trong ngày, dùng SalaryProfile (Benefit)
    /// để lấy danh sách ca làm việc và chọn ca phù hợp với thời điểm chấm công.
    /// Đảm bảo logic phạt đồng nhất với màn hình "Tổng hợp theo ca".
    /// </summary>
    private static (TimeSpan start, TimeSpan end)? ResolveFallbackShift(
        Guid employeeId, DateTime violationDate, TimeSpan punchTime,
        AttendanceStates state,
        Dictionary<Guid, EmployeeBenefit> employeeBenefits,
        Dictionary<string, ShiftTemplate> shiftTemplatesByName)
    {
        if (!employeeBenefits.TryGetValue(employeeId, out var eb)) return null;
        var benefit = eb.Benefit;
        if (benefit == null) return null;

        // Day-off check based on Benefit.WeeklyOffDays (e.g. "Sunday", "Saturday,Sunday").
        if (!string.IsNullOrWhiteSpace(benefit.WeeklyOffDays))
        {
            var dayName = violationDate.DayOfWeek.ToString();
            var offs = benefit.WeeklyOffDays.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
            if (offs.Any(d => string.Equals(d, dayName, StringComparison.OrdinalIgnoreCase)))
                return null;
        }

        // Parse "shifts:Ca sáng, Ca chiều" from Description; map names → ShiftTemplate.
        var candidates = new List<ShiftTemplate>();
        var shiftsField = ParseDescField(benefit.Description, "shifts");
        if (!string.IsNullOrWhiteSpace(shiftsField))
        {
            foreach (var raw in shiftsField.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries))
            {
                var key = NormalizeShiftName(raw);
                if (shiftTemplatesByName.TryGetValue(key, out var st))
                    candidates.Add(st);
            }
        }

        if (candidates.Count == 0)
        {
            // Last-resort fallback: Benefit's own CheckIn/CheckOut times.
            if (benefit.CheckIn.HasValue && benefit.CheckOut.HasValue)
                return (benefit.CheckIn.Value.ToTimeSpan(), benefit.CheckOut.Value.ToTimeSpan());
            return null;
        }

        // Choose the shift covering this punch.
        ShiftTemplate? chosen;
        if (state == AttendanceStates.CheckIn)
        {
            var window = TimeSpan.FromHours(2);
            var match = candidates
                .Where(s => punchTime >= s.StartTime - window && punchTime <= s.EndTime)
                .OrderBy(s => Math.Abs((punchTime - s.StartTime).TotalMinutes))
                .ToList();
            chosen = match.FirstOrDefault()
                ?? candidates.OrderBy(s => Math.Abs((punchTime - s.StartTime).TotalMinutes)).First();
        }
        else
        {
            var window = TimeSpan.FromHours(2);
            var match = candidates
                .Where(s => punchTime >= s.StartTime && punchTime <= s.EndTime + window)
                .OrderBy(s => Math.Abs((punchTime - s.EndTime).TotalMinutes))
                .ToList();
            chosen = match.FirstOrDefault()
                ?? candidates.OrderBy(s => Math.Abs((punchTime - s.EndTime).TotalMinutes)).First();
        }

        return (chosen.StartTime, chosen.EndTime);
    }

    private static string NormalizeShiftName(string s)
        => string.IsNullOrEmpty(s)
            ? string.Empty
            : System.Text.RegularExpressions.Regex.Replace(s.Trim().ToLowerInvariant(), @"\s+", " ");

    private static string ParseDescField(string? description, string key)
    {
        if (string.IsNullOrEmpty(description)) return string.Empty;
        foreach (var part in description.Split('|'))
        {
            var idx = part.IndexOf(':');
            if (idx <= 0) continue;
            if (string.Equals(part.Substring(0, idx).Trim(), key, StringComparison.Ordinal))
                return part.Substring(idx + 1).Trim();
        }
        return string.Empty;
    }
}