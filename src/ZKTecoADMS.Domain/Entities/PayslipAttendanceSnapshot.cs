using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Bản chụp chấm công gắn với phiếu lương — lưu độc lập, không phụ thuộc bảng Attendance sau khi chốt.
/// </summary>
public class PayslipAttendanceSnapshot : Entity<Guid>
{
    [Required]
    public Guid PayslipId { get; set; }
    public virtual Payslip Payslip { get; set; } = null!;

    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }

    public DateTime PeriodStart { get; set; }
    public DateTime PeriodEnd { get; set; }

    /// <summary>JSON: summary + dailyRecords + attendanceLogs</summary>
    [Required]
    public string SnapshotJson { get; set; } = string.Empty;

    public DateTime CapturedAt { get; set; } = DateTime.UtcNow;
    public Guid? CapturedByUserId { get; set; }
}
