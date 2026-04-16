using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Cấu hình KPI - định nghĩa các tiêu chí đánh giá
/// Ví dụ: "Doanh thu tháng", "Đánh giá khách hàng", "Số lỗi sản xuất"
/// </summary>
public class KpiConfig : AuditableEntity<Guid>
{
    /// <summary>Mã KPI (ví dụ: KPI001)</summary>
    [Required, MaxLength(50)]
    public string Code { get; set; } = string.Empty;

    /// <summary>Tên KPI</summary>
    [Required, MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    /// <summary>Mô tả chi tiết</summary>
    [MaxLength(1000)]
    public string? Description { get; set; }

    /// <summary>Loại KPI (số lượng, phần trăm, tiền, điểm, boolean)</summary>
    [Required]
    public KpiType Type { get; set; } = KpiType.Quantity;

    /// <summary>Đơn vị tính (sản phẩm, %, VNĐ, điểm...)</summary>
    [MaxLength(50)]
    public string? Unit { get; set; }

    /// <summary>Trọng số (0-100%) - dùng để tính điểm KPI tổng</summary>
    [Required]
    public decimal Weight { get; set; }

    /// <summary>Giá trị mục tiêu (target)</summary>
    [Required]
    public decimal TargetValue { get; set; }

    /// <summary>Giá trị tối thiểu để đạt KPI</summary>
    public decimal? MinValue { get; set; }

    /// <summary>Giá trị tối đa (cap)</summary>
    public decimal? MaxValue { get; set; }

    /// <summary>Tần suất đánh giá</summary>
    [Required]
    public KpiFrequency Frequency { get; set; } = KpiFrequency.Monthly;

    /// <summary>Tên cột trong Google Sheet tương ứng (để mapping tự động)</summary>
    [MaxLength(100)]
    public string? GoogleSheetColumnName { get; set; }

    /// <summary>Thứ tự hiển thị</summary>
    public int SortOrder { get; set; }

    /// <summary>Cửa hàng sở hữu</summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }

    /// <summary>Danh sách kết quả KPI</summary>
    public virtual ICollection<KpiResult> KpiResults { get; set; } = new List<KpiResult>();
}
