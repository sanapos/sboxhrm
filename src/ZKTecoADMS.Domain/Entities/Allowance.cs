using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Phụ cấp - Allowance Configuration
/// </summary>
public class Allowance : AuditableEntity<Guid>
{
    [Required]
    [MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    [MaxLength(50)]
    public string? Code { get; set; }

    [MaxLength(500)]
    public string? Description { get; set; }

    /// <summary>
    /// Loại phụ cấp: Fixed (cố định) hoặc Daily (theo ngày công)
    /// </summary>
    [Required]
    public AllowanceType Type { get; set; } = AllowanceType.Fixed;

    /// <summary>
    /// Giá trị phụ cấp
    /// </summary>
    [Required]
    public decimal Amount { get; set; }

    /// <summary>
    /// Đơn vị tiền tệ
    /// </summary>
    [MaxLength(10)]
    public string Currency { get; set; } = "VND";

    /// <summary>
    /// Chịu thuế TNCN hay không
    /// </summary>
    public bool IsTaxable { get; set; } = true;

    /// <summary>
    /// Tính vào lương BHXH hay không
    /// </summary>
    public bool IsInsuranceApplicable { get; set; } = false;

    /// <summary>
    /// Thứ tự hiển thị
    /// </summary>
    public int DisplayOrder { get; set; } = 0;

    /// <summary>
    /// Ngày bắt đầu áp dụng
    /// </summary>
    public DateTime? StartDate { get; set; }

    /// <summary>
    /// Ngày kết thúc áp dụng
    /// </summary>
    public DateTime? EndDate { get; set; }

    /// <summary>
    /// Danh sách ID nhân viên được áp dụng (JSON array). null = tất cả
    /// </summary>
    public string? EmployeeIds { get; set; }
    
    /// <summary>
    /// Cửa hàng sở hữu phụ cấp này
    /// </summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }
}
