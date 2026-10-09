using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Sổ seri máy: mỗi máy một dòng, theo dõi từ lúc nhập kho đến khi bán / trả nhà cung cấp.</summary>
public class PosProductSerial : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }

    [Required]
    public Guid ProductId { get; set; }

    public Guid? VariantId { get; set; }

    [Required]
    [MaxLength(100)]
    public string SerialNumber { get; set; } = string.Empty;

    [MaxLength(50)]
    public string? Imei { get; set; }

    /// <summary>Mã thẻ RFID / mã kiểm kho gắn với máy (EPC, viết hoa). Quét mã này cũng nhận ra máy.</summary>
    [MaxLength(100)]
    public string? TagCode { get; set; }

    public PosSerialStatus Status { get; set; } = PosSerialStatus.InStock;

    /// <summary>Phiếu nhập kho đưa máy vào.</summary>
    public Guid? ReceiptId { get; set; }

    /// <summary>Phiếu trả nhà cung cấp lấy máy ra.</summary>
    public Guid? PurchaseReturnId { get; set; }

    /// <summary>Chi nhánh đang giữ máy (null = trụ sở / cửa hàng chưa dùng chi nhánh).</summary>
    public Guid? BranchId { get; set; }

    /// <summary>Phiếu chuyển kho đang chở máy (khác null = đang trên đường, chưa bán được).</summary>
    public Guid? TransferId { get; set; }

    /// <summary>Đơn bán đang giữ máy (Status = Sold).</summary>
    public Guid? SaleOrderId { get; set; }

    public DateTime ReceivedDate { get; set; }
    public DateTime? SoldDate { get; set; }
    public decimal CostPrice { get; set; }

    [MaxLength(500)]
    public string? Note { get; set; }
}
