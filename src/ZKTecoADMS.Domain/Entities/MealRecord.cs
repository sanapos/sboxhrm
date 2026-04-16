using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Bản ghi chấm cơm - tạo khi nhân viên quẹt thẻ tại máy chấm cơm
/// </summary>
public class MealRecord : Entity<Guid>
{
    public Guid? AttendanceId { get; set; }
    public virtual Attendance? Attendance { get; set; }

    [Required]
    public Guid EmployeeUserId { get; set; }
    public virtual ApplicationUser EmployeeUser { get; set; } = null!;

    [MaxLength(20)]
    public string? PIN { get; set; }

    [Required]
    public Guid MealSessionId { get; set; }
    public virtual MealSession MealSession { get; set; } = null!;

    [Required]
    public DateTime MealTime { get; set; }

    [Required]
    public DateTime Date { get; set; }

    public Guid? ShiftId { get; set; }

    public Guid? DeviceId { get; set; }
    public virtual Device? Device { get; set; }

    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }
}
