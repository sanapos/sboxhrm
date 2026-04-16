using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Mức lương theo ca - mỗi ca có thể có nhiều mức lương khác nhau
/// Mỗi mức lương gán cho một nhóm nhân viên
/// </summary>
public class ShiftSalaryLevel : Entity<Guid>
{
    /// <summary>
    /// FK tới ShiftTemplate (ca làm việc)
    /// </summary>
    public Guid ShiftTemplateId { get; set; }

    /// <summary>
    /// Tên mức lương: "Mức 1 - Công nhân", "Mức 2 - Tổ trưởng"
    /// </summary>
    [Required]
    [MaxLength(200)]
    public string LevelName { get; set; } = string.Empty;

    /// <summary>
    /// Thứ tự sắp xếp
    /// </summary>
    public int SortOrder { get; set; }

    /// <summary>
    /// Cách tính: "fixed" = đơn giá cố định/ca, "hourly" = theo giờ, "multiplier" = hệ số lương cơ bản
    /// </summary>
    [MaxLength(20)]
    public string RateType { get; set; } = "fixed";

    /// <summary>
    /// Đơn giá cố định mỗi ca (VNĐ) - dùng khi RateType = "fixed"
    /// </summary>
    [Column(TypeName = "decimal(18,2)")]
    public decimal FixedRate { get; set; }

    /// <summary>
    /// Đơn giá theo giờ (VNĐ) - dùng khi RateType = "hourly"
    /// </summary>
    [Column(TypeName = "decimal(18,2)")]
    public decimal HourlyRate { get; set; }

    /// <summary>
    /// Hệ số nhân lương cơ bản - dùng khi RateType = "multiplier"
    /// VD: Ca đêm = 1.3
    /// </summary>
    [Column(TypeName = "decimal(5,2)")]
    public decimal Multiplier { get; set; } = 1.0m;

    /// <summary>
    /// Phụ cấp riêng cho ca (VNĐ/ca)
    /// </summary>
    [Column(TypeName = "decimal(18,2)")]
    public decimal ShiftAllowance { get; set; }

    /// <summary>
    /// Ca đêm (tự cộng thêm 30% lương giờ theo luật lao động)
    /// </summary>
    public bool IsNightShift { get; set; }

    /// <summary>
    /// Danh sách nhân viên áp dụng mức lương này (JSON array of Employee Ids)
    /// Null = mức mặc định, áp dụng cho tất cả NV trong ca
    /// </summary>
    public string? EmployeeIds { get; set; }

    /// <summary>
    /// Mô tả thêm
    /// </summary>
    [MaxLength(500)]
    public string? Description { get; set; }

    /// <summary>
    /// Trạng thái
    /// </summary>
    public bool IsActive { get; set; } = true;

    /// <summary>
    /// Cửa hàng
    /// </summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }

    /// <summary>
    /// Navigation property
    /// </summary>
    [ForeignKey(nameof(ShiftTemplateId))]
    public virtual ShiftTemplate? ShiftTemplate { get; set; }
}
