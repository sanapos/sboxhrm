using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Dòng hoa hồng đã chốt khi bán — 1 NV × 1 hàng (hoặc thành phần combo).</summary>
public class PosSaleCommissionLine : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    public Guid SaleOrderId { get; set; }
    public virtual PosSaleOrder? SaleOrder { get; set; }

    public Guid? SaleOrderLineId { get; set; }
    public virtual PosSaleOrderLine? SaleOrderLine { get; set; }

    [Required]
    public Guid ProductId { get; set; }
    public virtual PosProduct? Product { get; set; }

    [MaxLength(500)]
    public string ProductName { get; set; } = string.Empty;

    public Guid? ParentComboProductId { get; set; }

    [Required]
    public Guid EmployeeId { get; set; }

    [MaxLength(200)]
    public string EmployeeName { get; set; } = string.Empty;

    public decimal Qty { get; set; }
    public decimal RevenueAmount { get; set; }
    public PosCommissionMode CommissionMode { get; set; }
    public decimal CommissionPercent { get; set; }
    public decimal CommissionFixed { get; set; }
    public decimal CommissionAmount { get; set; }
}
