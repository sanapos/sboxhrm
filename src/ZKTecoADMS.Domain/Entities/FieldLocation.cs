using System;
using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Điểm bán / cửa hàng khách hàng do nhân viên thị trường đăng ký.
/// Khác với MobileWorkLocation (chi nhánh công ty dùng cho chấm công).
/// </summary>
public class FieldLocation : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    /// <summary>
    /// Tên cửa hàng / điểm bán
    /// </summary>
    [Required]
    [MaxLength(300)]
    public string Name { get; set; } = string.Empty;

    /// <summary>
    /// Địa chỉ
    /// </summary>
    [MaxLength(500)]
    public string? Address { get; set; }

    /// <summary>
    /// Tên người liên hệ
    /// </summary>
    [MaxLength(200)]
    public string? ContactName { get; set; }

    /// <summary>
    /// Số điện thoại liên hệ
    /// </summary>
    [MaxLength(50)]
    public string? ContactPhone { get; set; }

    /// <summary>
    /// Email liên hệ
    /// </summary>
    [MaxLength(200)]
    public string? ContactEmail { get; set; }

    /// <summary>
    /// Ghi chú về cửa hàng
    /// </summary>
    [MaxLength(1000)]
    public string? Note { get; set; }

    /// <summary>
    /// Vĩ độ (GPS lúc đăng ký)
    /// </summary>
    public double Latitude { get; set; }

    /// <summary>
    /// Kinh độ (GPS lúc đăng ký)
    /// </summary>
    public double Longitude { get; set; }

    /// <summary>
    /// Bán kính check-in (mét), mặc định 200m
    /// </summary>
    public int Radius { get; set; } = 200;

    /// <summary>
    /// Ảnh cửa hàng (JSON array of URLs)
    /// </summary>
    public string? PhotoUrlsJson { get; set; }

    /// <summary>
    /// Nhân viên đã đăng ký điểm này
    /// </summary>
    [MaxLength(100)]
    public string? RegisteredByEmployeeId { get; set; }

    [MaxLength(200)]
    public string? RegisteredByEmployeeName { get; set; }

    /// <summary>
    /// Loại điểm: shop, restaurant, market, pharmacy, ...
    /// </summary>
    [MaxLength(50)]
    public string? Category { get; set; }

    /// <summary>
    /// Đã duyệt bởi Manager chưa
    /// </summary>
    public bool IsApproved { get; set; } = true;
}
