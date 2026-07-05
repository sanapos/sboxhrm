using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Mã giảm giá / voucher POS.</summary>
public class PosVoucher : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    [MaxLength(50)]
    public string Code { get; set; } = string.Empty;

    [MaxLength(200)]
    public string? Name { get; set; }

    public PosVoucherDiscountType DiscountType { get; set; } = PosVoucherDiscountType.Fixed;

    public decimal DiscountValue { get; set; }

    public decimal MinOrderAmount { get; set; }

    public decimal? MaxDiscountAmount { get; set; }

    public DateTime? ValidFrom { get; set; }

    public DateTime? ValidTo { get; set; }

    public int? MaxUses { get; set; }

    public int UsedCount { get; set; }

    public Guid? CustomerId { get; set; }
    public virtual PosCustomer? Customer { get; set; }
}
