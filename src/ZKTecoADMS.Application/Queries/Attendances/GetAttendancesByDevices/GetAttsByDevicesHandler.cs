using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Attendances;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Queries.Attendances.GetAttendancesByDevices;

public class GetAttsByDevicesHandler(
    IRepositoryPagedQuery<Attendance> attRepository,
    IRepository<Employee> employeeRepository,
    IRepository<MobileAttendanceRecord> mobileAttendanceRepository
) : ICommandHandler<GetAttsByDevicesQuery, AppResponse<PagedResult<AttendanceDto>>>
{
    public async Task<AppResponse<PagedResult<AttendanceDto>>> Handle(GetAttsByDevicesQuery request, CancellationToken cancellationToken)
    {
        var allowedPins = request.Filter.AllowedPins;
        var hasPinFilter = allowedPins != null && allowedPins.Count > 0;

        // FromDate inclusive (start of day), ToDate exclusive (start of next day after To calendar day).
        var fromInclusive = request.Filter.FromDate.Date;
        var toExclusive = request.Filter.ToDate.Date.AddDays(1);
        if (request.Filter.ToDate.TimeOfDay > TimeSpan.Zero
            && request.Filter.ToDate > request.Filter.ToDate.Date)
        {
            // Client gửi "đến giờ hiện tại" — vẫn bao trùm hết ngày ToDate.
            toExclusive = request.Filter.ToDate.Date.AddDays(1);
        }

        var deviceIds = request.Filter.DeviceIds;
        var hasDeviceFilter = deviceIds is { Count: > 0 };

        var pagination = request.PaginationRequest;
        if (pagination.PageSize >= 200)
        {
            pagination.SortBy = nameof(Attendance.AttendanceTime);
            pagination.SortOrder = "asc";
        }

        var atts = await attRepository.GetPagedResultWithProjectionAsync(
            pagination,
            filter: a => 
                a.AttendanceTime >= fromInclusive
                && a.AttendanceTime < toExclusive
                && (!hasDeviceFilter || deviceIds!.Contains(a.DeviceId))
                && (!hasPinFilter || allowedPins!.Contains(a.PIN)),
            projection: a => new AttendanceDto(
                a.Id,
                a.AttendanceTime,
                a.Device.DeviceName,
                a.PIN,
                // Mã NV: Lấy từ Employee nếu có, nếu không có (manual) thì để null
                a.EmployeeId.HasValue && a.Employee!.Employee != null ? a.Employee.Employee.EmployeeCode : null,
                // Tên nhân viên: Lấy từ Employee nếu có, nếu không (manual) thì lấy từ WorkCode
                a.EmployeeId.HasValue && a.Employee!.Employee != null 
                    ? a.Employee.Employee.LastName + " " + a.Employee.Employee.FirstName 
                    : (a.WorkCode ?? "Thủ công"),
                // Tên trong máy: Lấy từ DeviceUser nếu có
                a.EmployeeId.HasValue ? a.Employee!.Name : null,
                a.EmployeeId.HasValue ? a.Employee!.Privilege : 0,
                a.VerifyMode,
                a.AttendanceState,
                a.WorkCode,
                a.Note,
                a.MobileAttendanceRecordId,
                null,
                null,
                null
            ),
            cancellationToken: cancellationToken);
        
        // Enrich manual attendances with full employee names
        var dtoList = atts.Items.ToList();

        var mobileIds = dtoList
            .Where(d => d.MobileAttendanceRecordId.HasValue)
            .Select(d => d.MobileAttendanceRecordId!.Value)
            .Distinct()
            .ToList();
        if (mobileIds.Count > 0)
        {
            var mobileRecords = await mobileAttendanceRepository.GetAllAsync(
                r => mobileIds.Contains(r.Id),
                cancellationToken: cancellationToken);
            var mobileById = mobileRecords.ToDictionary(r => r.Id);
            for (var i = 0; i < dtoList.Count; i++)
            {
                var dto = dtoList[i];
                if (dto.MobileAttendanceRecordId.HasValue
                    && mobileById.TryGetValue(dto.MobileAttendanceRecordId.Value, out var mob))
                {
                    dtoList[i] = dto with
                    {
                        Latitude = mob.Latitude,
                        Longitude = mob.Longitude,
                        LocationName = mob.LocationName
                    };
                }
            }
        }
        var manualAttendances = dtoList.Where(a => (int)a.VerifyMode == 100).ToList();
        if (manualAttendances.Any())
        {
            var pins = manualAttendances.Select(a => a.Pin).Distinct().ToList();
            var employees = await employeeRepository.GetAllAsync(e => pins.Contains(e.EmployeeCode ?? ""));
            var employeeDict = employees.ToDictionary(e => e.EmployeeCode ?? "", e => $"{e.LastName} {e.FirstName}".Trim());
            
            for (int i = 0; i < dtoList.Count; i++)
            {
                var dto = dtoList[i];
                if ((int)dto.VerifyMode == 100 && dto.Pin != null && employeeDict.TryGetValue(dto.Pin, out var fullName))
                {
                    // Replace with full name
                    dtoList[i] = dto with { UserName = fullName, EmployeeCode = dto.Pin };
                }
            }
            
            atts = new PagedResult<AttendanceDto>(dtoList, atts);
        }
        
        return AppResponse<PagedResult<AttendanceDto>>.Success(atts);
    }
}