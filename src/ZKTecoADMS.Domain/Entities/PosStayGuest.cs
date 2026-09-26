using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Khách lưu trú của một lượt nhận phòng (khách sạn / nhà nghỉ) — dùng khai báo tạm trú
/// và sổ theo dõi khách. Thời gian ở lấy theo phiên phòng (<see cref="PosResourceSession"/>).
/// </summary>
public class PosStayGuest : AuditableEntity<Guid>
{
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    public Guid ResourceSessionId { get; set; }
    public virtual PosResourceSession? ResourceSession { get; set; }

    public string FullName { get; set; } = string.Empty;
    /// <summary>CCCD / Hộ chiếu / Khác.</summary>
    public string IdType { get; set; } = "CCCD";
    public string? IdNumber { get; set; }
    public DateTime? DateOfBirth { get; set; }
    /// <summary>Nam / Nữ / Khác.</summary>
    public string? Gender { get; set; }
    public string? Nationality { get; set; }
    public string? Address { get; set; }
    public string? Phone { get; set; }
    public string? Note { get; set; }
    /// <summary>Người đứng tên / đại diện nhận phòng.</summary>
    public bool IsPrimary { get; set; }
}
