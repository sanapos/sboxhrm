// ZKTecoADMS.Domain/Entities/Device.cs
using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

public class Device : AuditableEntity<Guid>
{
    /// <summary>
    /// Loại thiết bị: Attendance (chấm công) hoặc Meal (chấm cơm)
    /// </summary>
    public DeviceType DeviceType { get; set; } = DeviceType.Attendance;

    [Required]
    [MaxLength(50)]
    public string SerialNumber { get; set; } = string.Empty;

    [Required]
    [MaxLength(100)]
    public string DeviceName { get; set; } = string.Empty;

    [MaxLength(500)]
    public string? Description { get; set; }

    [MaxLength(50)]
    public string? IpAddress { get; set; }

    [MaxLength(200)]
    public string? Location { get; set; }

    public DateTime? LastOnline { get; set; }

    [MaxLength(20)]
    public string DeviceStatus { get; set; } = "Offline";

    /// <summary>
    /// Manager của thiết bị (người quản lý trực tiếp)
    /// </summary>
    public Guid ManagerId { get; set; }
    
    /// <summary>
    /// Owner của thiết bị - User đã claim thiết bị này
    /// Null nếu thiết bị chưa được claim
    /// </summary>
    public Guid? OwnerId { get; set; }
    
    /// <summary>
    /// Thiết bị đã được claim bởi một user chưa
    /// </summary>
    public bool IsClaimed { get; set; } = false;
    
    /// <summary>
    /// Thời điểm thiết bị được claim
    /// </summary>
    public DateTime? ClaimedAt { get; set; }
    
    public Guid DeviceInfoId { get; set; }
    
    /// <summary>
    /// Cửa hàng sở hữu thiết bị này
    /// Null nếu thiết bị chưa được gán cho cửa hàng nào
    /// </summary>
    public Guid? StoreId { get; set; }

    // Navigation Properties

    public virtual ApplicationUser Manager { get; set; } = null!;
    public virtual ApplicationUser? Owner { get; set; }
    public virtual DeviceInfo DeviceInfo { get; set; } = null!;
    public virtual Store? Store { get; set; }
    public virtual ICollection<DeviceUser> Employees { get; set; } = new List<DeviceUser>();
    public virtual ICollection<Attendance> AttendanceLogs { get; set; } = new List<Attendance>();
    public virtual ICollection<DeviceCommand> DeviceCommands { get; set; } = new List<DeviceCommand>();
    public virtual ICollection<SyncLog> SyncLogs { get; set; } = new List<SyncLog>();
    public virtual ICollection<DeviceSetting> DeviceSettings { get; set; } = new List<DeviceSetting>();
}