using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Chi tiết dòng đơn bán hàng POS.</summary>
public class PosSaleOrderLine : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    public Guid SaleOrderId { get; set; }
    public virtual PosSaleOrder? SaleOrder { get; set; }

    [Required]
    public Guid ProductId { get; set; }
    public virtual PosProduct? Product { get; set; }

    /// <summary>Biến thể hàng cùng loại (nếu bán theo SKU).</summary>
    public Guid? VariantId { get; set; }
    public virtual PosProductVariant? Variant { get; set; }

    [Required]
    [MaxLength(500)]
    public string ProductName { get; set; } = string.Empty;

    [MaxLength(100)]
    public string? UnitName { get; set; }

    public decimal Qty { get; set; }
    public decimal UnitPrice { get; set; }
    /// <summary>Chiết khấu dòng (VNĐ).</summary>
    public decimal DiscountAmount { get; set; }
    public decimal LineTotal { get; set; }

    [MaxLength(500)]
    public string? LineNote { get; set; }

    /// <summary>Thời lượng khai báo / đã dùng (phút).</summary>
    public int? DurationMinutes { get; set; }

    /// <summary>Phút tính tiền sau làm tròn / tối thiểu.</summary>
    public int? BillableMinutes { get; set; }

    public DateTime? ServiceStartedAt { get; set; }
    public DateTime? ServiceEndedAt { get; set; }

    /// <summary>NV phụ trách dòng (stylist / PT).</summary>
    public Guid? AssignedEmployeeId { get; set; }

    /// <summary>Số lượng đã báo chế biến / gửi bếp.</summary>
    public decimal KitchenSentQty { get; set; }

    /// <summary>Lần gửi bếp gần nhất.</summary>
    public DateTime? KitchenSentAt { get; set; }

    /// <summary>JSON topping: [{id,name,price}].</summary>
    public string? ToppingsJson { get; set; }
}
