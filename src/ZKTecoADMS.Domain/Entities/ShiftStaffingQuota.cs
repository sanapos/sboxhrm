using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Định mức nhân sự cho mỗi ca làm việc theo phòng ban
/// </summary>
public class ShiftStaffingQuota : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }

    [Required]
    public Guid ShiftTemplateId { get; set; }

    /// <summary>
    /// Phòng ban (null = áp dụng cho tất cả)
    /// </summary>
    public string? Department { get; set; }

    /// <summary>
    /// Số nhân viên tối thiểu
    /// </summary>
    [Required]
    public int MinEmployees { get; set; } = 1;

    /// <summary>
    /// Số nhân viên tối đa
    /// </summary>
    [Required]
    public int MaxEmployees { get; set; } = 10;

    /// <summary>
    /// Ngưỡng cảnh báo thiếu nhân viên (nếu ≤ giá trị này = cảnh báo)
    /// </summary>
    public int WarningThreshold { get; set; } = 2;

    public virtual Store Store { get; set; } = null!;
    public virtual ShiftTemplate ShiftTemplate { get; set; } = null!;
}
