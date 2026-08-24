using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Món trong menu QR bàn / đặt online — chọn từ catalog POS, giá có thể khác cửa hàng.</summary>
public class PosQrMenuItem : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    public Guid ProductId { get; set; }
    public virtual PosProduct? Product { get; set; }

    /// <summary>Hiển thị trên QR order tại bàn.</summary>
    public bool ShowOnTable { get; set; } = true;

    /// <summary>Hiển thị trên trang đặt online.</summary>
    public bool ShowOnOnline { get; set; } = true;

    /// <summary>Giá bán QR/online — null = dùng giá cửa hàng (BasePrice).</summary>
    public decimal? QrPrice { get; set; }

    /// <summary>Thứ tự trên menu khách (nhỏ hơn = trước).</summary>
    public int SortOrder { get; set; }
}
