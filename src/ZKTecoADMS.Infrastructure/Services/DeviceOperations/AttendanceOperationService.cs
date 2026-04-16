using System.Globalization;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Core.Services.DeviceOperations;

/// <summary>
/// Service for parsing and processing attendance data from device attendance logs.
/// </summary>
public class AttendanceOperationService(
    ILogger<AttendanceOperationService> logger,
    IRepository<Attendance> attendanceRepository,
    IDeviceUserService employeeService) : IAttendanceOperationService
{
    // Field indices based on TFT protocol
    // Format: [PIN]\t[Punch date/time]\t[Attendance State]\t[Verify Mode]\t[Workcode]\t[Reserved 1]\t[Reserved 2]
    private const int PIN_INDEX = 0;
    private const int PUNCH_DATETIME_INDEX = 1;
    private const int ATTENDANCE_STATE_INDEX = 2;
    private const int VERIFY_MODE_INDEX = 3;
    private const int WORKCODE_INDEX = 4;
    private const int MIN_FIELD_COUNT = 4; // Minimum required fields
    private const int EXPECTED_FIELD_COUNT = 7;
    private const string DATETIME_FORMAT = "yyyy-MM-dd HH:mm:ss";

    /// <summary>
    /// Parses and processes attendance data from device log format.
    /// </summary>
    public async Task<List<Attendance>> ProcessAttendancesFromDeviceAsync(Device device, string body)
    {
        var attendanceLines = ExtractAttendanceLines(body);
        logger.LogInformation("Device SN-{SN}: processed {Count} attendance lines from device {DeviceName}",
            device.SerialNumber, attendanceLines.Count, device.DeviceName);

        var attendances = await ProcessAttendanceLinesAsync(device, attendanceLines);
        logger.LogInformation("Device SN-{SN}: parsed {Count} attendance records from device {DeviceName}",
            device.SerialNumber, attendances.Count, device.DeviceName);

        return attendances;
    }

    private static List<string> ExtractAttendanceLines(string body)
    {
        return body.Split(['\n', '\r'], StringSplitOptions.RemoveEmptyEntries)
                   .Where(line => !string.IsNullOrWhiteSpace(line))
                   .ToList();
    }

    private async Task<List<Attendance>> ProcessAttendanceLinesAsync(Device device, List<string> lines)
    {
        var attendances = new List<Attendance>();
        int duplicateCount = 0;
        int parseFailCount = 0;
        int invalidFieldCount = 0;

        foreach (var line in lines)
        {
            try
            {
                var attendance = await TryProcessAttendanceLineAsync(device, line);
                if (attendance != null)
                {
                    attendances.Add(attendance);
                }
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Unexpected error processing attendance line from device {DeviceId}: {Line}",
                    device.Id, line);
            }
        }

        logger.LogWarning("Device {DeviceId}: Processed {Total} lines -> {Valid} valid, {Dup} duplicates, {ParseFail} parse failures, {FieldFail} field count failures",
            device.Id, lines.Count, attendances.Count, duplicateCount, parseFailCount, invalidFieldCount);

        return attendances;
    }

    private async Task<Attendance?> TryProcessAttendanceLineAsync(Device device, string line)
    {
        var fields = SplitLineIntoFields(line);

        if (!ValidateFieldCount(fields, line))
        {
            return null;
        }

        var attendanceData = ParseAttendanceFields(fields);
        if (attendanceData == null)
        {
            logger.LogWarning("Failed to parse attendance data from line: {Line}", line);
            return null;
        }

        if (await IsDuplicateAttendanceAsync(device.Id, attendanceData))
        {
            logger.LogWarning("Duplicate attendance record skipped for PIN {PIN} at {Time} on device {DeviceId}",
                attendanceData.PIN, attendanceData.AttendanceTime, device.Id);
            return null;
        }

        return await CreateAttendanceRecordAsync(device.Id, attendanceData);
    }

    private static string[] SplitLineIntoFields(string line)
    {
        return line.Split('\t', StringSplitOptions.None);
    }

    private bool ValidateFieldCount(string[] fields, string line)
    {
        if (fields.Length < MIN_FIELD_COUNT)
        {
            logger.LogWarning(
                "Invalid attendance record format. Expected at least {Min} fields but got {Actual}. Line: {Line}",
                MIN_FIELD_COUNT, fields.Length, line);
            // Log hex representation of the first 50 chars for debugging tab characters
            var hex = string.Join(" ", line.Take(60).Select(c => $"{(int)c:X2}({c})"));
            logger.LogWarning("Line hex dump (first 60 chars): {Hex}", hex);
            return false;
        }

        if (fields.Length < EXPECTED_FIELD_COUNT)
        {
            logger.LogDebug(
                "Attendance record has fewer fields than expected. Expected {Expected} but got {Actual}",
                EXPECTED_FIELD_COUNT, fields.Length);
        }

        return true;
    }

    private async Task<bool> IsDuplicateAttendanceAsync(Guid deviceId, AttendanceData attendanceData)
    {
        return await attendanceRepository.ExistsAsync(a => 
            a.DeviceId == deviceId && 
            a.PIN == attendanceData.PIN && 
            a.AttendanceTime == attendanceData.AttendanceTime);
    }

    private async Task<Attendance> CreateAttendanceRecordAsync(Guid deviceId, AttendanceData attendanceData)
    {
        var employee = await employeeService.GetDeviceUserByPinAsync(deviceId, attendanceData.PIN);

        return new Attendance
        {
            Id = Guid.NewGuid(),
            DeviceId = deviceId,
            PIN = attendanceData.PIN,
            AttendanceTime = attendanceData.AttendanceTime,
            AttendanceState = attendanceData.AttendanceState,
            VerifyMode = attendanceData.VerifyMode,
            WorkCode = attendanceData.WorkCode,
            EmployeeId = employee?.Id
        };
    }

    private AttendanceData? ParseAttendanceFields(string[] fields)
    {
        try
        {
            var pin = ExtractPin(fields);
            var attendanceTime = ParseAttendanceTime(fields);
            var attendanceState = ParseAttendanceState(fields);
            var verifyMode = ParseVerifyMode(fields);
            var workCode = ExtractWorkCode(fields);

            if (attendanceTime == null || attendanceState == null)
            {
                return null;
            }

            return new AttendanceData
            {
                PIN = pin,
                AttendanceTime = attendanceTime.Value,
                AttendanceState = attendanceState.Value,
                VerifyMode = verifyMode,
                WorkCode = workCode
            };
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error parsing attendance fields");
            return null;
        }
    }

    private static string ExtractPin(string[] fields)
    {
        return fields[PIN_INDEX].Trim();
    }

    private DateTime? ParseAttendanceTime(string[] fields)
    {
        var dateTimeString = fields[PUNCH_DATETIME_INDEX].Trim();

        if (DateTime.TryParseExact(
            dateTimeString,
            DATETIME_FORMAT,
            CultureInfo.InvariantCulture,
            DateTimeStyles.None,
            out var attendanceTime))
        {
            return attendanceTime;
        }

        logger.LogWarning("Failed to parse datetime: {DateTime}. Expected format: {Format}",
            dateTimeString, DATETIME_FORMAT);
        return null;
    }

    private AttendanceStates? ParseAttendanceState(string[] fields)
    {
        var stateString = fields[ATTENDANCE_STATE_INDEX].Trim();

        if (int.TryParse(stateString, out var stateValue))
        {
            return MapAttendanceState(stateValue);
        }

        logger.LogWarning("Failed to parse attendance state: {State}", stateString);
        return null;
    }

    private VerifyModes ParseVerifyMode(string[] fields)
    {
        if (fields.Length <= VERIFY_MODE_INDEX)
        {
            return VerifyModes.Unknown;
        }

        var verifyModeString = fields[VERIFY_MODE_INDEX].Trim();

        if (int.TryParse(verifyModeString, out var verifyModeValue))
        {
            return MapVerifyMode(verifyModeValue);
        }

        logger.LogDebug("Failed to parse verify mode: {VerifyMode}. Using Unknown", verifyModeString);
        return VerifyModes.Unknown;
    }

    private static string? ExtractWorkCode(string[] fields)
    {
        if (fields.Length <= WORKCODE_INDEX)
        {
            return null;
        }

        var workCode = fields[WORKCODE_INDEX].Trim();
        return string.IsNullOrWhiteSpace(workCode) ? null : workCode;
    }

    /// <summary>
    /// Maps device attendance state values to our enum.
    /// Based on ZKTeco device protocol:
    /// 0=Check In, 1=Check Out, 2=Break Out, 3=Break In, 4=Meal Out, 5=Meal In
    /// </summary>
    private static AttendanceStates MapAttendanceState(int stateValue)
    {
        return stateValue switch
        {
            0 => AttendanceStates.CheckIn,
            1 => AttendanceStates.CheckOut,
            2 => AttendanceStates.BreakOut,
            3 => AttendanceStates.BreakIn,
            4 => AttendanceStates.MealOut,
            5 => AttendanceStates.MealIn,
            _ => AttendanceStates.CheckIn // Default to CheckIn for unknown states
        };
    }

    /// <summary>
    /// Maps device verify mode values to our enum.
    /// Based on ZKTeco device protocol verification methods.
    /// </summary>
    private static VerifyModes MapVerifyMode(int modeValue)
    {
        return modeValue switch
        {
            0 => VerifyModes.Password,
            1 => VerifyModes.Finger,
            2 => VerifyModes.Badge,
            3 => VerifyModes.PIN,
            4 => VerifyModes.PINAndFingerprint,
            5 => VerifyModes.FingerAndPassword,
            6 => VerifyModes.BadgeAndFinger,
            7 => VerifyModes.BadgeAndPassword,
            8 => VerifyModes.BadgeAndPasswordAndFinger,
            9 => VerifyModes.PINAndPasswordAndFinger,
            15 => VerifyModes.Face,
            _ => VerifyModes.Unknown
        };
    }

    /// <summary>
    /// Internal data transfer object for parsed attendance data
    /// </summary>
    private class AttendanceData
    {
        public required string PIN { get; set; }
        public DateTime AttendanceTime { get; set; }
        public AttendanceStates AttendanceState { get; set; }
        public VerifyModes VerifyMode { get; set; }
        public string? WorkCode { get; set; }
    }
}
