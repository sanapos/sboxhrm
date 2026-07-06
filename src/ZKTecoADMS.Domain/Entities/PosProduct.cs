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

    /// <summary>% VAT bán hàng (áp dụng khi cửa hàng chọn thuế theo từng mặt hàng).</summary>
    public decimal VatRate { get; set; } = 8;

    /// <summary>Không chịu thuế GTGT (KCT).</summary>
    public bool VatExempt { get; set; }

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

    /// <summary>Máy in mặc định cho mặt hàng (phiếu bếp/chế biến). Null = dùng máy in nhóm hàng.</summary>
    public Guid? DefaultPrinterId { get; set; }
    public virtual PosStorePrinter? DefaultPrinter { get; set; }

    /// <summary>Thời hạn bảo hành (tháng) tính từ ngày bán. Null = không bảo hành.</summary>
    public int? WarrantyMonths { get; set; }

    /// <summary>Bắt buộc nhập seri máy khi bán.</summary>
    public bool RequiresSerial { get; set; }

    /// <summary>Theo dõi lô / HSD khi nhập hàng.</summary>
    public bool TrackExpiry { get; set; }

    /// <summary>Số ngày cảnh báo trước HSD (mặc định 30).</summary>
    public int ExpiryWarningDays { get; set; } = 30;

    public virtual ICollection<PosProductUnit> Units { get; set; } = [];
    public virtual ICollection<PosProductAttributeValue> AttributeValues { get; set; } = [];
    public virtual ICollection<PosStockTransaction> StockTransactions { get; set; } = [];
    public virtual ICollection<PosProductComboLine> ComboLines { get; set; } = [];
    public virtual ICollection<PosProductVariant> Variants { get; set; } = [];
}
