using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Sổ tay bán hàng nhanh: một mục = tên chung + danh sách món kèm số lượng.
/// Bấm một mục trên màn bán là cả danh sách vào bàn (mỗi món một dòng riêng).
/// Khác combo: combo là một món bán ra, sổ tay chỉ là lối tắt nhập giỏ.
/// </summary>
public class PosQuickSellNote : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    [MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    /// <summary>Ghi chú ngắn cho thu ngân (vd «mâm 4 người»).</summary>
    [MaxLength(500)]
    public string? Description { get; set; }

    public int SortOrder { get; set; }

    public virtual ICollection<PosQuickSellNoteItem> Items { get; set; } = [];
}

/// <summary>Một món trong sổ tay bán nhanh.</summary>
public class PosQuickSellNoteItem : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    public Guid NoteId { get; set; }
    public virtual PosQuickSellNote? Note { get; set; }

    [Required]
    public Guid ProductId { get; set; }
    public virtual PosProduct? Product { get; set; }

    /// <summary>Số phần thêm vào giỏ khi bấm mục sổ tay.</summary>
    public decimal Qty { get; set; } = 1;

    public int SortOrder { get; set; }
}
