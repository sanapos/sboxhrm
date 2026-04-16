using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Interfaces;

/// <summary>
/// Service đọc dữ liệu KPI từ Google Sheet
/// </summary>
public interface IKpiGoogleSheetService
{
    /// <summary>
    /// Đọc dữ liệu KPI từ Google Sheet cho một kỳ đánh giá
    /// </summary>
    /// <param name="spreadsheetId">ID Google Spreadsheet</param>
    /// <param name="sheetName">Tên sheet trong spreadsheet</param>
    /// <param name="credentialJson">Đường dẫn credential (optional)</param>
    /// <returns>Danh sách kết quả KPI đọc được</returns>
    Task<List<KpiSheetRow>> ReadKpiDataAsync(string spreadsheetId, string sheetName, string? credentialJson = null);

    /// <summary>
    /// Ghi kết quả tính lương KPI ngược lên Google Sheet
    /// </summary>
    Task<bool> WriteKpiSalaryResultsAsync(string spreadsheetId, string sheetName, List<KpiSalarySheetRow> results, string? credentialJson = null);

    /// <summary>
    /// Lấy danh sách các sheet có trong spreadsheet
    /// </summary>
    Task<List<string>> GetSheetNamesAsync(string spreadsheetId, string? credentialJson = null);

    /// <summary>
    /// Kiểm tra kết nối và đọc header của sheet
    /// </summary>
    Task<List<string>> GetSheetHeadersAsync(string spreadsheetId, string sheetName, string? credentialJson = null);

    /// <summary>
    /// Đọc giá trị của 1 ô cụ thể trong spreadsheet
    /// </summary>
    Task<decimal?> ReadCellValueAsync(string spreadsheetId, string range, string? credentialJson = null);

    /// <summary>
    /// Ghi giá trị vào một range trong spreadsheet
    /// </summary>
    Task<bool> WriteCellRangeAsync(string spreadsheetId, string range, IList<IList<object>> values, string? credentialJson = null);

    /// <summary>
    /// Tạo sheet mẫu KPI với danh sách nhân viên
    /// </summary>
    Task<bool> CreateKpiTemplateAsync(string spreadsheetId, string sheetName, List<KpiTemplateEmployee> employees, string? credentialJson = null);
}

/// <summary>
/// Dữ liệu nhân viên cho template KPI
/// </summary>
public class KpiTemplateEmployee
{
    public string EmployeeCode { get; set; } = string.Empty;
    public string EmployeeName { get; set; } = string.Empty;
}

/// <summary>
/// Dữ liệu một dòng KPI đọc từ Google Sheet
/// </summary>
public class KpiSheetRow
{
    /// <summary>Mã nhân viên (cột EmployeeCode)</summary>
    public string EmployeeCode { get; set; } = string.Empty;

    /// <summary>Tên nhân viên</summary>
    public string EmployeeName { get; set; } = string.Empty;

    /// <summary>Danh sách giá trị KPI theo tên cột</summary>
    public Dictionary<string, decimal> KpiValues { get; set; } = new();

    /// <summary>Số dòng trong sheet (để ghi ngược kết quả)</summary>
    public int RowIndex { get; set; }
}

/// <summary>
/// Dữ liệu kết quả lương KPI để ghi lên Google Sheet
/// </summary>
public class KpiSalarySheetRow
{
    public string EmployeeCode { get; set; } = string.Empty;
    public string EmployeeName { get; set; } = string.Empty;
    public decimal TotalKpiScore { get; set; }
    public decimal KpiBonusRate { get; set; }
    public decimal BaseSalary { get; set; }
    public decimal KpiBonusAmount { get; set; }
    public decimal GrossIncome { get; set; }
    public decimal NetIncome { get; set; }
    public int RowIndex { get; set; }
}
