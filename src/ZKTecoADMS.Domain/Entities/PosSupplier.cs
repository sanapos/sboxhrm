using System.ComponentModel.DataAnnotations;

using ZKTecoADMS.Domain.Entities.Base;



namespace ZKTecoADMS.Domain.Entities;



/// <summary>Nhà cung cấp hàng hóa POS.</summary>

public class PosSupplier : AuditableEntity<Guid>

{

    [Required]

    public Guid StoreId { get; set; }

    public virtual Store? Store { get; set; }



    [Required]

    [MaxLength(30)]

    public string SupplierCode { get; set; } = string.Empty;



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



    public Guid? GroupId { get; set; }

    public virtual PosSupplierGroup? Group { get; set; }



    [MaxLength(200)]

    public string? CompanyName { get; set; }



    [MaxLength(50)]

    public string? TaxCode { get; set; }



    [MaxLength(50)]

    public string? IdentityNo { get; set; }



    [MaxLength(1000)]

    public string? Note { get; set; }



    /// <summary>Tổng giá trị đã mua (phiếu hoàn thành).</summary>

    public decimal TotalPurchase { get; set; }



    /// <summary>Nợ cần trả NCC hiện tại.</summary>

    public decimal CurrentDebt { get; set; }



    public virtual ICollection<PosProduct> Products { get; set; } = [];

    public virtual ICollection<PosStockReceipt> Receipts { get; set; } = [];

    public virtual ICollection<PosPurchaseReturn> Returns { get; set; } = [];

    public virtual ICollection<PosSupplierPayment> Payments { get; set; } = [];

}

