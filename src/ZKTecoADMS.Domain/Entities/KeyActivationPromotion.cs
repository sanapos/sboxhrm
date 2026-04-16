using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Chương trình khuyến mãi kích hoạt key — tặng thêm ngày khi kích nhiều key cùng gói
/// </summary>
public class KeyActivationPromotion : Entity<Guid>
{
    /// <summary>
    /// Tên chương trình
    /// </summary>
    public string Name { get; set; } = string.Empty;

    /// <summary>
    /// Gói dịch vụ áp dụng (chỉ key cùng gói mới được kích)
    /// </summary>
    public Guid ServicePackageId { get; set; }
    public virtual ServicePackage? ServicePackage { get; set; }

    /// <summary>
    /// Ngày bắt đầu chương trình
    /// </summary>
    public DateTime StartDate { get; set; }

    /// <summary>
    /// Ngày kết thúc chương trình
    /// </summary>
    public DateTime EndDate { get; set; }

    /// <summary>
    /// Số ngày tặng thêm khi kích 1 key
    /// </summary>
    public int Bonus1Key { get; set; } = 0;

    /// <summary>
    /// Số ngày tặng thêm khi kích 2 key
    /// </summary>
    public int Bonus2Keys { get; set; } = 0;

    /// <summary>
    /// Số ngày tặng thêm khi kích 3 key
    /// </summary>
    public int Bonus3Keys { get; set; } = 0;

    /// <summary>
    /// Số ngày tặng thêm khi kích 4 key
    /// </summary>
    public int Bonus4Keys { get; set; } = 0;

    /// <summary>
    /// Kích hoạt chương trình
    /// </summary>
    public bool IsActive { get; set; } = true;
}
