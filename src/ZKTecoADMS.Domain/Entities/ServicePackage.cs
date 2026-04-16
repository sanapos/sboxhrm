using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Gói dịch vụ - định nghĩa các chức năng được phép sử dụng
/// </summary>
public class ServicePackage : Entity<Guid>
{
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public bool IsActive { get; set; } = true;

    /// <summary>
    /// Số ngày mặc định khi kích hoạt gói (0 = không giới hạn)
    /// </summary>
    public int DefaultDurationDays { get; set; } = 30;

    public int MaxUsers { get; set; } = 10;
    public int MaxDevices { get; set; } = 2;

    /// <summary>
    /// Danh sách module được phép, lưu dạng JSON array: ["Employee","Attendance","Salary",...]
    /// </summary>
    public string AllowedModules { get; set; } = "[]";

    /// <summary>
    /// Stores đang sử dụng gói này
    /// </summary>
    public virtual ICollection<Store> Stores { get; set; } = [];
}
