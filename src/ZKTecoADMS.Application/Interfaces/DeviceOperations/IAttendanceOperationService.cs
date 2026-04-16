namespace ZKTecoADMS.Application.Interfaces;

/// <summary>
/// Service interface for parsing and processing attendance data from device attendance logs.
/// </summary>
public interface IAttendanceOperationService
{
    /// <summary>
    /// Parses and processes attendance data from device log format.
    /// Format: [PIN]\t[Punch date/time]\t[Attendance State]\t[Verify Mode]\t[Workcode]\t[Reserved 1]\t[Reserved 2]
    /// </summary>
    Task<List<Attendance>> ProcessAttendancesFromDeviceAsync(Device device, string body);
}
