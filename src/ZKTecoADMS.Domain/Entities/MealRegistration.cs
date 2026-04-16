using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Đăng ký suất ăn trước - nhân viên đăng ký ăn/không ăn mỗi ngày
/// </summary>
public class MealRegistration : Entity<Guid>
{
    [Required]
    public Guid EmployeeUserId { get; set; }
    public virtual ApplicationUser EmployeeUser { get; set; } = null!;

    [MaxLength(200)]
    public string EmployeeName { get; set; } = string.Empty;

    [Required]
    public Guid MealSessionId { get; set; }
    public virtual MealSession MealSession { get; set; } = null!;

    [Required]
    public DateTime Date { get; set; }

    /// <summary>
    /// true = đăng ký ăn, false = không ăn
    /// </summary>
    public bool IsRegistered { get; set; } = true;

    /// <summary>
    /// Thời gian đăng ký
    /// </summary>
    public DateTime RegisteredAt { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// Thời gian huỷ đăng ký (nếu có)
    /// </summary>
    public DateTime? CancelledAt { get; set; }

    [MaxLength(500)]
    public string? Note { get; set; }

    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }
}
