using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Kết quả KPI của nhân viên - lưu giá trị thực tế đã đạt được
/// Đọc từ Google Sheet hoặc nhập tay
/// </summary>
public class KpiResult : AuditableEntity<Guid>
{
    /// <summary>Nhân viên</summary>
    [Required]
    public Guid EmployeeId { get; set; }
    public virtual Employee Employee { get; set; } = null!;

    /// <summary>Cấu hình KPI</summary>
    [Required]
    public Guid KpiConfigId { get; set; }
    public virtual KpiConfig KpiConfig { get; set; } = null!;

    /// <summary>Kỳ đánh giá</summary>
    [Required]
    public Guid KpiPeriodId { get; set; }
    public virtual KpiPeriod KpiPeriod { get; set; } = null!;

    /// <summary>Giá trị thực tế đạt được</summary>
    [Required]
    public decimal ActualValue { get; set; }

    /// <summary>Giá trị mục tiêu (copy từ KpiConfig tại thời điểm đánh giá)</summary>
    [Required]
    public decimal TargetValue { get; set; }

    /// <summary>Tỷ lệ hoàn thành (%) = ActualValue / TargetValue * 100</summary>
    public decimal CompletionRate { get; set; }

    /// <summary>Điểm KPI đã tính = CompletionRate * Weight / 100</summary>
    public decimal WeightedScore { get; set; }

    /// <summary>Ghi chú / nhận xét</summary>
    [MaxLength(500)]
    public string? Notes { get; set; }

    /// <summary>Nguồn dữ liệu (Manual, GoogleSheet)</summary>
    [MaxLength(50)]
    public string Source { get; set; } = "Manual";

    /// <summary>Cửa hàng sở hữu</summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }
}
