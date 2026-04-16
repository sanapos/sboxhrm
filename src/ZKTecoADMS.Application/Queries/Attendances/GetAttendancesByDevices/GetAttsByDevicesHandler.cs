using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Attendances;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Queries.Attendances.GetAttendancesByDevices;

public class GetAttsByDevicesHandler(
    IRepositoryPagedQuery<Attendance> attRepository,
    IRepository<Employee> employeeRepository
) : ICommandHandler<GetAttsByDevicesQuery, AppResponse<PagedResult<AttendanceDto>>>
{
    public async Task<AppResponse<PagedResult<AttendanceDto>>> Handle(GetAttsByDevicesQuery request, CancellationToken cancellationToken)
    {
        var allowedPins = request.Filter.AllowedPins;
        var hasPinFilter = allowedPins != null && allowedPins.Count > 0;
        
        var atts = await attRepository.GetPagedResultWithProjectionAsync(
            request.PaginationRequest,
            filter: a => 
                a.AttendanceTime.Date <= request.Filter.ToDate.Date
                && a.AttendanceTime.Date >= request.Filter.FromDate.Date
                && request.Filter.DeviceIds.Contains(a.DeviceId)
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
                a.Note
            ),
            cancellationToken: cancellationToken);
        
        // Enrich manual attendances with full employee names
        var dtoList = atts.Items.ToList();
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