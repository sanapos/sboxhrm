using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Nhóm hàng POS (cây phân cấp tùy chọn).</summary>
public class PosProductCategory : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    public Guid? ParentId { get; set; }
    public virtual PosProductCategory? Parent { get; set; }
    public virtual ICollection<PosProductCategory> Children { get; set; } = [];

    [Required]
    [MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    public int SortOrder { get; set; }

    /// <summary>Máy in mặc định cho cả nhóm hàng (phiếu bếp).</summary>
    public Guid? DefaultPrinterId { get; set; }
    public virtual PosStorePrinter? DefaultPrinter { get; set; }

    /// <summary>Máy in tem mặc định cho cả nhóm hàng.</summary>
    public Guid? DefaultLabelPrinterId { get; set; }
    public virtual PosStorePrinter? DefaultLabelPrinter { get; set; }

    public virtual ICollection<PosProduct> Products { get; set; } = [];
}
