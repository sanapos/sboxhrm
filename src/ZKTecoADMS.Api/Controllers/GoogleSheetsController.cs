using Microsoft.AspNetCore.Mvc;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;
using Microsoft.AspNetCore.Authorization;

namespace ZKTecoADMS.API.Controllers;

/// <summary>
/// API Controller để quản lý Google Sheets Integration
/// </summary>
[ApiController]
[Route("api/[controller]")]
public class GoogleSheetsController(
    IGoogleSheetService googleSheetService,
    IRepository<Device> deviceRepository,
    IRepository<DeviceUser> employeeRepository,
    IRepository<Attendance> attendanceRepository,
    IRepository<AppSettings> appSettingsRepository)
    : AuthenticatedControllerBase
{
    /// <summary>
    /// Computes the attendance fetch window respecting day_end_time setting.
    /// If day_end_time = "05:00:00", logical day D = [D 05:00, D+1 05:00).
    /// </summary>
    private async Task<(DateTime start, DateTime end)> GetAttendanceWindowAsync(DateTime date, Guid storeId)
    {
        var setting = await appSettingsRepository.GetSingleAsync(
            s => s.StoreId == storeId && s.Key == "day_end_time");
        if (setting?.Value != null && TimeSpan.TryParse(setting.Value, out var cutoff) && cutoff > TimeSpan.Zero)
        {
            var start = date.Date.Add(cutoff);
            return (start, start.AddDays(1));
        }
        return (date.Date, date.Date.AddDays(1));
    }
    /// <summary>
    /// Kiểm tra kết nối Google Sheets
    /// </summary>
    [HttpGet("test-connection")]
    public async Task<ActionResult<AppResponse<bool>>> TestConnection()
    {
        var result = await googleSheetService.TestConnectionAsync();
        if (result)
        {
            return Ok(AppResponse<bool>.Success(true));
        }
        return Ok(AppResponse<bool>.Fail("Không thể kết nối Google Sheets"));
    }

    /// <summary>
    /// Khởi tạo Google Sheets với SpreadsheetId mới
    /// </summary>
    [HttpPost("initialize")]
    public async Task<ActionResult<AppResponse<bool>>> Initialize([FromBody] InitializeGoogleSheetRequest request)
    {
        var result = await googleSheetService.InitializeAsync(request.SpreadsheetId, request.CredentialsPath ?? string.Empty);
        if (result)
        {
            return Ok(AppResponse<bool>.Success(true));
        }
        return Ok(AppResponse<bool>.Fail("Không thể khởi tạo Google Sheets"));
    }

    /// <summary>
    /// Đồng bộ tất cả thiết bị lên Google Sheet
    /// </summary>
    [HttpPost("sync-devices")]
    public async Task<ActionResult<AppResponse<bool>>> SyncDevices()
    {
        var storeId = RequiredStoreId;
        var devices = await deviceRepository.GetAllAsync(d => d.StoreId == storeId);
        var result = await googleSheetService.SyncDevicesToSheetAsync(devices);
        
        if (result)
        {
            return Ok(AppResponse<bool>.Success(true));
        }
        return Ok(AppResponse<bool>.Fail("Không thể đồng bộ thiết bị"));
    }

    /// <summary>
    /// Đồng bộ tất cả nhân viên lên Google Sheet
    /// </summary>
    [HttpPost("sync-employees")]
    public async Task<ActionResult<AppResponse<bool>>> SyncEmployees()
    {
        var storeId = RequiredStoreId;
        var employees = await employeeRepository.GetAllAsync(e => e.Device.StoreId == storeId);
        var result = await googleSheetService.SyncEmployeesToSheetAsync(employees);
        
        if (result)
        {
            return Ok(AppResponse<bool>.Success(true));
        }
        return Ok(AppResponse<bool>.Fail("Không thể đồng bộ nhân viên"));
    }

    /// <summary>
    /// Đồng bộ dữ liệu chấm công theo ngày
    /// </summary>
    [HttpPost("sync-attendances")]
    public async Task<ActionResult<AppResponse<bool>>> SyncAttendances([FromBody] SyncAttendancesRequest request)
    {
        var storeId = RequiredStoreId;
        var (startDate, endDate) = await GetAttendanceWindowAsync(request.Date, storeId);
        
        var attendances = await attendanceRepository.GetAllAsync(
            a => a.AttendanceTime >= startDate && a.AttendanceTime < endDate
                && a.Device.StoreId == storeId);
        
        var result = await googleSheetService.PushDailyReportAsync(request.Date, attendances);
        
        if (result)
        {
            return Ok(AppResponse<bool>.Success(true));
        }
        return Ok(AppResponse<bool>.Fail("Không thể đồng bộ dữ liệu chấm công"));
    }

    /// <summary>
    /// Đồng bộ toàn bộ dữ liệu
    /// </summary>
    [HttpPost("sync-all")]
    public async Task<ActionResult<AppResponse<SyncAllResult>>> SyncAll()
    {
        var storeId = RequiredStoreId;
        var result = new SyncAllResult();

        // Sync devices
        var devices = await deviceRepository.GetAllAsync(d => d.StoreId == storeId);
        result.DevicesSynced = await googleSheetService.SyncDevicesToSheetAsync(devices);
        result.DevicesCount = devices.Count();

        // Sync employees
        var employees = await employeeRepository.GetAllAsync(e => e.Device.StoreId == storeId);
        result.EmployeesSynced = await googleSheetService.SyncEmployeesToSheetAsync(employees);
        result.EmployeesCount = employees.Count();

        // Sync today's attendances
        var today = DateTime.Today;
        var (attStart, attEnd) = await GetAttendanceWindowAsync(today, storeId);
        var attendances = await attendanceRepository.GetAllAsync(
            a => a.AttendanceTime >= attStart && a.AttendanceTime < attEnd
                && a.Device.StoreId == storeId);
        result.AttendancesSynced = await googleSheetService.PushDailyReportAsync(today, attendances);
        result.AttendancesCount = attendances.Count();

        if (result.DevicesSynced && result.EmployeesSynced && result.AttendancesSynced)
        {
            return Ok(AppResponse<SyncAllResult>.Success(result));
        }
        return Ok(AppResponse<SyncAllResult>.Fail("Một số dữ liệu không thể đồng bộ"));
    }
}

public record InitializeGoogleSheetRequest(string SpreadsheetId, string? CredentialsPath = null);
public record SyncAttendancesRequest(DateTime Date);

public class SyncAllResult
{
    public bool DevicesSynced { get; set; }
    public int DevicesCount { get; set; }
    public bool EmployeesSynced { get; set; }
    public int EmployeesCount { get; set; }
    public bool AttendancesSynced { get; set; }
    public int AttendancesCount { get; set; }
}
