namespace ZKTecoADMS.Application.DTOs.Payslips;

public class PayslipAttendanceSnapshotDto
{
    public Guid PayslipId { get; set; }
    public DateTime PeriodStart { get; set; }
    public DateTime PeriodEnd { get; set; }
    public DateTime CapturedAt { get; set; }
    /// <summary>Parsed snapshot payload (summary, dailyRecords, attendanceLogs).</summary>
    public object? Data { get; set; }
}
