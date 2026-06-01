using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Core.Services.DeviceOperations;

/// <summary>
/// Service for parsing and processing employee data from device OPERLOG data.
/// </summary>
public class EmployeeOperationService(ILogger<EmployeeOperationService> logger) : IDeviceUserOperationService
{
    // Field identifiers based on protocol
    private const string USER_PREFIX = "USER";
    private const string PIN_KEY = "PIN";
    private const string NAME_KEY = "Name";
    private const string PRI_KEY = "Pri";
    private const string PASSWORD_KEY = "Passwd";
    private const string CARD_KEY = "Card";
    private const string GROUP_KEY = "Grp";
    private const string TIMEZONE_KEY = "TZ";
    private const string VERIFY_KEY = "Verify";
    private const string VICECARD_KEY = "ViceCard";
    // Chỉ bắt buộc PIN + Name; một số firmware gửi ít field hơn (Card/Grp/TZ có thể thiếu)
    private const int MIN_FIELDS = 2;

    /// <summary>
    /// Parses and processes employee data from device OPERLOG format.
    /// </summary>
    public async Task<List<DeviceUser>> ProcessUsersFromDeviceAsync(Device device, string body)
    {
        var employeeLines = ExtractEmployeeLines(body);
        logger.LogInformation("Processing {Count} employee records from device {DeviceId}",
            employeeLines.Count, device.Id);

        var employees = await ProcessEmployeeLinesAsync(device, employeeLines);
        logger.LogInformation("Successfully processed {Count} employee records from device {DeviceId}",
            employees.Count, device.Id);

        return employees;
    }

    private static List<string> ExtractEmployeeLines(string body)
    {
        var lines = body.Split(['\n', '\r'], StringSplitOptions.RemoveEmptyEntries)
            .Where(line => !string.IsNullOrWhiteSpace(line))
            .Select(line => line.Trim())
            .ToList();

        var operLogLines = lines.Where(l => l.StartsWith(USER_PREFIX, StringComparison.OrdinalIgnoreCase)).ToList();
        if (operLogLines.Count > 0)
        {
            return operLogLines;
        }

        // POST table=USERINFO: mỗi dòng PIN=...\tName=... (không có tiền tố USER)
        return lines.Where(l => l.Contains($"{PIN_KEY}=", StringComparison.OrdinalIgnoreCase)).ToList();
    }

    private async Task<List<DeviceUser>> ProcessEmployeeLinesAsync(Device device, List<string> employeeLines)
    {
        var employees = new List<DeviceUser>();

        foreach (var line in employeeLines)
        {
            try
            {
                var employee = await TryProcessEmployeeLineAsync(device, line);
                if (employee != null)
                {
                    employees.Add(employee);
                }
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Unexpected error processing employee line from device {DeviceId}: {Line}",
                    device.Id, line);
            }
        }

        return employees;
    }

    private Task<DeviceUser?> TryProcessEmployeeLineAsync(Device device, string line)
    {
        var employeeFields = ParseEmployeeLine(line);

        if (employeeFields == null || !ValidateEmployeeFields(employeeFields))
        {
            return Task.FromResult<DeviceUser?>(null);
        }

        return Task.FromResult(ExtractEmployeeData(employeeFields, device.Id));
    }

    /// <summary>
    /// Parses an employee line into key-value pairs.
    /// Format: USER PIN=982\tName=Richard\tPasswd=9822\tCard=13375590\tGrp=1\tTZ=
    /// </summary>
    private Dictionary<string, string>? ParseEmployeeLine(string line)
    {
        try
        {
            var fields = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

            var content = line.TrimStart();
            if (content.StartsWith(USER_PREFIX, StringComparison.OrdinalIgnoreCase))
            {
                content = content.Substring(USER_PREFIX.Length).TrimStart();
            }

            var parts = content.Split('\t', StringSplitOptions.RemoveEmptyEntries);
            foreach (var part in parts)
            {
                var keyValue = part.Split('=', 2);
                if (keyValue.Length != 2) continue;
                fields[keyValue[0].Trim()] = keyValue[1].Trim();
            }

            return fields.Count > 0 ? fields : null;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error parsing user line: {Line}", line);
            return null;
        }
    }

    private bool ValidateEmployeeFields(Dictionary<string, string> fields)
    {
        if (!fields.TryGetValue(PIN_KEY, out var pinValue) || string.IsNullOrWhiteSpace(pinValue))
        {
            logger.LogWarning("Employee record missing required PIN field");
            return false;
        }

        if (!fields.TryGetValue(NAME_KEY, out var nameValue) || string.IsNullOrWhiteSpace(nameValue))
        {
            logger.LogWarning("Employee record missing required Name field for PIN: {PIN}",
                fields.GetValueOrDefault(PIN_KEY));
            return false;
        }

        return true;
    }

    private DeviceUser? ExtractEmployeeData(Dictionary<string, string> fields, Guid deviceId)
    {
        try
        {
            var employee = new DeviceUser
            {
                Pin = ExtractField(fields, PIN_KEY, string.Empty) ?? string.Empty,
                Name = ExtractField(fields, NAME_KEY, string.Empty)!,
                Password = ExtractField(fields, PASSWORD_KEY),
                CardNumber = ExtractField(fields, CARD_KEY),
                GroupId = ExtractIntField(fields, GROUP_KEY, 1),
                Privilege = ExtractIntField(fields, PRI_KEY),
                DeviceId = deviceId,
                IsActive = true,
            };
            return employee;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error extracting employee data from fields");
            return null;
        }
    }

    private string? ExtractField(Dictionary<string, string> fields, string key, string? defaultValue = null)
    {
        if (fields.TryGetValue(key, out var value) && !string.IsNullOrWhiteSpace(value))
        {
            return value;
        }
        return defaultValue;
    }

    private int ExtractIntField(Dictionary<string, string> fields, string key, int defaultValue = 0)
    {
        if (fields.TryGetValue(key, out var value) && int.TryParse(value, out var intValue))
        {
            return intValue;
        }

        if (!string.IsNullOrWhiteSpace(value))
        {
            logger.LogDebug("Failed to parse integer field {Key}: {Value}. Using default: {Default}",
                key, value, defaultValue);
        }

        return defaultValue;
    }
}
