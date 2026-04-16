using System;
using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Hành trình di chuyển giữa các điểm bán trong ngày.
/// Theo dõi GPS liên tục, thời gian di chuyển, khoảng cách thực tế.
/// </summary>
public class JourneyTracking : AuditableEntity<Guid>
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
    /// Ngày hành trình
    /// </summary>
    [Required]
    public DateTime JourneyDate { get; set; }

    /// <summary>
    /// Thời gian bắt đầu hành trình (nhân viên bấm "Bắt đầu hành trình")
    /// </summary>
    public DateTime? StartTime { get; set; }

    /// <summary>
    /// Thời gian kết thúc hành trình (nhân viên bấm "Kết thúc")
    /// </summary>
    public DateTime? EndTime { get; set; }

    /// <summary>
    /// Trạng thái: not_started, in_progress, paused, completed, reviewed
    /// </summary>
    [Required]
    [MaxLength(30)]
    public string Status { get; set; } = "not_started";

    /// <summary>
    /// Tổng số km di chuyển (tính từ GPS tracking points)
    /// </summary>
    public double TotalDistanceKm { get; set; }

    /// <summary>
    /// Tổng thời gian di chuyển (phút) - không tính thời gian tại điểm
    /// </summary>
    public int TotalTravelMinutes { get; set; }

    /// <summary>
    /// Tổng thời gian tại điểm (phút) - tổng timeSpent tại các visit
    /// </summary>
    public int TotalOnSiteMinutes { get; set; }

    /// <summary>
    /// Số điểm đã check-in / tổng được giao hôm nay
    /// </summary>
    public int CheckedInCount { get; set; }
    public int AssignedCount { get; set; }

    /// <summary>
    /// Chuỗi tọa độ GPS theo thời gian (JSON array of {lat, lng, time, speed})
    /// Để vẽ polyline trên bản đồ
    /// </summary>
    public string? RoutePointsJson { get; set; }

    /// <summary>
    /// Ghi chú
    /// </summary>
    [MaxLength(1000)]
    public string? Note { get; set; }

    /// <summary>
    /// Người review (manager)
    /// </summary>
    [MaxLength(200)]
    public string? ReviewedBy { get; set; }
    public DateTime? ReviewedAt { get; set; }

    [MaxLength(500)]
    public string? ReviewNote { get; set; }
}
