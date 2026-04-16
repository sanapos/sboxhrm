using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Interfaces;

/// <summary>
/// Service interface for sending real-time attendance notifications
/// </summary>
public interface IAttendanceNotificationService
{
    /// <summary>
    /// Broadcast new attendance to all connected clients
    /// </summary>
    Task NotifyNewAttendanceAsync(Attendance attendance, Device device, DeviceUser? user, string? employeeNameOverride = null);
    
    /// <summary>
    /// Broadcast multiple new attendances to all connected clients
    /// </summary>
    Task NotifyNewAttendancesAsync(IEnumerable<Attendance> attendances, Device device);
}
