using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

public class PosCustomerPointTransaction : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    public Guid CustomerId { get; set; }
    public virtual PosCustomer? Customer { get; set; }

    public Guid? SaleOrderId { get; set; }
    public virtual PosSaleOrder? SaleOrder { get; set; }

    public PosCustomerPointType TransactionType { get; set; }

    public decimal Points { get; set; }

    public decimal BalanceAfter { get; set; }

    [MaxLength(500)]
    public string? Note { get; set; }
}
