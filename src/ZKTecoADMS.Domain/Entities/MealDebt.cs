using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Công nợ suất ăn: ghi nhận tiền ăn và thanh toán của nhân viên
/// Type: 0=Charge (phát sinh), 1=Payment (thanh toán)
/// </summary>
public class MealDebt : AuditableEntity<Guid>
{
    [Required]
    public Guid EmployeeUserId { get; set; }
    public virtual ApplicationUser EmployeeUser { get; set; } = null!;

    [MaxLength(200)]
    public string EmployeeName { get; set; } = string.Empty;

    /// <summary>0 = Charge (phát sinh từ chấm cơm), 1 = Payment (thanh toán)</summary>
    public int Type { get; set; }

    public decimal Amount { get; set; }

    public DateTime Date { get; set; }

    public Guid? MealSessionId { get; set; }
    public virtual MealSession? MealSession { get; set; }

    /// <summary>Tháng tính công nợ (yyyy-MM)</summary>
    [MaxLength(10)]
    public string? Period { get; set; }

    [MaxLength(500)]
    public string? Note { get; set; }

    /// <summary>Người thu tiền / ghi nhận</summary>
    public Guid? RecordedByUserId { get; set; }

    [MaxLength(200)]
    public string? RecordedByName { get; set; }

    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }
}
