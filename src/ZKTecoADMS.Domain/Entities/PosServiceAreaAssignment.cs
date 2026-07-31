using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Gán khu vực phục vụ (tầng/khu bàn) cho tài khoản POS.
/// Không có dòng nào cho user → xem tất cả khu (tương thích dữ liệu cũ).
/// Có ≥1 dòng → chỉ thấy bàn thuộc các khu được gán.
/// Admin / Manager / Cashier luôn xem tất cả (bỏ qua bảng này).
/// </summary>
public class PosServiceAreaAssignment : Entity<Guid>
{
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    public Guid UserId { get; set; }
    public virtual ApplicationUser? User { get; set; }

    public Guid AreaId { get; set; }
    public virtual PosServiceArea? Area { get; set; }

    public bool CanView { get; set; } = true;
    public bool CanOperate { get; set; } = true;
    public bool IsActive { get; set; } = true;

    public string? GrantedBy { get; set; }
    public string? Note { get; set; }
}
