using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Helpers;

/// <summary>Resolve attendance log by id or PIN + date/time (corrections, sync dedupe).</summary>
public static class AttendanceLogResolveHelper
{
    public const int NearDuplicateWindowSeconds = 60;

    /// <summary>Device PIN for an employee (device user PIN, else employee code).</summary>
    public static async Task<string?> ResolvePinAsync(
        IRepository<DeviceUser> deviceUserRepository,
        IRepository<Employee> employeeRepository,
        Guid? storeId,
        string? employeeCode,
        string? pin,
        Guid? employeeId,
        CancellationToken cancellationToken = default)
    {
        if (!string.IsNullOrWhiteSpace(pin))
        {
            var p = pin.Trim();
            var duMatch = await deviceUserRepository.GetSingleAsync(
                d => d.Pin == p,
                cancellationToken: cancellationToken);
            if (duMatch != null)
                return p;
            // Client có thể gửi nhầm mã HR vào trường pin — tra tiếp như employeeCode.
        }

        if (employeeId.HasValue)
        {
            var du = await deviceUserRepository.GetSingleAsync(
                d => d.EmployeeId == employeeId,
                cancellationToken: cancellationToken);
            if (!string.IsNullOrWhiteSpace(du?.Pin))
                return du.Pin.Trim();
        }

        if (!string.IsNullOrWhiteSpace(employeeCode))
        {
            var code = employeeCode.Trim();
            var duByPin = await deviceUserRepository.GetSingleAsync(
                d => d.Pin == code,
                cancellationToken: cancellationToken);
            if (!string.IsNullOrWhiteSpace(duByPin?.Pin))
                return duByPin.Pin.Trim();

            if (storeId.HasValue)
            {
                var emp = await employeeRepository.GetSingleAsync(
                    e => e.StoreId == storeId && e.EmployeeCode == code,
                    cancellationToken: cancellationToken);
                if (emp != null)
                {
                    var du = await deviceUserRepository.GetSingleAsync(
                        d => d.EmployeeId == emp.Id,
                        cancellationToken: cancellationToken);
                    if (!string.IsNullOrWhiteSpace(du?.Pin))
                        return du.Pin.Trim();
                }
            }

            return code;
        }

        return null;
    }

    public static DateTime? BuildTargetTime(DateTime? oldDate, TimeSpan? oldTime)
    {
        if (!oldDate.HasValue || !oldTime.HasValue)
            return null;
        return oldDate.Value.Date.Add(oldTime.Value);
    }

    /// <summary>Find log for correction delete/edit (id first, then PIN + time).</summary>
    public static async Task<Attendance?> FindLogForCorrectionAsync(
        IRepository<Attendance> attendanceRepository,
        IRepository<DeviceUser> deviceUserRepository,
        IRepository<Employee> employeeRepository,
        Guid? storeId,
        string? employeeCode,
        string? pin,
        Guid? attendanceId,
        DateTime? oldDate,
        TimeSpan? oldTime,
        Guid? employeeId = null,
        CancellationToken cancellationToken = default)
    {
        if (attendanceId.HasValue && attendanceId.Value != Guid.Empty)
        {
            var byId = await attendanceRepository.GetByIdAsync(
                attendanceId.Value, cancellationToken: cancellationToken);
            if (byId != null)
                return byId;
        }

        var resolvedPin = await ResolvePinAsync(
            deviceUserRepository, employeeRepository, storeId, employeeCode, pin,
            employeeId, cancellationToken);
        var target = BuildTargetTime(oldDate, oldTime);

        if (employeeId.HasValue && target.HasValue)
        {
            var byEmployee = await FindByEmployeeIdAndTimeAsync(
                attendanceRepository, employeeId.Value, target.Value, cancellationToken);
            if (byEmployee != null)
                return byEmployee;
        }

        if (string.IsNullOrEmpty(resolvedPin) || !target.HasValue)
            return null;

        return await FindByPinAndTimeAsync(
            attendanceRepository, resolvedPin, target.Value, cancellationToken);
    }

    /// <summary>Find log by HR employee id + punch time (fallback when PIN/client time drift).</summary>
    public static async Task<Attendance?> FindByEmployeeIdAndTimeAsync(
        IRepository<Attendance> attendanceRepository,
        Guid employeeId,
        DateTime targetTime,
        CancellationToken cancellationToken = default)
    {
        static Attendance? PickNearest(IReadOnlyList<Attendance> list, DateTime target)
        {
            if (list.Count == 0)
                return null;
            var exact = list.FirstOrDefault(a => a.AttendanceTime == target);
            return exact ?? list
                .OrderBy(a => Math.Abs((a.AttendanceTime - target).TotalSeconds))
                .First();
        }

        async Task<List<Attendance>> QueryWindowAsync(DateTime start, DateTime end) =>
            (await attendanceRepository.GetAllAsync(
                a => a.EmployeeId == employeeId
                     && a.AttendanceTime >= start
                     && a.AttendanceTime <= end,
                cancellationToken: cancellationToken)).ToList();

        var tight = await QueryWindowAsync(
            targetTime.AddSeconds(-2), targetTime.AddSeconds(2));
        var pick = PickNearest(tight, targetTime);
        if (pick != null)
            return pick;

        var minuteStart = new DateTime(
            targetTime.Year, targetTime.Month, targetTime.Day,
            targetTime.Hour, targetTime.Minute, 0);
        var minuteEnd = minuteStart.AddMinutes(1).AddTicks(-1);
        var sameMinute = await QueryWindowAsync(minuteStart, minuteEnd);
        pick = PickNearest(sameMinute, targetTime);
        if (pick != null)
            return pick;

        // UI có thể hiển thị giờ ca (snap) lệch vài chục phút so với log máy.
        const int employeeMatchWindowSeconds = 1800;
        var wide = await QueryWindowAsync(
            targetTime.AddSeconds(-employeeMatchWindowSeconds),
            targetTime.AddSeconds(employeeMatchWindowSeconds));
        return PickNearest(wide, targetTime);
    }

    public static async Task<Attendance?> FindByPinAndTimeAsync(
        IRepository<Attendance> attendanceRepository,
        string pin,
        DateTime targetTime,
        CancellationToken cancellationToken = default)
    {
        var pinNorm = pin.Trim();
        var pinUpper = pinNorm.ToUpperInvariant();

        static Attendance? PickNearest(IReadOnlyList<Attendance> list, DateTime target)
        {
            if (list.Count == 0)
                return null;
            var exact = list.FirstOrDefault(a => a.AttendanceTime == target);
            return exact ?? list
                .OrderBy(a => Math.Abs((a.AttendanceTime - target).TotalSeconds))
                .First();
        }

        async Task<List<Attendance>> QueryWindowAsync(DateTime start, DateTime end) =>
            (await attendanceRepository.GetAllAsync(
                a => a.PIN.ToUpper() == pinUpper
                     && a.AttendanceTime >= start
                     && a.AttendanceTime <= end,
                cancellationToken: cancellationToken)).ToList();

        // ±2s, then same minute, then ±120s (máy ZKTeco / làm tròn phút trên UI).
        var tight = await QueryWindowAsync(
            targetTime.AddSeconds(-2), targetTime.AddSeconds(2));
        var pick = PickNearest(tight, targetTime);
        if (pick != null)
            return pick;

        var minuteStart = new DateTime(
            targetTime.Year, targetTime.Month, targetTime.Day,
            targetTime.Hour, targetTime.Minute, 0);
        var minuteEnd = minuteStart.AddMinutes(1).AddTicks(-1);
        var sameMinute = await QueryWindowAsync(minuteStart, minuteEnd);
        pick = PickNearest(sameMinute, targetTime);
        if (pick != null)
            return pick;

        var wide = await QueryWindowAsync(
            targetTime.AddSeconds(-NearDuplicateWindowSeconds),
            targetTime.AddSeconds(NearDuplicateWindowSeconds));
        return PickNearest(wide, targetTime);
    }

    public static bool IsNearDuplicateOfExisting(
        Attendance candidate,
        IReadOnlyList<Attendance> existingOnDevice)
    {
        foreach (var e in existingOnDevice)
        {
            if (!string.Equals(e.PIN, candidate.PIN, StringComparison.OrdinalIgnoreCase))
                continue;
            var delta = Math.Abs((e.AttendanceTime - candidate.AttendanceTime).TotalSeconds);
            if (delta <= NearDuplicateWindowSeconds)
                return true;
        }
        return false;
    }
}
