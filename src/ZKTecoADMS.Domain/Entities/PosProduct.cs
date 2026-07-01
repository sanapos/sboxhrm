using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Hàng hóa / dịch vụ bán POS (khác ProductItem lương sản phẩm).</summary>
public class PosProduct : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    [MaxLength(50)]
    public string ProductCode { get; set; } = string.Empty;

    [MaxLength(50)]
    public string? Barcode { get; set; }

    [Required]
    [MaxLength(500)]
    public string Name { get; set; } = string.Empty;

    public Guid? CategoryId { get; set; }
    public virtual PosProductCategory? Category { get; set; }

    public Guid? BrandId { get; set; }
    public virtual PosProductBrand? Brand { get; set; }

    public Guid? StorageLocationId { get; set; }
    public virtual PosStorageLocation? StorageLocation { get; set; }

    public Guid? SupplierId { get; set; }
    public virtual PosSupplier? Supplier { get; set; }

    public PosProductType ProductType { get; set; } = PosProductType.Goods;

    [MaxLength(2000)]
    public string? Description { get; set; }

    [MaxLength(500)]
    public string? ImageUrl { get; set; }

    public decimal CostPrice { get; set; }
    public decimal BasePrice { get; set; }

    public decimal OnHandQty { get; set; }
    public decimal ReservedQty { get; set; }
    public decimal MinStockQty { get; set; }
    public decimal MaxStockQty { get; set; }

    public decimal? Weight { get; set; }

    [MaxLength(20)]
    public string WeightUnit { get; set; } = "g";

    [MaxLength(100)]
    public string BaseUnitName { get; set; } = "Cái";

    /// <summary>Hiển thị trên màn hình bán hàng POS.</summary>
    public bool IsDirectSale { get; set; } = true;

    /// <summary>Ghi chú nhanh khi bán — JSON array chuỗi.</summary>
    [MaxLength(4000)]
    public string? SaleQuickNotesJson { get; set; }

    public bool IsFavorite { get; set; }

    public virtual ICollection<PosProductUnit> Units { get; set; } = [];
    public virtual ICollection<PosProductAttributeValue> AttributeValues { get; set; } = [];
    public virtual ICollection<PosStockTransaction> StockTransactions { get; set; } = [];
    public virtual ICollection<PosProductComboLine> ComboLines { get; set; } = [];
    public virtual ICollection<PosProductVariant> Variants { get; set; } = [];
}
