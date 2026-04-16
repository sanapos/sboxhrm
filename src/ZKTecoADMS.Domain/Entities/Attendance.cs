using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

public class Attendance : Entity<Guid>
{
    public Guid DeviceId { get; set; }

    public Guid? EmployeeId { get; set; }
    
    [Required]
    [MaxLength(20)]
    public string PIN { get; set; } = string.Empty;
    
    public VerifyModes VerifyMode { get; set; }
    
    public AttendanceStates AttendanceState { get; set; }

    public DateTime AttendanceTime { get; set; }
    
    [MaxLength(10)]
    public string? WorkCode { get; set; }
    
    [MaxLength(500)]
    public string? Note { get; set; } // Ghi chú đầy đủ

    /// <summary>
    /// Liên kết với bản ghi chấm công mobile (nếu có)
    /// </summary>
    public Guid? MobileAttendanceRecordId { get; set; }

    // Navigation Properties
    public virtual Device Device { get; set; } = null!;
    
    public virtual DeviceUser? Employee { get; set; }
}

