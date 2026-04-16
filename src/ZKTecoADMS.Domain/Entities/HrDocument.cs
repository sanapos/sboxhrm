using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Tài liệu nhân sự - HR Document
/// </summary>
public class HrDocument : AuditableEntity<Guid>
{
    /// <summary>
    /// ID nhân viên sở hữu tài liệu
    /// </summary>
    [Required]
    public Guid EmployeeUserId { get; set; }

    /// <summary>
    /// Tên tài liệu
    /// </summary>
    [Required]
    [MaxLength(255)]
    public string Name { get; set; } = string.Empty;

    /// <summary>
    /// Mô tả
    /// </summary>
    [MaxLength(1000)]
    public string? Description { get; set; }

    /// <summary>
    /// Loại tài liệu (Contract, Certificate, IDCard, Other...)
    /// </summary>
    [Required]
    public HrDocumentType DocumentType { get; set; }

    /// <summary>
    /// Đường dẫn file gốc
    /// </summary>
    [Required]
    [MaxLength(500)]
    public string FilePath { get; set; } = string.Empty;

    /// <summary>
    /// Tên file gốc
    /// </summary>
    [Required]
    [MaxLength(255)]
    public string FileName { get; set; } = string.Empty;

    /// <summary>
    /// Loại nội dung (MIME type)
    /// </summary>
    [MaxLength(100)]
    public string? ContentType { get; set; }

    /// <summary>
    /// Kích thước file (bytes)
    /// </summary>
    public long FileSize { get; set; }

    /// <summary>
    /// Ngày hiệu lực (đối với hợp đồng, chứng chỉ...)
    /// </summary>
    public DateTime? EffectiveDate { get; set; }

    /// <summary>
    /// Ngày hết hạn (đối với chứng chỉ, giấy phép...)
    /// </summary>
    public DateTime? ExpiryDate { get; set; }

    /// <summary>
    /// Số hiệu tài liệu (số hợp đồng, số chứng chỉ...)
    /// </summary>
    [MaxLength(100)]
    public string? DocumentNumber { get; set; }

    /// <summary>
    /// Cơ quan cấp (đối với chứng chỉ, giấy phép...)
    /// </summary>
    [MaxLength(255)]
    public string? IssuedBy { get; set; }

    /// <summary>
    /// Ghi chú
    /// </summary>
    [MaxLength(1000)]
    public string? Notes { get; set; }

    /// <summary>
    /// Người tải lên
    /// </summary>
    public Guid? UploadedByUserId { get; set; }

    /// <summary>
    /// Cửa hàng
    /// </summary>
    public Guid? StoreId { get; set; }

    // Navigation Properties
    public virtual ApplicationUser? EmployeeUser { get; set; }
    public virtual ApplicationUser? UploadedByUser { get; set; }
    public virtual Store? Store { get; set; }
}
