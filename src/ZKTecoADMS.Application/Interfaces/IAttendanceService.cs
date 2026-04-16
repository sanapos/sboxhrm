using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Interfaces;

public interface IAttendanceService 
{
    Task<IEnumerable<Attendance>> GetAttendanceByEmployeeAsync(Guid deviceId, Guid employeeId, DateTime? startDate, DateTime? endDate);
    Task<bool> LogExistsAsync(Guid deviceId, string pin, DateTime attendanceTime);
    Task CreateAttendancesAsync(IEnumerable<Attendance> attendances);
    Task<bool> UpdateShiftAttendancesAsync(IEnumerable<Attendance> attendances, Device device);
}
