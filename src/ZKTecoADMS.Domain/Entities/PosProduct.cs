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

    /// <summary>Thứ tự hiển thị trên menu bán hàng (nhỏ hơn = trước).</summary>
    public int SortOrder { get; set; }

    /// <summary>Máy in mặc định cho mặt hàng (phiếu bếp/chế biến/kho). Null = dùng máy in nhóm hàng.</summary>
    public Guid? DefaultPrinterId { get; set; }
    public virtual PosStorePrinter? DefaultPrinter { get; set; }

    /// <summary>Máy in tem mặc định (tem bếp/tem ly). Tách khỏi DefaultPrinterId để gán tem không đè gán phiếu bếp.</summary>
    public Guid? DefaultLabelPrinterId { get; set; }
    public virtual PosStorePrinter? DefaultLabelPrinter { get; set; }

    /// <summary>Thời hạn bảo hành (tháng) tính từ ngày bán. Null = không bảo hành.</summary>
    public int? WarrantyMonths { get; set; }

    /// <summary>Bắt buộc nhập seri máy khi bán.</summary>
    public bool RequiresSerial { get; set; }

    /// <summary>
    /// Cho phép số lượng thập phân khi bán / nhập / tồn kho (vd 0.5 kg).
    /// Tắt = chỉ số nguyên. Không dùng cùng RequiresSerial.
    /// </summary>
    public bool AllowDecimalQty { get; set; }

    /// <summary>Theo dõi lô / HSD khi nhập hàng.</summary>
    public bool TrackExpiry { get; set; }

    /// <summary>Số ngày cảnh báo trước HSD (mặc định 30).</summary>
    public int ExpiryWarningDays { get; set; } = 30;

    /// <summary>Cách tính tiền dịch vụ (chỉ áp dụng ProductType = Service).</summary>
    public PosServiceBillingMode ServiceBillingMode { get; set; } = PosServiceBillingMode.Flat;

    /// <summary>Phút tối thiểu khi tính giờ (vd 60).</summary>
    public int? MinBillMinutes { get; set; }

    /// <summary>Làm tròn phút (vd 15 → mỗi 15 phút). PerBlock = độ dài 1 block.</summary>
    public int? BillRoundMinutes { get; set; }

    /// <summary>Phút đầu miễn / không tính (vd 5–10 bi-a).</summary>
    public int? GraceMinutes { get; set; }

    /// <summary>
    /// Chỉ áp BillRoundMinutes khi thời lượng thực (trước grace) vượt ngưỡng này.
    /// Null/0 = luôn làm tròn khi có BillRoundMinutes.
    /// </summary>
    public int? RoundAfterMinutes { get; set; }

    /// <summary>Phí mở phòng/bàn — cộng ngay khi bắt đầu (karaoke, bi-a).</summary>
    public decimal OpeningFee { get; set; }

    /// <summary>Phút đã gồm trong phí mở. Phần vượt tính theo block/giờ.</summary>
    public int? OpeningMinutes { get; set; }

    /// <summary>Thời lượng mặc định khi thêm vào giỏ (phút).</summary>
    public int? DefaultDurationMinutes { get; set; }

    /// <summary>Số buổi trong gói khi bán (gym / liệu trình). 0 = không phải gói buổi.</summary>
    public int SessionPackCount { get; set; }

    /// <summary>Hạn sử dụng gói buổi (ngày) kể từ ngày bán. 0 = không hạn.</summary>
    public int SessionPackValidDays { get; set; }

    /// <summary>SP này là topping (trân châu, thạch…).</summary>
    public bool IsTopping { get; set; }

    /// <summary>Cho phép chọn topping khi bán.</summary>
    public bool AllowToppings { get; set; }

    /// <summary>Tự mở popup chọn topping ngay khi thêm món vào giỏ.</summary>
    public bool AutoOpenToppingPopup { get; set; } = true;

    /// <summary>Khi bán combo: hiện danh sách thành phần dưới tên (kiểu topping). Tắt = chỉ hiện tên combo.</summary>
    public bool ShowComboComponentsOnSell { get; set; }

    public virtual ICollection<PosProductUnit> Units { get; set; } = [];
    public virtual ICollection<PosProductAttributeValue> AttributeValues { get; set; } = [];
    public virtual ICollection<PosStockTransaction> StockTransactions { get; set; } = [];
    public virtual ICollection<PosProductComboLine> ComboLines { get; set; } = [];
    /// <summary>Định lượng NVL (hàng hóa / dịch vụ). Combo dùng ComboLines.</summary>
    public virtual ICollection<PosProductRecipeLine> RecipeLines { get; set; } = [];
    public virtual ICollection<PosProductVariant> Variants { get; set; } = [];
    /// <summary>Tùy chọn thêm gắn trực tiếp vào món (giống ghi chú nhanh nhưng có giá / SP).</summary>
    public virtual ICollection<PosProductToppingOption> ToppingOptions { get; set; } = [];
    /// <summary>Nhóm topping chung gán vào món.</summary>
    public virtual ICollection<PosProductToppingGroupLink> ToppingGroupLinks { get; set; } = [];
}

/// <summary>Tùy chọn thêm được phép gắn vào một món (vd trà sữa ← trân châu). Không phải nhóm topping chung.</summary>
public class PosProductToppingOption : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    public Guid ProductId { get; set; }
    public virtual PosProduct? Product { get; set; }

    [Required]
    public Guid ToppingProductId { get; set; }
    public virtual PosProduct? ToppingProduct { get; set; }

    /// <summary>Null = dùng giá bán của SP topping.</summary>
    public decimal? ExtraPrice { get; set; }

    public int SortOrder { get; set; }
}

/// <summary>Nhóm topping dùng chung (vd: Topping trà sữa).</summary>
public class PosToppingGroup : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    [MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    public int SortOrder { get; set; }

    public virtual ICollection<PosToppingGroupItem> Items { get; set; } = [];
    public virtual ICollection<PosProductToppingGroupLink> ProductLinks { get; set; } = [];
}

/// <summary>SP trong một nhóm topping (có giá phụ thu).</summary>
public class PosToppingGroupItem : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    public Guid GroupId { get; set; }
    public virtual PosToppingGroup? Group { get; set; }

    [Required]
    public Guid ToppingProductId { get; set; }
    public virtual PosProduct? ToppingProduct { get; set; }

    /// <summary>Null = dùng BasePrice của SP topping.</summary>
    public decimal? ExtraPrice { get; set; }

    public int SortOrder { get; set; }
}

/// <summary>Gán nhóm topping chung vào hàng hóa.</summary>
public class PosProductToppingGroupLink : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    public Guid ProductId { get; set; }
    public virtual PosProduct? Product { get; set; }

    [Required]
    public Guid GroupId { get; set; }
    public virtual PosToppingGroup? Group { get; set; }

    public int SortOrder { get; set; }
}
