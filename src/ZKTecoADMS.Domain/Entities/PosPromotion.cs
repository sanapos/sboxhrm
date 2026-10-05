using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Chương trình khuyến mãi tự áp ở màn bán (siêu thị / cửa hàng): giảm theo khung giờ, mua nhiều giảm,
/// mua X tặng Y, đồng giá combo, giảm theo tổng hóa đơn, mua kèm giá ưu đãi, hàng cận hạn.
/// Quy tắc chi tiết nằm trong <see cref="ConfigJson"/> (cùng lược đồ với engine Dart pos_promotion_engine.dart).
/// </summary>
public class PosPromotion : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required, MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    /// <summary>time_discount | qty_discount | buy_x_get_y | combo_price | bill_discount | addon_price | near_expiry</summary>
    [Required, MaxLength(30)]
    public string Type { get; set; } = "time_discount";

    /// <summary>Ưu tiên (số lớn hơn xét trước khi bằng tiền giảm).</summary>
    public int Priority { get; set; }

    /// <summary>Cho cộng dồn với khuyến mãi khác trên cùng dòng / hóa đơn.</summary>
    public bool Stackable { get; set; }

    /// <summary>Ngày áp dụng (giờ VN, chỉ phần ngày). Null = không giới hạn.</summary>
    public DateTime? ValidFrom { get; set; }
    public DateTime? ValidTo { get; set; }

    /// <summary>Bit thứ trong tuần: bit0 = Thứ 2 … bit6 = Chủ nhật. 0 = mọi ngày.</summary>
    public int DaysOfWeekMask { get; set; }

    /// <summary>Khung giờ trong ngày (phút từ 0h). Null = cả ngày. TimeTo &lt; TimeFrom = qua đêm.</summary>
    public int? TimeFromMinutes { get; set; }
    public int? TimeToMinutes { get; set; }

    /// <summary>Chỉ khách thành viên (đã chọn khách CRM).</summary>
    public bool MembersOnly { get; set; }

    public string ConfigJson { get; set; } = "{}";

    [MaxLength(500)]
    public string? Note { get; set; }
}
