using System;
using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Giao điểm bán cho nhân viên thị trường.
/// Liên kết nhân viên → MobileWorkLocation theo thứ/ngày cụ thể.
/// </summary>
public class FieldLocationAssignment : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    /// <summary>
    /// ApplicationUserId của nhân viên được giao
    /// </summary>
    [Required]
    [MaxLength(100)]
    public string EmployeeId { get; set; } = string.Empty;

    [MaxLength(200)]
    public string EmployeeName { get; set; } = string.Empty;

    /// <summary>
    /// Liên kết tới FieldLocation (điểm bán khách hàng)
    /// </summary>
    [Required]
    public Guid LocationId { get; set; }
    public virtual FieldLocation? Location { get; set; }

    /// <summary>
    /// Thứ trong tuần (1=Mon..7=Sun), null = áp dụng tất cả các ngày
    /// </summary>
    public int? DayOfWeek { get; set; }

    /// <summary>
    /// Thứ tự đi trong ngày (1, 2, 3...)
    /// </summary>
    public int SortOrder { get; set; } = 1;

    /// <summary>
    /// Ghi chú
    /// </summary>
    [MaxLength(500)]
    public string? Note { get; set; }
}
