namespace ZKTecoADMS.Application.DTOs.Shifts;

public class UpdateShiftTimesRequest
{
    public DateTime? CheckInTime { get; set; }
    public DateTime? CheckOutTime { get; set; }
}
