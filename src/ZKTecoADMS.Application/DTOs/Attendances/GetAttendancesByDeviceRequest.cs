namespace ZKTecoADMS.Application.DTOs.Attendances;

public class GetAttendancesByDeviceRequest
{
    public List<Guid> DeviceIds { get; set; } = new();
    
    public DateTime FromDate { get; set; }
    
    public DateTime ToDate { get; set; }
    
    /// <summary>
    /// Optional: filter by specific PINs (for employee/manager scoping)
    /// Null or empty = no PIN filter (admin sees all)
    /// </summary>
    public List<string>? AllowedPins { get; set; }
}