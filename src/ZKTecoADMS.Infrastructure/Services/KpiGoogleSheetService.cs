using Google.Apis.Auth.OAuth2;
using Google.Apis.Services;
using Google.Apis.Sheets.v4;
using Google.Apis.Sheets.v4.Data;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Settings;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>
/// Service đọc/ghi dữ liệu KPI từ/lên Google Sheets
/// </summary>
public class KpiGoogleSheetService : IKpiGoogleSheetService
{
    private readonly ILogger<KpiGoogleSheetService> _logger;
    private readonly GoogleSheetSettings _settings;
    private readonly string _contentRootPath;

    public KpiGoogleSheetService(
        ILogger<KpiGoogleSheetService> logger,
        IOptions<GoogleSheetSettings> settings,
        IWebHostEnvironment env)
    {
        _logger = logger;
        _settings = settings.Value;
        _contentRootPath = env.ContentRootPath;
    }

    private async Task<SheetsService> GetSheetsServiceAsync(string? credentialJson)
    {
        var rawPath = credentialJson ?? _settings.CredentialsPath;
        var credPath = Path.IsPathRooted(rawPath) ? rawPath : Path.Combine(_contentRootPath, rawPath);
        if (!File.Exists(credPath))
            throw new FileNotFoundException($"Google credentials file not found: {credPath}");

        GoogleCredential credential;
        await using (var stream = new FileStream(credPath, FileMode.Open, FileAccess.Read))
        {
            credential = GoogleCredential.FromStream(stream)
                .CreateScoped(SheetsService.Scope.Spreadsheets);
        }

        return new SheetsService(new BaseClientService.Initializer
        {
            HttpClientInitializer = credential,
            ApplicationName = _settings.ApplicationName
        });
    }

    /// <inheritdoc />
    public async Task<List<string>> GetSheetNamesAsync(string spreadsheetId, string? credentialJson = null)
    {
        try
        {
            var service = await GetSheetsServiceAsync(credentialJson);
            var spreadsheet = await service.Spreadsheets.Get(spreadsheetId).ExecuteAsync();
            return spreadsheet.Sheets.Select(s => s.Properties.Title).ToList();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to get sheet names from spreadsheet {Id}", spreadsheetId);
            throw;
        }
    }

    /// <inheritdoc />
    public async Task<List<string>> GetSheetHeadersAsync(string spreadsheetId, string sheetName, string? credentialJson = null)
    {
        try
        {
            var service = await GetSheetsServiceAsync(credentialJson);
            var range = $"{sheetName}!1:1";
            var request = service.Spreadsheets.Values.Get(spreadsheetId, range);
            var response = await request.ExecuteAsync();

            if (response.Values == null || response.Values.Count == 0)
                return new List<string>();

            return response.Values[0].Select(v => v?.ToString() ?? "").ToList();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to get sheet headers from {Sheet}", sheetName);
            throw;
        }
    }

    /// <summary>
    /// Normalize mã NV: loại bỏ .0, scientific notation, khoảng trắng
    /// </summary>
    private static string NormalizeCode(string raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return "";
        // Nếu là số (có thể dạng khoa học 4.91E+10 hoặc 49094008189.0)
        if (double.TryParse(raw, System.Globalization.NumberStyles.Any,
                System.Globalization.CultureInfo.InvariantCulture, out var num))
        {
            // Chuyển về dạng integer string (không có .0)
            return ((long)num).ToString();
        }
        return raw.Trim();
    }

    /// <summary>
    /// Parse giá trị số từ Google Sheet, hỗ trợ cả format VN (20.000.000) và US (20,000,000)
    /// </summary>
    private static bool TryParseNumber(string raw, out decimal result)
    {
        result = 0;
        if (string.IsNullOrWhiteSpace(raw)) return false;
        raw = raw.Trim();

        // Dạng VN: 20.000.000 (nhiều dấu chấm) → loại bỏ dấu chấm
        var dotCount = raw.Count(c => c == '.');
        var commaCount = raw.Count(c => c == ',');

        if (dotCount >= 2 && commaCount == 0)
        {
            // 20.000.000 → 20000000
            return decimal.TryParse(raw.Replace(".", ""), System.Globalization.NumberStyles.Any,
                System.Globalization.CultureInfo.InvariantCulture, out result);
        }
        if (commaCount >= 2 && dotCount == 0)
        {
            // 20,000,000 → 20000000
            return decimal.TryParse(raw.Replace(",", ""), System.Globalization.NumberStyles.Any,
                System.Globalization.CultureInfo.InvariantCulture, out result);
        }
        if (dotCount == 1 && commaCount >= 1)
        {
            // 20,000,000.50 → US format
            return decimal.TryParse(raw.Replace(",", ""), System.Globalization.NumberStyles.Any,
                System.Globalization.CultureInfo.InvariantCulture, out result);
        }
        if (commaCount == 1 && dotCount >= 1)
        {
            // 20.000.000,50 → EU/VN format
            return decimal.TryParse(raw.Replace(".", "").Replace(",", "."), System.Globalization.NumberStyles.Any,
                System.Globalization.CultureInfo.InvariantCulture, out result);
        }
        // Mặc định: thử parse bình thường
        if (decimal.TryParse(raw.Replace(",", "."), System.Globalization.NumberStyles.Any,
                System.Globalization.CultureInfo.InvariantCulture, out result))
            return true;
        return decimal.TryParse(raw, System.Globalization.NumberStyles.Any,
            System.Globalization.CultureInfo.InvariantCulture, out result);
    }

    /// <inheritdoc />
    public async Task<List<KpiSheetRow>> ReadKpiDataAsync(string spreadsheetId, string sheetName, string? credentialJson = null)
    {
        try
        {
            var service = await GetSheetsServiceAsync(credentialJson);
            var range = $"{sheetName}!A:ZZ";
            var request = service.Spreadsheets.Values.Get(spreadsheetId, range);
            var response = await request.ExecuteAsync();

            if (response.Values == null || response.Values.Count < 2)
            {
                _logger.LogWarning("No data found in sheet {Sheet}", sheetName);
                return new List<KpiSheetRow>();
            }

            // Dòng đầu tiên là header
            var headers = response.Values[0].Select(v => v?.ToString()?.Trim() ?? "").ToList();
            var results = new List<KpiSheetRow>();

            // Tìm cột mã nhân viên và tên
            var codeColIndex = headers.FindIndex(h =>
                h.Equals("EmployeeCode", StringComparison.OrdinalIgnoreCase) ||
                h.Equals("Mã NV", StringComparison.OrdinalIgnoreCase) ||
                h.Equals("MaNV", StringComparison.OrdinalIgnoreCase) ||
                h.Equals("Ma_NV", StringComparison.OrdinalIgnoreCase) ||
                h.Equals("Code", StringComparison.OrdinalIgnoreCase));

            var nameColIndex = headers.FindIndex(h =>
                h.Equals("EmployeeName", StringComparison.OrdinalIgnoreCase) ||
                h.Equals("Tên NV", StringComparison.OrdinalIgnoreCase) ||
                h.Equals("TenNV", StringComparison.OrdinalIgnoreCase) ||
                h.Equals("HoTen", StringComparison.OrdinalIgnoreCase) ||
                h.Equals("Họ Tên", StringComparison.OrdinalIgnoreCase) ||
                h.Equals("Name", StringComparison.OrdinalIgnoreCase));

            if (codeColIndex < 0)
            {
                _logger.LogWarning("Column 'EmployeeCode/Mã NV' not found in sheet headers: {Headers}",
                    string.Join(", ", headers));
                // Fallback: dùng cột đầu tiên
                codeColIndex = 0;
            }

            // Đọc dữ liệu từ dòng 2 trở đi
            for (int rowIdx = 1; rowIdx < response.Values.Count; rowIdx++)
            {
                var row = response.Values[rowIdx];
                if (row.Count == 0) continue;

                var rawCode = codeColIndex < row.Count ? row[codeColIndex]?.ToString()?.Trim() ?? "" : "";
                // Google Sheets có thể format số lớn thành dạng khoa học (4.91E+10)
                // hoặc thêm .0 vào cuối. Cần normalize về string thuần.
                var employeeCode = NormalizeCode(rawCode);
                if (string.IsNullOrEmpty(employeeCode)) continue;

                var employeeName = nameColIndex >= 0 && nameColIndex < row.Count
                    ? row[nameColIndex]?.ToString()?.Trim() ?? ""
                    : "";

                var kpiValues = new Dictionary<string, decimal>();

                // Đọc tất cả các cột còn lại (trừ code & name) như giá trị KPI
                for (int colIdx = 0; colIdx < headers.Count; colIdx++)
                {
                    if (colIdx == codeColIndex || colIdx == nameColIndex) continue;
                    if (string.IsNullOrEmpty(headers[colIdx])) continue;

                    var cellValue = colIdx < row.Count ? row[colIdx]?.ToString()?.Trim() ?? "" : "";
                    if (TryParseNumber(cellValue, out var numValue))
                    {
                        kpiValues[headers[colIdx]] = numValue;
                    }
                }

                results.Add(new KpiSheetRow
                {
                    EmployeeCode = employeeCode,
                    EmployeeName = employeeName,
                    KpiValues = kpiValues,
                    RowIndex = rowIdx + 1 // 1-based for Google Sheets API
                });
            }

            _logger.LogInformation("Read {Count} KPI rows from sheet {Sheet}", results.Count, sheetName);
            return results;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to read KPI data from sheet {Sheet}", sheetName);
            throw;
        }
    }

    /// <inheritdoc />
    public async Task<decimal?> ReadCellValueAsync(string spreadsheetId, string range, string? credentialJson = null)
    {
        var service = await GetSheetsServiceAsync(credentialJson);
        var request = service.Spreadsheets.Values.Get(spreadsheetId, range);
        var response = await request.ExecuteAsync();
        if (response.Values != null && response.Values.Count > 0 && response.Values[0].Count > 0)
        {
            var cellValue = response.Values[0][0]?.ToString()?.Trim() ?? "";
            if (TryParseNumber(cellValue, out var numValue))
                return numValue;
        }
        return null;
    }

    /// <inheritdoc />
    public async Task<bool> WriteCellRangeAsync(string spreadsheetId, string range,
        IList<IList<object>> values, string? credentialJson = null)
    {
        try
        {
            var service = await GetSheetsServiceAsync(credentialJson);
            var body = new ValueRange { Values = values };
            var update = service.Spreadsheets.Values.Update(body, spreadsheetId, range);
            update.ValueInputOption = SpreadsheetsResource.ValuesResource.UpdateRequest.ValueInputOptionEnum.RAW;
            await update.ExecuteAsync();
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to write range {Range}", range);
            throw;
        }
    }

    public async Task<bool> CreateKpiTemplateAsync(string spreadsheetId, string sheetName,
        List<KpiTemplateEmployee> employees, string? credentialJson = null)
    {
        try
        {
            var service = await GetSheetsServiceAsync(credentialJson);

            // Kiểm tra sheet đã tồn tại chưa
            var existingSheets = await GetSheetNamesAsync(spreadsheetId, credentialJson);
            if (!existingSheets.Contains(sheetName))
            {
                var addSheetRequest = new Request
                {
                    AddSheet = new AddSheetRequest
                    {
                        Properties = new SheetProperties { Title = sheetName }
                    }
                };
                var batchRequest = new BatchUpdateSpreadsheetRequest
                {
                    Requests = new List<Request> { addSheetRequest }
                };
                await service.Spreadsheets.BatchUpdate(batchRequest, spreadsheetId).ExecuteAsync();
            }

            // Ghi header
            var headerValues = new List<IList<object>>
            {
                new List<object> { "Mã NV", "Tên NV", "Tổng KPI" }
            };
            var headerRange = $"{sheetName}!A1:C1";
            var headerBody = new ValueRange { Values = headerValues };
            var headerUpdate = service.Spreadsheets.Values.Update(headerBody, spreadsheetId, headerRange);
            headerUpdate.ValueInputOption = SpreadsheetsResource.ValuesResource.UpdateRequest.ValueInputOptionEnum.USERENTERED;
            await headerUpdate.ExecuteAsync();

            // Ghi dữ liệu nhân viên
            if (employees.Count > 0)
            {
                var dataValues = employees.Select(e => (IList<object>)new List<object>
                {
                    e.EmployeeCode,
                    e.EmployeeName,
                    "" // Tổng KPI - để trống cho người dùng nhập
                }).ToList();

                var dataRange = $"{sheetName}!A2:C{employees.Count + 1}";
                var dataBody = new ValueRange { Values = dataValues };
                var dataUpdate = service.Spreadsheets.Values.Update(dataBody, spreadsheetId, dataRange);
                dataUpdate.ValueInputOption = SpreadsheetsResource.ValuesResource.UpdateRequest.ValueInputOptionEnum.RAW;
                await dataUpdate.ExecuteAsync();
            }

            _logger.LogInformation("Created KPI template with {Count} employees in sheet {Sheet}", employees.Count, sheetName);
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to create KPI template in sheet {Sheet}", sheetName);
            throw;
        }
    }

    /// <inheritdoc />
    public async Task<bool> WriteKpiSalaryResultsAsync(string spreadsheetId, string sheetName,
        List<KpiSalarySheetRow> results, string? credentialJson = null)
    {
        try
        {
            var service = await GetSheetsServiceAsync(credentialJson);

            // Tạo sheet kết quả nếu chưa có
            var resultSheetName = $"{sheetName}_KetQua";
            var existingSheets = await GetSheetNamesAsync(spreadsheetId, credentialJson);
            
            if (!existingSheets.Contains(resultSheetName))
            {
                var addSheetRequest = new Request
                {
                    AddSheet = new AddSheetRequest
                    {
                        Properties = new SheetProperties { Title = resultSheetName }
                    }
                };
                var batchRequest = new BatchUpdateSpreadsheetRequest
                {
                    Requests = new List<Request> { addSheetRequest }
                };
                await service.Spreadsheets.BatchUpdate(batchRequest, spreadsheetId).ExecuteAsync();
            }

            // Ghi header
            var headerValues = new List<IList<object>>
            {
                new List<object>
                {
                    "Mã NV", "Tên NV", "Điểm KPI", "Tỷ lệ thưởng (%)",
                    "Lương cơ bản", "Thưởng KPI", "Tổng thu nhập", "Thực nhận"
                }
            };

            var headerRange = $"{resultSheetName}!A1:H1";
            var headerBody = new ValueRange { Values = headerValues };
            var headerUpdate = service.Spreadsheets.Values.Update(headerBody, spreadsheetId, headerRange);
            headerUpdate.ValueInputOption = SpreadsheetsResource.ValuesResource.UpdateRequest.ValueInputOptionEnum.USERENTERED;
            await headerUpdate.ExecuteAsync();

            // Ghi dữ liệu
            var dataValues = results.Select(r => (IList<object>)new List<object>
            {
                r.EmployeeCode,
                r.EmployeeName,
                r.TotalKpiScore,
                r.KpiBonusRate,
                r.BaseSalary,
                r.KpiBonusAmount,
                r.GrossIncome,
                r.NetIncome
            }).ToList();

            var dataRange = $"{resultSheetName}!A2:H{results.Count + 1}";
            var dataBody = new ValueRange { Values = dataValues };
            var dataUpdate = service.Spreadsheets.Values.Update(dataBody, spreadsheetId, dataRange);
            dataUpdate.ValueInputOption = SpreadsheetsResource.ValuesResource.UpdateRequest.ValueInputOptionEnum.USERENTERED;
            await dataUpdate.ExecuteAsync();

            _logger.LogInformation("Written {Count} salary results to sheet {Sheet}", results.Count, resultSheetName);
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to write KPI salary results to sheet {Sheet}", sheetName);
            return false;
        }
    }
}
