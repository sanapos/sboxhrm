using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

public class PosQuoteLine : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    public Guid QuoteId { get; set; }
    public virtual PosQuote? Quote { get; set; }

    public Guid? ProductId { get; set; }
    public virtual PosProduct? Product { get; set; }

    [MaxLength(50)]
    public string? ProductCode { get; set; }

    [Required]
    [MaxLength(500)]
    public string ProductName { get; set; } = string.Empty;

    [MaxLength(100)]
    public string? UnitName { get; set; }

    public decimal Qty { get; set; } = 1;
    public decimal UnitPrice { get; set; }
    public decimal DiscountAmount { get; set; }
    public decimal VatRate { get; set; }
    public decimal LineTotal { get; set; }

    [MaxLength(500)]
    public string? LineNote { get; set; }

    /// <summary>Chiều dài khi bán theo diện tích. Đơn vị theo ĐVT dòng.</summary>
    public decimal? Length { get; set; }

    /// <summary>Chiều rộng khi bán theo diện tích.</summary>
    public decimal? Width { get; set; }

    /// <summary>Chiều cao khi bán theo diện tích.</summary>
    public decimal? Height { get; set; }

    /// <summary>Hàng gia công tính theo m²: đơn giá / m². Khi có, UnitPrice = giá mỗi bộ, Qty = số bộ.</summary>
    public decimal? PricePerM2 { get; set; }

    /// <summary>Diện tích một bộ (m²) — từ rộng × cao mm hoặc nhập tay.</summary>
    public decimal? AreaM2 { get; set; }

    /// <summary>Giá tối thiểu mỗi bộ áp lúc lập báo giá.</summary>
    public decimal? MinPricePerSet { get; set; }

    /// <summary>Số tháng bảo hành (sao chép từ hàng hóa khi lập BG).</summary>
    public int? WarrantyMonths { get; set; }

    public int SortOrder { get; set; }
}
