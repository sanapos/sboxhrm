using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Khách hàng POS (CRM).</summary>
public class PosCustomer : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    [MaxLength(30)]
    public string CustomerCode { get; set; } = string.Empty;

    [Required]
    [MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    [MaxLength(50)]
    public string? Phone { get; set; }

    [MaxLength(200)]
    public string? Email { get; set; }

    [MaxLength(500)]
    public string? Address { get; set; }

    [MaxLength(100)]
    public string? Province { get; set; }

    [MaxLength(100)]
    public string? Ward { get; set; }

    [MaxLength(200)]
    public string? CompanyName { get; set; }

    [MaxLength(50)]
    public string? TaxCode { get; set; }

    public DateTime? Birthday { get; set; }

    [MaxLength(500)]
    public string? DeliveryAddress { get; set; }

    [MaxLength(1000)]
    public string? Note { get; set; }

    /// <summary>Tổng giá trị đã mua (đơn hoàn thành).</summary>
    public decimal TotalPurchase { get; set; }

    /// <summary>Công nợ khách hàng hiện tại.</summary>
    public decimal CurrentDebt { get; set; }

    /// <summary>Điểm tích lũy hiện tại.</summary>
    public decimal PointBalance { get; set; }

    public virtual ICollection<PosSaleOrder> SaleOrders { get; set; } = [];
    public virtual ICollection<PosCustomerPayment> Payments { get; set; } = [];
    public virtual ICollection<PosCustomerPointTransaction> PointTransactions { get; set; } = [];
}
