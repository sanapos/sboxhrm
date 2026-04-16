using ZKTecoADMS.Application.DTOs.Attendances;

namespace ZKTecoADMS.Application.Queries.Attendances.GetAttendancesByDevices;

public record GetAttsByDevicesQuery(PaginationRequest PaginationRequest, GetAttendancesByDeviceRequest Filter) : ICommand<AppResponse<PagedResult<AttendanceDto>>>;