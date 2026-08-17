using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Hàng mẫu toàn hệ thống (Super Admin) — từ điển mã vạch + menu món/đồ uống.
/// Cửa hàng adopt → tạo PosProduct, giữ ImageUrl dùng chung (không upload lại ảnh).
/// </summary>
public class PosProductSampleCatalog : AuditableEntity<Guid>
{
    /// <summary>Null với món ăn/uống không có EAN.</summary>
    [MaxLength(50)]
    public string? Barcode { get; set; }

    [Required]
    [MaxLength(500)]
    public string Name { get; set; } = string.Empty;

    [MaxLength(100)]
    public string? UnitName { get; set; }

    [MaxLength(200)]
    public string? BrandName { get; set; }

    [MaxLength(200)]
    public string? CategoryName { get; set; }

    /// <summary>Path tương đối wwwroot, vd. catalog/pos-samples/{id}.jpg — dùng chung mọi store.</summary>
    [MaxLength(1000)]
    public string? ImageUrl { get; set; }

    [MaxLength(2000)]
    public string? Description { get; set; }

    public PosProductSampleKind Kind { get; set; } = PosProductSampleKind.Packaged;

    /// <summary>Gợi ý loại hàng khi tạo nhanh (HH/DV/CB/NVL/TP).</summary>
    public PosProductType ProductType { get; set; } = PosProductType.Goods;

    /// <summary>Giá bán gợi ý — thu ngân vẫn sửa trước khi lưu.</summary>
    public decimal? DefaultPrice { get; set; }

    /// <summary>Giá vốn gợi ý.</summary>
    public decimal? DefaultCostPrice { get; set; }

    /// <summary>% VAT gợi ý (khi cửa hàng thuế theo mặt hàng).</summary>
    public decimal VatRate { get; set; } = 8;

    /// <summary>Không chịu thuế GTGT (KCT).</summary>
    public bool VatExempt { get; set; }

    public int SortOrder { get; set; }

    public bool IsActive { get; set; } = true;
}
