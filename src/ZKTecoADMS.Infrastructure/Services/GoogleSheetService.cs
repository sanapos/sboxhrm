using Google.Apis.Auth.OAuth2;
using Google.Apis.Services;
using Google.Apis.Sheets.v4;
using Google.Apis.Sheets.v4.Data;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Settings;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>
/// Google Sheets Service - Đẩy dữ liệu chấm công realtime lên Google Sheet
/// </summary>
public class GoogleSheetService : IGoogleSheetService
{
    private readonly ILogger<GoogleSheetService> _logger;
    private readonly GoogleSheetSettings _settings;
    private readonly string _contentRootPath;
    private SheetsService? _sheetsService;
    private bool _isInitialized = false;

    public GoogleSheetService(
        ILogger<GoogleSheetService> logger,
        IOptions<GoogleSheetSettings> settings,
        IWebHostEnvironment env)
    {
        _logger = logger;
        _settings = settings.Value;
        _contentRootPath = env.ContentRootPath;
    }

    public async Task<bool> InitializeAsync(string? spreadsheetId = null, string? credentialJson = null)
    {
        try
        {
            var rawPath = credentialJson ?? _settings.CredentialsPath;
            var credPath = Path.IsPathRooted(rawPath) ? rawPath : Path.Combine(_contentRootPath, rawPath);
            var spreadsheet = spreadsheetId ?? _settings.SpreadsheetId;

            if (string.IsNullOrEmpty(spreadsheet))
            {
                _logger.LogWarning("Google Sheets SpreadsheetId is not configured");
                return false;
            }

            if (!File.Exists(credPath))
            {
                _logger.LogWarning("Google credentials file not found: {Path}", credPath);
                return false;
            }

            GoogleCredential credential;
            await using (var stream = new FileStream(credPath, FileMode.Open, FileAccess.Read))
            {
                credential = GoogleCredential.FromStream(stream)
                    .CreateScoped(SheetsService.Scope.Spreadsheets);
            }

            _sheetsService = new SheetsService(new BaseClientService.Initializer
            {
                HttpClientInitializer = credential,
                ApplicationName = _settings.ApplicationName
            });

            _isInitialized = true;
            _logger.LogInformation("Google Sheets service initialized successfully");

            // Tạo các sheet nếu chưa có
            await EnsureSheetsExistAsync();

            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to initialize Google Sheets service");
            return false;
        }
    }

    private async Task EnsureSheetsExistAsync()
    {
        if (_sheetsService == null) return;

        try
        {
            var spreadsheet = await _sheetsService.Spreadsheets.Get(_settings.SpreadsheetId).ExecuteAsync();
            var existingSheets = spreadsheet.Sheets.Select(s => s.Properties.Title).ToList();

            var requiredSheets = new[]
            {
                _settings.AttendanceSheetName,
                _settings.EmployeesSheetName,
                _settings.DevicesSheetName,
                _settings.DailyReportSheetName
            };

            var sheetsToCreate = requiredSheets.Where(s => !existingSheets.Contains(s)).ToList();

            if (sheetsToCreate.Count > 0)
            {
                var requests = sheetsToCreate.Select(sheetName => new Request
                {
                    AddSheet = new AddSheetRequest
                    {
                        Properties = new SheetProperties { Title = sheetName }
                    }
                }).ToList();

                var batchUpdate = new BatchUpdateSpreadsheetRequest { Requests = requests };
                await _sheetsService.Spreadsheets.BatchUpdate(batchUpdate, _settings.SpreadsheetId).ExecuteAsync();

                // Thêm header cho từng sheet
                foreach (var sheetName in sheetsToCreate)
                {
                    await AddHeadersToSheetAsync(sheetName);
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to ensure sheets exist");
        }
    }

    private async Task AddHeadersToSheetAsync(string sheetName)
    {
        if (_sheetsService == null) return;

        IList<object> headers = sheetName switch
        {
            var s when s == _settings.AttendanceSheetName => new List<object>
            {
                "ID", "Mã NV", "Tên NV", "Thiết bị", "Thời gian", "Loại xác thực",
                "Trạng thái", "Ngày tạo"
            },
            var s when s == _settings.EmployeesSheetName => new List<object>
            {
                "ID", "Mã NV", "Tên NV", "Thẻ", "Quyền", "Thiết bị", "Ngày tạo"
            },
            var s when s == _settings.DevicesSheetName => new List<object>
            {
                "ID", "Serial Number", "Tên thiết bị", "IP", "Vị trí", "Trạng thái",
                "Online lần cuối", "Ngày tạo"
            },
            var s when s == _settings.DailyReportSheetName => new List<object>
            {
                "Ngày", "Mã NV", "Tên NV", "Giờ vào", "Giờ ra", "Tổng giờ làm", "Ghi chú"
            },
            _ => new List<object>()
        };

        if (headers.Count == 0) return;

        var range = $"{sheetName}!A1";
        var valueRange = new ValueRange
        {
            Values = new List<IList<object>> { headers }
        };

        var request = _sheetsService.Spreadsheets.Values.Update(valueRange, _settings.SpreadsheetId, range);
        request.ValueInputOption = SpreadsheetsResource.ValuesResource.UpdateRequest.ValueInputOptionEnum.RAW;
        await request.ExecuteAsync();

        _logger.LogInformation("Added headers to sheet: {SheetName}", sheetName);
    }

    public async Task<bool> PushAttendanceAsync(Attendance attendance, DeviceUser employee, Device device)
    {
        if (!_isInitialized || _sheetsService == null)
        {
            _logger.LogWarning("Google Sheets service not initialized");
            return false;
        }

        if (!_settings.EnableRealtimeSync)
        {
            return true;
        }

        try
        {
            var range = $"{_settings.AttendanceSheetName}!A:H";
            var values = new List<IList<object>>
            {
                new List<object>
                {
                    attendance.Id.ToString(),
                    employee.Pin,
                    employee.Name,
                    device.DeviceName,
                    attendance.AttendanceTime.ToString("yyyy-MM-dd HH:mm:ss"),
                    attendance.VerifyMode.ToString(),
                    attendance.AttendanceState.ToString(),
                    DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss")
                }
            };

            var valueRange = new ValueRange { Values = values };
            var request = _sheetsService.Spreadsheets.Values.Append(valueRange, _settings.SpreadsheetId, range);
            request.ValueInputOption = SpreadsheetsResource.ValuesResource.AppendRequest.ValueInputOptionEnum.RAW;
            await request.ExecuteAsync();

            _logger.LogInformation("Pushed attendance to Google Sheet: Employee={EmployeeName}, Time={Time}",
                employee.Name, attendance.AttendanceTime);

            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to push attendance to Google Sheet");
            return false;
        }
    }

    public async Task<bool> PushAttendancesAsync(IEnumerable<Attendance> attendances, Device device)
    {
        if (!_isInitialized || _sheetsService == null)
        {
            _logger.LogWarning("Google Sheets service not initialized");
            return false;
        }

        try
        {
            var attendanceList = attendances.ToList();
            if (attendanceList.Count == 0) return true;

            var range = $"{_settings.AttendanceSheetName}!A:H";
            var values = attendanceList.Select(a => (IList<object>)new List<object>
            {
                a.Id.ToString(),
                a.Employee?.Pin ?? a.PIN,
                a.Employee?.Name ?? "",
                device.DeviceName,
                a.AttendanceTime.ToString("yyyy-MM-dd HH:mm:ss"),
                a.VerifyMode.ToString(),
                a.AttendanceState.ToString(),
                DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss")
            }).ToList();

            var valueRange = new ValueRange { Values = values };
            var request = _sheetsService.Spreadsheets.Values.Append(valueRange, _settings.SpreadsheetId, range);
            request.ValueInputOption = SpreadsheetsResource.ValuesResource.AppendRequest.ValueInputOptionEnum.RAW;
            await request.ExecuteAsync();

            _logger.LogInformation("Pushed {Count} attendances to Google Sheet from device {DeviceName}",
                attendanceList.Count, device.DeviceName);

            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to push attendances to Google Sheet");
            return false;
        }
    }

    public async Task<bool> SyncEmployeesToSheetAsync(IEnumerable<DeviceUser> employees)
    {
        if (!_isInitialized || _sheetsService == null)
        {
            _logger.LogWarning("Google Sheets service not initialized");
            return false;
        }

        try
        {
            var employeeList = employees.ToList();
            if (employeeList.Count == 0) return true;

            // Clear existing data (except header)
            var clearRange = $"{_settings.EmployeesSheetName}!A2:G";
            var clearRequest = _sheetsService.Spreadsheets.Values.Clear(
                new ClearValuesRequest(), _settings.SpreadsheetId, clearRange);
            await clearRequest.ExecuteAsync();

            // Add new data
            var range = $"{_settings.EmployeesSheetName}!A2:G";
            var values = employeeList.Select(e => (IList<object>)new List<object>
            {
                e.Id.ToString(),
                e.Pin,
                e.Name,
                e.CardNumber ?? "",
                e.Privilege.ToString(),
                e.Device?.DeviceName ?? "",
                e.CreatedAt.ToString("yyyy-MM-dd HH:mm:ss")
            }).ToList();

            var valueRange = new ValueRange { Values = values };
            var request = _sheetsService.Spreadsheets.Values.Update(valueRange, _settings.SpreadsheetId, range);
            request.ValueInputOption = SpreadsheetsResource.ValuesResource.UpdateRequest.ValueInputOptionEnum.RAW;
            await request.ExecuteAsync();

            _logger.LogInformation("Synced {Count} employees to Google Sheet", employeeList.Count);
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to sync employees to Google Sheet");
            return false;
        }
    }

    public async Task<bool> SyncDevicesToSheetAsync(IEnumerable<Device> devices)
    {
        if (!_isInitialized || _sheetsService == null)
        {
            _logger.LogWarning("Google Sheets service not initialized");
            return false;
        }

        try
        {
            var deviceList = devices.ToList();
            if (deviceList.Count == 0) return true;

            // Clear existing data (except header)
            var clearRange = $"{_settings.DevicesSheetName}!A2:H";
            var clearRequest = _sheetsService.Spreadsheets.Values.Clear(
                new ClearValuesRequest(), _settings.SpreadsheetId, clearRange);
            await clearRequest.ExecuteAsync();

            // Add new data
            var range = $"{_settings.DevicesSheetName}!A2:H";
            var values = deviceList.Select(d => (IList<object>)new List<object>
            {
                d.Id.ToString(),
                d.SerialNumber,
                d.DeviceName,
                d.IpAddress ?? "",
                d.Location ?? "",
                d.DeviceStatus,
                d.LastOnline?.ToString("yyyy-MM-dd HH:mm:ss") ?? "",
                d.CreatedAt.ToString("yyyy-MM-dd HH:mm:ss")
            }).ToList();

            var valueRange = new ValueRange { Values = values };
            var request = _sheetsService.Spreadsheets.Values.Update(valueRange, _settings.SpreadsheetId, range);
            request.ValueInputOption = SpreadsheetsResource.ValuesResource.UpdateRequest.ValueInputOptionEnum.RAW;
            await request.ExecuteAsync();

            _logger.LogInformation("Synced {Count} devices to Google Sheet", deviceList.Count);
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to sync devices to Google Sheet");
            return false;
        }
    }

    public async Task<bool> PushDailyReportAsync(DateTime date, IEnumerable<Attendance> attendances)
    {
        if (!_isInitialized || _sheetsService == null)
        {
            _logger.LogWarning("Google Sheets service not initialized");
            return false;
        }

        try
        {
            var attendanceList = attendances
                .Where(a => a.AttendanceTime.Date == date.Date)
                .GroupBy(a => a.EmployeeId)
                .ToList();

            if (attendanceList.Count == 0) return true;

            var range = $"{_settings.DailyReportSheetName}!A:G";
            var values = new List<IList<object>>();

            foreach (var group in attendanceList)
            {
                var sortedAttendances = group.OrderBy(a => a.AttendanceTime).ToList();
                var firstIn = sortedAttendances.FirstOrDefault();
                var lastOut = sortedAttendances.LastOrDefault();

                if (firstIn == null) continue;

                var totalHours = lastOut != null && lastOut != firstIn
                    ? (lastOut.AttendanceTime - firstIn.AttendanceTime).TotalHours
                    : 0;

                values.Add(new List<object>
                {
                    date.ToString("yyyy-MM-dd"),
                    firstIn.Employee?.Pin ?? firstIn.PIN,
                    firstIn.Employee?.Name ?? "",
                    firstIn.AttendanceTime.ToString("HH:mm:ss"),
                    lastOut?.AttendanceTime.ToString("HH:mm:ss") ?? "",
                    totalHours.ToString("F2"),
                    ""
                });
            }

            var valueRange = new ValueRange { Values = values };
            var request = _sheetsService.Spreadsheets.Values.Append(valueRange, _settings.SpreadsheetId, range);
            request.ValueInputOption = SpreadsheetsResource.ValuesResource.AppendRequest.ValueInputOptionEnum.RAW;
            await request.ExecuteAsync();

            _logger.LogInformation("Pushed daily report for {Date} to Google Sheet", date.ToString("yyyy-MM-dd"));
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to push daily report to Google Sheet");
            return false;
        }
    }

    public async Task<bool> TestConnectionAsync()
    {
        if (!_isInitialized || _sheetsService == null)
        {
            await InitializeAsync(_settings.SpreadsheetId, _settings.CredentialsPath);
        }

        if (_sheetsService == null) return false;

        try
        {
            var spreadsheet = await _sheetsService.Spreadsheets.Get(_settings.SpreadsheetId).ExecuteAsync();
            _logger.LogInformation("Google Sheets connection test successful. Spreadsheet: {Title}",
                spreadsheet.Properties.Title);
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Google Sheets connection test failed");
            return false;
        }
    }
}
