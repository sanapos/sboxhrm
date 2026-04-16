using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Nhập sản lượng - ghi nhận số lượng sản phẩm nhân viên làm được mỗi ngày
/// </summary>
public class ProductionEntry : AuditableEntity<Guid>
{
    [Required]
    public Guid EmployeeId { get; set; }
    public virtual Employee Employee { get; set; } = null!;

    [Required]
    public Guid ProductItemId { get; set; }
    public virtual ProductItem ProductItem { get; set; } = null!;

    /// <summary>Ngày làm việc</summary>
    [Required]
    public DateTime WorkDate { get; set; }

    /// <summary>Số lượng sản phẩm</summary>
    [Required]
    public decimal Quantity { get; set; }

    /// <summary>Đơn giá tại thời điểm nhập (để lưu lịch sử)</summary>
    public decimal? UnitPrice { get; set; }

    /// <summary>Thành tiền = Quantity * UnitPrice</summary>
    public decimal? Amount { get; set; }

    [MaxLength(500)]
    public string? Note { get; set; }

    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }
}
