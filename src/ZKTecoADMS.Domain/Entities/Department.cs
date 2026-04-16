using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Phòng ban với cấu trúc phân cấp (Hierarchy)
/// </summary>
public class Department : AuditableEntity<Guid>
{
    /// <summary>
    /// Mã phòng ban
    /// </summary>
    [Required]
    [MaxLength(20)]
    public string Code { get; set; } = string.Empty;

    /// <summary>
    /// Tên phòng ban
    /// </summary>
    [Required]
    [MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    /// <summary>
    /// Mô tả phòng ban
    /// </summary>
    [MaxLength(500)]
    public string? Description { get; set; }

    /// <summary>
    /// ID phòng ban cha (null nếu là phòng ban gốc)
    /// </summary>
    public Guid? ParentDepartmentId { get; set; }

    /// <summary>
    /// Phòng ban cha
    /// </summary>
    public virtual Department? ParentDepartment { get; set; }

    /// <summary>
    /// Danh sách phòng ban con
    /// </summary>
    public virtual ICollection<Department> Children { get; set; } = new List<Department>();

    /// <summary>
    /// ID người quản lý phòng ban
    /// </summary>
    public Guid? ManagerId { get; set; }

    /// <summary>
    /// Người quản lý phòng ban
    /// </summary>
    public virtual Employee? Manager { get; set; }

    /// <summary>
    /// Cấp độ trong cây phân cấp (0 = gốc, 1 = cấp 1, ...)
    /// </summary>
    public int Level { get; set; }

    /// <summary>
    /// Thứ tự hiển thị trong cùng cấp
    /// </summary>
    public int SortOrder { get; set; }

    /// <summary>
    /// Cửa hàng/Chi nhánh mà phòng ban thuộc về
    /// </summary>
    public Guid? StoreId { get; set; }

    /// <summary>
    /// Cửa hàng/Chi nhánh
    /// </summary>
    public virtual Store? Store { get; set; }

    /// <summary>
    /// Danh sách nhân viên thuộc phòng ban
    /// </summary>
    public virtual ICollection<Employee> Employees { get; set; } = new List<Employee>();

    /// <summary>
    /// Đường dẫn phân cấp (ví dụ: "/root/parent/current/")
    /// Dùng để query nhanh các phòng ban con
    /// </summary>
    [MaxLength(500)]
    public string? HierarchyPath { get; set; }

    /// <summary>
    /// Số lượng nhân viên trực tiếp (cache để tối ưu)
    /// </summary>
    public int DirectEmployeeCount { get; set; }

    /// <summary>
    /// Tổng số nhân viên (bao gồm cả phòng ban con)
    /// </summary>
    public int TotalEmployeeCount { get; set; }

    /// <summary>
    /// Danh sách chức vụ trong phòng ban (JSON array)
    /// </summary>
    [MaxLength(2000)]
    public string? Positions { get; set; }
}
