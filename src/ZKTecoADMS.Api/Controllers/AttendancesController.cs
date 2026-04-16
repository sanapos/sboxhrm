using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Queries.Attendances.GetAttendancesByDevices;
using ZKTecoADMS.Application.Queries.Attendances.GetMonthlyAttendanceSummary;
using ZKTecoADMS.Application.DTOs.Attendances;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Application.Constants;
using Microsoft.AspNetCore.Authorization;
using Microsoft.Extensions.Logging;

namespace ZKTecoADMS.API.Controllers;


[ApiController]
[Route("api/[controller]")]
[Authorize]
public class AttendancesController(
    IMediator bus,
    IRepository<Attendance> attendanceRepository,
    IRepository<Employee> employeeRepository,
    IRepository<DeviceUser> deviceUserRepository,
    IRepository<Device> deviceRepository,
    IDataScopeService dataScopeService,
    ILogger<AttendancesController> logger
    )
    : AuthenticatedControllerBase
{
    [HttpPost("devices")]
    public async Task<ActionResult<AppResponse<PagedResult<AttendanceDto>>>> GetAttendanceByDevice(
        [FromQuery] PaginationRequest paginationRequest, [FromBody] GetAttendancesByDeviceRequest filter)
    {
        logger.LogWarning($"[AttendancesController] GetAttendanceByDevice: DeviceIds={string.Join(",", filter.DeviceIds)}, From={filter.FromDate}, To={filter.ToDate}, PageNumber={paginationRequest.PageNumber}, PageSize={paginationRequest.PageSize}");
        
        // Validate DeviceIds belong to user's store (Admin can query any)
        if (!IsAdmin && filter.DeviceIds.Any())
        {
            var storeId = GetCurrentStoreId();
            logger.LogWarning($"[AttendancesController] User StoreId={storeId}, IsAdmin={IsAdmin}");
            var devices = await deviceRepository.GetAllAsync(d => filter.DeviceIds.Contains(d.Id));
            if (devices.Any(d => d.StoreId != storeId))
            {
                logger.LogWarning("[AttendancesController] BLOCKED: Device StoreId mismatch");
                return Ok(AppResponse<PagedResult<AttendanceDto>>.Error("Bạn không có quyền xem dữ liệu chấm công của thiết bị này"));
            }
        }

        // Employee: chỉ xem chấm công của chính mình
        // Manager: xem chấm công của NV thuộc phạm vi quản lý
        if (!IsAdmin)
        {
            var allowedPins = await GetAllowedPinsAsync();
            if (allowedPins != null)
            {
                filter.AllowedPins = allowedPins;
                logger.LogInformation("[AttendancesController] PIN filter applied: {Count} PINs for role {Role}", 
                    allowedPins.Count, CurrentUserRole);
            }
        }

        var command = new GetAttsByDevicesQuery(paginationRequest, filter);

        var result = await bus.Send(command);
        logger.LogWarning($"[AttendancesController] Result: IsSuccess={result.IsSuccess}, ItemCount={result.Data?.Items?.Count() ?? 0}");
        return Ok(result);
    }

    [HttpGet("devices/{deviceId}/users/{CurrentUserId}")]
    public async Task<ActionResult<IEnumerable<Attendance>>> GetAttendanceByUser(
        Guid deviceId,
        Guid CurrentUserId, 
        [FromQuery] DateTime? startDate, 
        [FromQuery] DateTime? endDate)
    {
        return Ok(null);
    }

    [HttpPost("monthly-summary")]
    public async Task<ActionResult<AppResponse<MonthlyAttendanceSummaryDto>>> GetMonthlyAttendanceSummary(
        [FromQuery] int year,
        [FromQuery] int month,
        [FromBody] GetMonthlyAttendanceSummaryRequest request)
    {
        // Employee: chỉ xem bảng tổng hợp của chính mình
        if (IsEmployee)
        {
            var employeeId = EmployeeId;
            if (!employeeId.HasValue)
            {
                return Ok(AppResponse<MonthlyAttendanceSummaryDto>.Error("Tài khoản chưa liên kết với nhân viên"));
            }
            // Override: chỉ cho xem data của chính mình
            request.EmployeeIds = [employeeId.Value];
        }
        
        // Validate EmployeeIds belong to user's store (Admin can query any)
        if (!IsAdmin && request.EmployeeIds.Any())
        {
            var storeId = GetCurrentStoreId();
            var employees = await employeeRepository.GetAllAsync(e => request.EmployeeIds.Contains(e.Id));
            if (employees.Any(e => e.StoreId != storeId))
            {
                return Ok(AppResponse<MonthlyAttendanceSummaryDto>.Error("Bạn không có quyền xem dữ liệu của nhân viên này"));
            }

            // Manager chỉ được xem NV thuộc phạm vi quản lý
            if (IsManager && !IsEmployee && storeId.HasValue)
            {
                var subordinateIds = await dataScopeService.GetSubordinateEmployeeIdsAsync(CurrentUserId, storeId.Value);
                var unauthorizedIds = request.EmployeeIds.Except(subordinateIds).ToList();
                if (unauthorizedIds.Any())
                {
                    return Ok(AppResponse<MonthlyAttendanceSummaryDto>.Error("Bạn không có quyền xem dữ liệu của nhân viên ngoài phạm vi quản lý"));
                }
            }
        }

        var query = new GetMonthlyAttendanceSummaryQuery(request.EmployeeIds, year, month);
        return Ok(await bus.Send(query));
    }

    /// <summary>
    /// Create a manual attendance record
    /// </summary>
    [HttpPost("manual")]
    public async Task<ActionResult<AppResponse<object>>> CreateManualAttendance(
        [FromBody] CreateManualAttendanceRequest request)
    {
        try
        {
            // Validate EmployeeId
            if (request.EmployeeId == Guid.Empty)
            {
                return Ok(AppResponse<object>.Fail("EmployeeId is required"));
            }
            
            // Validate DeviceId - it's required for FK constraint
            if (!request.DeviceId.HasValue || request.DeviceId == Guid.Empty)
            {
                return Ok(AppResponse<object>.Fail("DeviceId is required for manual attendance"));
            }
            
            var employeeId = request.EmployeeId;
            var deviceId = request.DeviceId.Value;
            
            // Validate device belongs to user's store
            if (!IsAdmin)
            {
                var device = await deviceRepository.GetByIdAsync(deviceId);
                if (device == null || device.StoreId != GetCurrentStoreId())
                {
                    return Ok(AppResponse<object>.Fail("Bạn không có quyền tạo chấm công cho thiết bị này"));
                }
            }

            // Get employee to get PIN
            var employee = await employeeRepository.GetByIdAsync(employeeId);
            if (employee == null)
            {
                return Ok(AppResponse<object>.Fail("Employee not found"));
            }

            // Look up DeviceUser on this device for proper UID (PIN from device)
            var deviceUser = await deviceUserRepository.GetSingleAsync(
                du => du.EmployeeId == employeeId && du.DeviceId == deviceId);
            // Fallback: try any DeviceUser for this employee
            deviceUser ??= await deviceUserRepository.GetSingleAsync(
                du => du.EmployeeId == employeeId);
            
            // Auto-calculate AttendanceState based on the order of attendances in the day
            // Odd = Check-in (0), Even = Check-out (1)
            var dateOnly = request.PunchTime.Date;
            
            // PIN: prefer DeviceUser.Pin (actual device UID), fallback to EmployeeCode
            var pin = deviceUser?.Pin ?? employee.EmployeeCode ?? employeeId.ToString().Substring(0, Math.Min(8, employeeId.ToString().Length));
            var dailyAttendances = await attendanceRepository
                .GetAllAsync(a => a.PIN == pin && 
                               a.AttendanceTime.Date == dateOnly);
            
            var sortedAttendances = dailyAttendances
                .OrderBy(a => a.AttendanceTime)
                .ToList();
            
            // Find the position of this new attendance in the timeline
            int position = sortedAttendances.Count(a => a.AttendanceTime < request.PunchTime) + 1;
            
            // Odd position = Check-in (0), Even position = Check-out (1)
            var attendanceState = (position % 2 == 1) ? AttendanceStates.CheckIn : AttendanceStates.CheckOut;

            // WorkCode: Store employee name for manual attendance display (max 10 chars as per DB constraint)
            // Full name stored for display purposes
            var employeeName = $"{employee.LastName} {employee.FirstName}".Trim();
            var workCode = employeeName.Length > 10 
                ? employeeName.Substring(0, 10) 
                : employeeName;

            var attendance = new Attendance
            {
                Id = Guid.NewGuid(),
                EmployeeId = deviceUser?.Id, // Link to DeviceUser for proper DeviceUserName display
                DeviceId = deviceId,
                PIN = pin,
                AttendanceTime = request.PunchTime,
                VerifyMode = VerifyModes.Manual, // Manual attendance = 100
                AttendanceState = attendanceState,
                WorkCode = workCode,
                Note = request.Note, // Full note
                CreatedAt = DateTime.UtcNow
            };

            await attendanceRepository.AddAsync(attendance);

            return Ok(AppResponse<object>.Success(new
            {
                Id = attendance.Id,
                EmployeeId = attendance.EmployeeId,
                DeviceId = attendance.DeviceId,
                AttendanceTime = attendance.AttendanceTime,
                VerifyMode = (int)attendance.VerifyMode,
                AttendanceState = (int)attendance.AttendanceState,
                WorkCode = attendance.WorkCode,
                EmployeeName = employeeName, // Return full name
                EmployeeCode = employee.EmployeeCode,
                Note = request.Note, // Return original note
                CreatedAt = attendance.CreatedAt
            }));
        }
        catch (Exception ex)
        {
            // Log detailed error
            var innerMessage = ex.InnerException?.Message ?? ex.Message;
            Console.WriteLine($"[CreateManualAttendance] Error: {ex.Message}");
            Console.WriteLine($"[CreateManualAttendance] Inner: {innerMessage}");
            Console.WriteLine($"[CreateManualAttendance] Stack: {ex.StackTrace}");
            return Ok(AppResponse<object>.Fail(innerMessage));
        }
    }

    /// <summary>
    /// Update an attendance record
    /// </summary>
    [HttpPut("{id}")]
    public async Task<ActionResult<AppResponse<bool>>> UpdateAttendance(
        Guid id, [FromBody] UpdateAttendanceRequest request)
    {
        try
        {
            var attendance = await attendanceRepository.GetByIdAsync(id);
            if (attendance == null)
            {
                return Ok(AppResponse<bool>.Fail("Không tìm thấy bản ghi chấm công"));
            }

            attendance.AttendanceTime = request.AttendanceTime;
            
            // Auto-calculate AttendanceState based on the order of attendances in the day
            // Odd = Check-in (0), Even = Check-out (1)
            var dateOnly = request.AttendanceTime.Date;
            var employeeId = attendance.EmployeeId;
            
            // Get all attendances for this employee on this date, sorted by time
            var dailyAttendances = await attendanceRepository
                .GetAllAsync(a => a.EmployeeId == employeeId && 
                               a.AttendanceTime.Date == dateOnly &&
                               a.Id != id);
            
            var sortedAttendances = dailyAttendances
                .OrderBy(a => a.AttendanceTime)
                .ToList();
            
            // Find the position of this attendance in the timeline
            int position = sortedAttendances.Count(a => a.AttendanceTime < request.AttendanceTime) + 1;
            
            // Odd position = Check-in (0), Even position = Check-out (1)
            attendance.AttendanceState = (position % 2 == 1) ? AttendanceStates.CheckIn : AttendanceStates.CheckOut;

            await attendanceRepository.UpdateAsync(attendance);

            return Ok(AppResponse<bool>.Success(true));
        }
        catch (Exception ex)
        {
            return Ok(AppResponse<bool>.Fail(ex.Message));
        }
    }

    /// <summary>
    /// Delete an attendance record
    /// </summary>
    [HttpDelete("{id}")]
    public async Task<ActionResult<AppResponse<bool>>> DeleteAttendance(Guid id)
    {
        try
        {
            var attendance = await attendanceRepository.GetByIdAsync(id);
            if (attendance == null)
            {
                return Ok(AppResponse<bool>.Fail("Không tìm thấy bản ghi chấm công"));
            }

            await attendanceRepository.DeleteAsync(attendance);

            return Ok(AppResponse<bool>.Success(true));
        }
        catch (Exception ex)
        {
            return Ok(AppResponse<bool>.Fail(ex.Message));
        }
    }

    /// <summary>
    /// Get PINs the current user is allowed to see.
    /// Employee: only their own PINs. Manager: subordinate employee PINs.
    /// Returns null for Admin (no filter needed).
    /// </summary>
    private async Task<List<string>?> GetAllowedPinsAsync()
    {
        if (IsAdmin) return null;

        var storeId = GetCurrentStoreId();
        
        // Employee role: chỉ xem PIN của chính mình
        if (IsEmployee)
        {
            var employeeId = EmployeeId;
            if (!employeeId.HasValue)
            {
                return []; // No employee linked → no data
            }
            var myDeviceUsers = await deviceUserRepository.GetAllAsync(du => du.EmployeeId == employeeId.Value);
            return myDeviceUsers.Select(du => du.Pin).Distinct().ToList();
        }

        // Manager role: xem PIN của NV thuộc phạm vi quản lý
        if (IsManager && storeId.HasValue)
        {
            var subordinateIds = await dataScopeService.GetSubordinateEmployeeIdsAsync(CurrentUserId, storeId.Value);
            if (subordinateIds.Count == 0) return [];
            
            var deviceUsers = await deviceUserRepository.GetAllAsync(
                du => du.EmployeeId.HasValue && subordinateIds.Contains(du.EmployeeId.Value));
            return deviceUsers.Select(du => du.Pin).Distinct().ToList();
        }

        return null; // Fallback: no filter
    }
}

public class CreateManualAttendanceRequest
{
    public Guid EmployeeId { get; set; }
    public Guid? DeviceId { get; set; }
    public DateTime PunchTime { get; set; }
    public int VerifyType { get; set; } = 100;
    public string? Note { get; set; }
    public bool IsManual { get; set; } = true;
}

public class UpdateAttendanceRequest
{
    public DateTime AttendanceTime { get; set; }
    // AttendanceState is auto-calculated based on order of attendances in the day
    // Odd position = Check-in (0), Even position = Check-out (1)
}

public class GetMonthlyAttendanceSummaryRequest
{
    public List<Guid> EmployeeIds { get; set; } = [];
}
