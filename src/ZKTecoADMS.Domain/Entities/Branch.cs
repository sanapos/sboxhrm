using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Chi nhánh / Văn phòng / Cơ sở
/// </summary>
public class Branch : AuditableEntity<Guid>
{
    /// <summary>
    /// Mã chi nhánh (duy nhất trong Store)
    /// </summary>
    [Required]
    [MaxLength(20)]
    public string Code { get; set; } = string.Empty;

    /// <summary>
    /// Tên chi nhánh
    /// </summary>
    [Required]
    [MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    /// <summary>
    /// Mô tả
    /// </summary>
    [MaxLength(1000)]
    public string? Description { get; set; }

    /// <summary>
    /// Số điện thoại chi nhánh
    /// </summary>
    [MaxLength(20)]
    public string? Phone { get; set; }

    /// <summary>
    /// Email chi nhánh
    /// </summary>
    [MaxLength(200)]
    public string? Email { get; set; }

    /// <summary>
    /// Địa chỉ đầy đủ
    /// </summary>
    [MaxLength(500)]
    public string? Address { get; set; }

    /// <summary>
    /// Tỉnh / Thành phố
    /// </summary>
    [MaxLength(100)]
    public string? City { get; set; }

    /// <summary>
    /// Quận / Huyện
    /// </summary>
    [MaxLength(100)]
    public string? District { get; set; }

    /// <summary>
    /// Phường / Xã
    /// </summary>
    [MaxLength(100)]
    public string? Ward { get; set; }

    /// <summary>
    /// Vĩ độ (dùng cho bản đồ)
    /// </summary>
    public double? Latitude { get; set; }

    /// <summary>
    /// Kinh độ (dùng cho bản đồ)
    /// </summary>
    public double? Longitude { get; set; }

    /// <summary>
    /// Chi nhánh cha (null = chi nhánh gốc / trụ sở chính)
    /// </summary>
    public Guid? ParentBranchId { get; set; }
    public virtual Branch? ParentBranch { get; set; }

    /// <summary>
    /// Danh sách chi nhánh con
    /// </summary>
    public virtual ICollection<Branch> Children { get; set; } = new List<Branch>();

    /// <summary>
    /// ID quản lý chi nhánh (Employee)
    /// </summary>
    public Guid? ManagerId { get; set; }
    public virtual Employee? Manager { get; set; }

    /// <summary>
    /// Đây có phải trụ sở chính không
    /// </summary>
    public bool IsHeadquarter { get; set; }

    /// <summary>
    /// Thứ tự hiển thị
    /// </summary>
    public int SortOrder { get; set; }

    /// <summary>
    /// Mã thuế chi nhánh (nếu khác trụ sở chính)
    /// </summary>
    [MaxLength(50)]
    public string? TaxCode { get; set; }

    /// <summary>
    /// Giờ mở cửa / bắt đầu làm việc
    /// </summary>
    public TimeSpan? OpenTime { get; set; }

    /// <summary>
    /// Giờ đóng cửa / kết thúc làm việc
    /// </summary>
    public TimeSpan? CloseTime { get; set; }

    /// <summary>
    /// Số lượng nhân viên tối đa
    /// </summary>
    public int? MaxEmployees { get; set; }

    /// <summary>
    /// Cửa hàng mà chi nhánh thuộc về
    /// </summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }

    /// <summary>
    /// Danh sách nhân viên thuộc chi nhánh
    /// </summary>
    public virtual ICollection<Employee> Employees { get; set; } = new List<Employee>();
}
