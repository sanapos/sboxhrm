using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Bảng giá bán POS (KiotViet).</summary>
public class PosPriceList : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    [MaxLength(100)]
    public string Name { get; set; } = string.Empty;

    public bool IsDefault { get; set; }
    public bool IsActive { get; set; } = true;
    public int SortOrder { get; set; }

    /// <summary>Áp dụng mặc định khi bán từ ngày (null = không giới hạn đầu).</summary>
    public DateTime? ValidFrom { get; set; }

    /// <summary>Áp dụng mặc định khi bán đến ngày (null = không giới hạn cuối).</summary>
    public DateTime? ValidTo { get; set; }

    public virtual ICollection<PosPriceListItem> Items { get; set; } = [];
}

/// <summary>Giá bán theo bảng giá — theo hàng / biến thể / đơn vị.</summary>
public class PosPriceListItem : AuditableEntity<Guid>
{
    public PosPriceListItem()
    {
        // AuditableEntity.IsActive mặc định false — item bảng giá phải active khi tạo.
        IsActive = true;
    }

    [Required]
    public Guid StoreId { get; set; }

    [Required]
    public Guid PriceListId { get; set; }
    public virtual PosPriceList? PriceList { get; set; }

    [Required]
    public Guid ProductId { get; set; }
    public virtual PosProduct? Product { get; set; }

    public Guid? VariantId { get; set; }
    public virtual PosProductVariant? Variant { get; set; }

    public Guid? UnitId { get; set; }
    public virtual PosProductUnit? Unit { get; set; }

    public decimal Price { get; set; }
}
