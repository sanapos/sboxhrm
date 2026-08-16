using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Từ điển mã vạch cửa hàng — tên hàng gợi ý khi quét mã chưa có trong hàng hóa.
/// Import Excel chỉ cần Mã vạch + Tên; giá bán nhập lúc quét.
/// </summary>
public class PosBarcodeCatalog : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    [MaxLength(50)]
    public string Barcode { get; set; } = string.Empty;

    [Required]
    [MaxLength(500)]
    public string Name { get; set; } = string.Empty;

    [MaxLength(100)]
    public string? UnitName { get; set; }

    [MaxLength(200)]
    public string? BrandName { get; set; }

    [MaxLength(200)]
    public string? CategoryName { get; set; }

    /// <summary>URL ảnh gợi ý (cột Excel «Hình ảnh»). Copy sang hàng hóa khi thêm nhanh.</summary>
    [MaxLength(1000)]
    public string? ImageUrl { get; set; }
}
