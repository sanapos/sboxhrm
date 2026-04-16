using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Thiết lập KPI theo nhân viên trong một kỳ tính KPI.
/// Lưu: tiêu chí đánh giá (Doanh thu / Point), mức được giao, 
/// các mốc thưởng khi đạt mốc, giá trị thực tế đạt được.
/// </summary>
public class KpiEmployeeTarget : AuditableEntity<Guid>
{
    /// <summary>Nhân viên được thiết lập KPI</summary>
    [Required]
    public Guid EmployeeId { get; set; }
    public virtual Employee Employee { get; set; } = null!;

    /// <summary>Kỳ đánh giá KPI</summary>
    [Required]
    public Guid KpiPeriodId { get; set; }
    public virtual KpiPeriod KpiPeriod { get; set; } = null!;

    /// <summary>Tiêu chí đánh giá: 0 = Doanh thu, 1 = Point</summary>
    public int CriteriaType { get; set; } = 0;

    /// <summary>Mức được giao (target – doanh thu hoặc point)</summary>
    [Required]
    public decimal TargetValue { get; set; }

    /// <summary>Thực tế đạt được (nhập thủ công sau kỳ)</summary>
    public decimal? ActualValue { get; set; }

    /// <summary>Tỷ lệ hoàn thành (%) = ActualValue / TargetValue * 100. Tự tính khi lưu.</summary>
    public decimal CompletionRate { get; set; }

    /// <summary>
    /// Các mốc thưởng dưới dạng JSON array.
    /// VD: [{"milestonePercent":80,"bonusAmount":500000},{"milestonePercent":100,"bonusAmount":1000000},{"milestonePercent":120,"bonusAmount":1500000}]
    /// </summary>
    [MaxLength(2000)]
    public string? BonusTiersJson { get; set; }

    /// <summary>
    /// Các mốc phạt/thưởng khi chưa đạt 100%.
    /// VD: [{"fromPct":0,"toPct":50,"rate":-30,"rateType":1},{"fromPct":50,"toPct":80,"rate":-10,"rateType":1},{"fromPct":80,"toPct":100,"rate":0,"rateType":1}]
    /// rate < 0 = phạt (trừ %), rate > 0 = thưởng thêm
    /// </summary>
    [MaxLength(2000)]
    public string? PenaltyTiersJson { get; set; }

    /// <summary>Ghi chú</summary>
    [MaxLength(500)]
    public string? Notes { get; set; }

    /// <summary>Lương cố định khi đạt đúng 100% chỉ tiêu (chưa kể phần vượt)</summary>
    public decimal CompletionSalary { get; set; }

    /// <summary>Cửa hàng sở hữu</summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }

    // ── Google Sheet config per employee ──

    /// <summary>URL hoặc SpreadsheetId của Google Sheet chứa doanh số</summary>
    [MaxLength(500)]
    public string? GoogleSheetUrl { get; set; }

    /// <summary>Tên tab (sheet) chứa doanh số</summary>
    [MaxLength(200)]
    public string? GoogleSheetName { get; set; }

    /// <summary>Vị trí ô chứa giá trị doanh số (VD: B5, C10)</summary>
    [MaxLength(20)]
    public string? GoogleCellPosition { get; set; }

    /// <summary>Bật/tắt tự động đồng bộ</summary>
    public bool AutoSyncEnabled { get; set; }

    /// <summary>Tần suất đồng bộ (phút)</summary>
    public int SyncIntervalMinutes { get; set; } = 60;
}
