using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;
/// <summary>Phiếu xuất kho POS.</summary>
public class PosStockIssue : AuditableEntity<Guid>, IBranchScoped
{
    /// <summary>Chi nhánh (null = cửa hàng chưa dùng chi nhánh). Tự gán khi tạo mới.</summary>
    public Guid? BranchId { get; set; }

    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    [MaxLength(30)]
    public string IssueNo { get; set; } = string.Empty;

    [MaxLength(200)]
    public string? Reason { get; set; }

    [MaxLength(500)]
    public string? Note { get; set; }

    public PosStockIssueKind Kind { get; set; } = PosStockIssueKind.Generic;

    public PosStockIssueStatus Status { get; set; } = PosStockIssueStatus.Draft;

    public DateTime? IssuedAt { get; set; }

    [MaxLength(200)]
    public string? IssuedBy { get; set; }

    /// <summary>Loại xuất (xuất dùng nội bộ).</summary>
    [MaxLength(100)]
    public string? CategoryName { get; set; }

    /// <summary>Người nhận (xuất dùng nội bộ).</summary>
    [MaxLength(200)]
    public string? RecipientName { get; set; }

    public DateTime? CompletedAt { get; set; }

    public decimal TotalQty { get; set; }

    public decimal TotalValue { get; set; }

    /// <summary>Xuất kho theo báo giá thương mại (không phải hóa đơn bán).</summary>
    public Guid? QuoteId { get; set; }

    public virtual ICollection<PosStockIssueLine> Lines { get; set; } = [];
}
