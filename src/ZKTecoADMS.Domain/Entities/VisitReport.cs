using System;
using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Báo cáo check-in tại điểm bán.
/// Ghi nhận thời gian đến, đi, ảnh chụp, ghi chú báo cáo.
/// </summary>
public class VisitReport : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

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

    [MaxLength(200)]
    public string? LocationName { get; set; }

    /// <summary>
    /// Ngày viếng thăm
    /// </summary>
    [Required]
    public DateTime VisitDate { get; set; }

    /// <summary>
    /// Thời gian check-in (đến điểm)
    /// </summary>
    public DateTime? CheckInTime { get; set; }

    /// <summary>
    /// Thời gian check-out (rời điểm)
    /// </summary>
    public DateTime? CheckOutTime { get; set; }

    /// <summary>
    /// Thời gian tại điểm (phút), tính tự động khi check-out
    /// </summary>
    public int? TimeSpentMinutes { get; set; }

    /// <summary>
    /// Vĩ độ khi check-in
    /// </summary>
    public double? CheckInLatitude { get; set; }
    public double? CheckInLongitude { get; set; }

    /// <summary>
    /// Khoảng cách so với điểm bán khi check-in (mét)
    /// </summary>
    public double? CheckInDistance { get; set; }

    /// <summary>
    /// Vĩ độ khi check-out
    /// </summary>
    public double? CheckOutLatitude { get; set; }
    public double? CheckOutLongitude { get; set; }

    /// <summary>
    /// Khoảng cách so với điểm bán khi check-out (mét)
    /// </summary>
    public double? CheckOutDistance { get; set; }

    /// <summary>
    /// Ảnh chụp tại điểm (JSON array URLs)
    /// </summary>
    public string? PhotoUrlsJson { get; set; }

    /// <summary>
    /// Ghi chú / báo cáo tại điểm
    /// </summary>
    [MaxLength(2000)]
    public string? ReportNote { get; set; }

    /// <summary>
    /// Dữ liệu báo cáo tuỳ chỉnh (JSON - doanh thu, sản phẩm, etc.)
    /// </summary>
    public string? ReportDataJson { get; set; }

    /// <summary>
    /// Liên kết tới JourneyTracking (hành trình trong ngày)
    /// </summary>
    public Guid? JourneyId { get; set; }

    /// <summary>
    /// True nếu check-in ngoài bán kính cho phép
    /// </summary>
    public bool OutsideRadius { get; set; }

    /// <summary>
    /// Trạng thái: draft, checked_in, checked_out, submitted, reviewed
    /// </summary>
    [Required]
    [MaxLength(50)]
    public string Status { get; set; } = "draft";

    /// <summary>
    /// Người review (manager)
    /// </summary>
    [MaxLength(200)]
    public string? ReviewedBy { get; set; }
    public DateTime? ReviewedAt { get; set; }

    [MaxLength(500)]
    public string? ReviewNote { get; set; }
}
