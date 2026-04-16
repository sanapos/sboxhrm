using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Bảng quy đổi điểm KPI → tỷ lệ thưởng
/// Ví dụ: 90-100 điểm → 150%, 80-89 → 120%, 70-79 → 100%, ...
/// </summary>
public class KpiBonusRule : AuditableEntity<Guid>
{
    /// <summary>Tên quy tắc</summary>
    [Required, MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    /// <summary>Điểm KPI tối thiểu</summary>
    [Required]
    public decimal MinScore { get; set; }

    /// <summary>Điểm KPI tối đa</summary>
    [Required]
    public decimal MaxScore { get; set; }

    /// <summary>Tỷ lệ thưởng (%) - ví dụ: 150 nghĩa là 150% lương</summary>
    [Required]
    public decimal BonusRate { get; set; }

    /// <summary>Mô tả</summary>
    [MaxLength(500)]
    public string? Description { get; set; }

    /// <summary>Thứ tự sắp xếp</summary>
    public int SortOrder { get; set; }

    /// <summary>Cửa hàng sở hữu</summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }
}
