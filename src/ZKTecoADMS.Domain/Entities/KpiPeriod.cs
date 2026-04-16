using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Kỳ đánh giá KPI (tháng/quý/năm)
/// Quản lý trạng thái: Mở → Khóa → Tính lương → Duyệt
/// </summary>
public class KpiPeriod : AuditableEntity<Guid>
{
    /// <summary>Tên kỳ (ví dụ: "Tháng 01/2026", "Q1/2026")</summary>
    [Required, MaxLength(100)]
    public string Name { get; set; } = string.Empty;

    /// <summary>Năm</summary>
    [Required]
    public int Year { get; set; }

    /// <summary>Tháng (1-12, null nếu quý/năm)</summary>
    public int? Month { get; set; }

    /// <summary>Quý (1-4, null nếu tháng/năm)</summary>
    public int? Quarter { get; set; }

    /// <summary>Ngày bắt đầu kỳ</summary>
    [Required]
    public DateTime PeriodStart { get; set; }

    /// <summary>Ngày kết thúc kỳ</summary>
    [Required]
    public DateTime PeriodEnd { get; set; }

    /// <summary>Tần suất</summary>
    [Required]
    public KpiFrequency Frequency { get; set; } = KpiFrequency.Monthly;

    /// <summary>Trạng thái kỳ</summary>
    [Required]
    public KpiPeriodStatus Status { get; set; } = KpiPeriodStatus.Open;

    /// <summary>ID Google Sheet (nếu liên kết)</summary>
    [MaxLength(200)]
    public string? GoogleSpreadsheetId { get; set; }

    /// <summary>Tên Sheet trong Google Spreadsheet</summary>
    [MaxLength(100)]
    public string? GoogleSheetName { get; set; }

    /// <summary>Lần đồng bộ Google Sheet gần nhất</summary>
    public DateTime? LastSyncedAt { get; set; }

    /// <summary>Bật/tắt tự động đồng bộ Google Sheet</summary>
    public bool AutoSyncEnabled { get; set; }

    /// <summary>Các mốc giờ tự động đồng bộ, JSON array VD: ["08:00","12:00","17:00"]</summary>
    [MaxLength(500)]
    public string? AutoSyncTimeSlots { get; set; }

    /// <summary>Ghi chú</summary>
    [MaxLength(1000)]
    public string? Notes { get; set; }

    /// <summary>Cửa hàng sở hữu</summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }

    /// <summary>Danh sách kết quả KPI trong kỳ</summary>
    public virtual ICollection<KpiResult> KpiResults { get; set; } = new List<KpiResult>();

    /// <summary>Danh sách bảng lương KPI trong kỳ</summary>
    public virtual ICollection<KpiSalary> KpiSalaries { get; set; } = new List<KpiSalary>();
}
