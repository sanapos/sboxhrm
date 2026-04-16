namespace ZKTecoADMS.Application.Settings;

/// <summary>
/// Cấu hình Google Sheets
/// </summary>
public class GoogleSheetSettings
{
    public const string SectionName = "GoogleSheets";

    /// <summary>
    /// ID của Google Spreadsheet
    /// </summary>
    public string SpreadsheetId { get; set; } = string.Empty;

    /// <summary>
    /// Đường dẫn đến file credentials JSON
    /// </summary>
    public string CredentialsPath { get; set; } = "credentials.json";

    /// <summary>
    /// Tên sheet chứa dữ liệu chấm công
    /// </summary>
    public string AttendanceSheetName { get; set; } = "Attendance";

    /// <summary>
    /// Tên sheet chứa danh sách nhân viên
    /// </summary>
    public string EmployeesSheetName { get; set; } = "Employees";

    /// <summary>
    /// Tên sheet chứa danh sách thiết bị
    /// </summary>
    public string DevicesSheetName { get; set; } = "Devices";

    /// <summary>
    /// Tên sheet chứa báo cáo hàng ngày
    /// </summary>
    public string DailyReportSheetName { get; set; } = "DailyReport";

    /// <summary>
    /// Bật/tắt tính năng đẩy dữ liệu realtime
    /// </summary>
    public bool EnableRealtimeSync { get; set; } = true;

    /// <summary>
    /// Tên ứng dụng Google API
    /// </summary>
    public string ApplicationName { get; set; } = "ZKTeco ADMS Google Sheets Integration";
}
