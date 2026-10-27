using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// «Chụp hóa đơn NCC → phiếu nhập»: nhớ tên hàng in trên hóa đơn của một nhà cung cấp ứng với hàng nào của cửa hàng
/// (người dùng đã xác nhận). Lần sau hóa đơn cùng NCC ghi cùng tên → tự chọn đúng hàng, đúng ĐVT / hệ số quy đổi.
/// SupplierId null = hóa đơn không rõ NCC (dùng chung cho cả cửa hàng).
/// </summary>
public class PosAiInvoiceMapping : Entity<Guid>
{
    public Guid StoreId { get; set; }

    public Guid? SupplierId { get; set; }

    /// <summary>Khóa so tên: bỏ dấu, chỉ chữ + số (<c>PosProductNameMatch.FoldKey</c>).</summary>
    [MaxLength(300)]
    public string NameKey { get; set; } = string.Empty;

    /// <summary>Tên đúng như in trên hóa đơn (lần xác nhận gần nhất).</summary>
    [MaxLength(500)]
    public string InvoiceName { get; set; } = string.Empty;

    public Guid ProductId { get; set; }

    /// <summary>ĐVT in trên hóa đơn (vd «Thùng») của lần xác nhận gần nhất.</summary>
    [MaxLength(100)]
    public string? InvoiceUnit { get; set; }

    /// <summary>ĐVT của hàng dùng trên phiếu nhập (ĐVT gốc hoặc ĐVT quy đổi đã khai báo).</summary>
    [MaxLength(100)]
    public string? UnitName { get; set; }

    /// <summary>1 ĐVT hóa đơn = UnitFactor × ĐVT gốc khi hàng chưa khai báo ĐVT đó (người dùng nhập tay); 1 = không quy đổi.</summary>
    public decimal UnitFactor { get; set; } = 1;

    public int UseCount { get; set; }

    public DateTime LastUsedAt { get; set; } = DateTime.UtcNow;
}
