using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Interfaces;

/// <summary>
/// Service để đẩy dữ liệu chấm công lên Google Sheets
/// </summary>
public interface IGoogleSheetService
{
    /// <summary>
    /// Khởi tạo kết nối với Google Sheets
    /// </summary>
    Task<bool> InitializeAsync(string spreadsheetId, string credentialJson);

    /// <summary>
    /// Đẩy dữ liệu chấm công realtime lên Google Sheet
    /// </summary>
    Task<bool> PushAttendanceAsync(Attendance attendance, DeviceUser employee, Device device);

    /// <summary>
    /// Đẩy nhiều bản ghi chấm công lên Google Sheet
    /// </summary>
    Task<bool> PushAttendancesAsync(IEnumerable<Attendance> attendances, Device device);

    /// <summary>
    /// Đồng bộ danh sách nhân viên lên Google Sheet
    /// </summary>
    Task<bool> SyncEmployeesToSheetAsync(IEnumerable<DeviceUser> employees);

    /// <summary>
    /// Đồng bộ danh sách thiết bị lên Google Sheet
    /// </summary>
    Task<bool> SyncDevicesToSheetAsync(IEnumerable<Device> devices);

    /// <summary>
    /// Lấy báo cáo chấm công theo ngày
    /// </summary>
    Task<bool> PushDailyReportAsync(DateTime date, IEnumerable<Attendance> attendances);

    /// <summary>
    /// Kiểm tra kết nối Google Sheet
    /// </summary>
    Task<bool> TestConnectionAsync();
}
