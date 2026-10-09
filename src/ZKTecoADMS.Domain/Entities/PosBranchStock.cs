using System.ComponentModel.DataAnnotations;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Chứng từ / giao dịch thuộc một chi nhánh. BranchId null = cửa hàng chưa dùng chi nhánh.
/// Interceptor tự gán chi nhánh đang thao tác khi tạo mới.
/// </summary>
public interface IBranchScoped
{
    Guid? BranchId { get; set; }
}

/// <summary>
/// Tồn kho của một chi nhánh (không phải trụ sở).
/// Tồn trụ sở = tổng tồn sản phẩm − Σ tồn các chi nhánh khác − hàng đang chuyển
/// → dữ liệu cũ tự thuộc trụ sở, tổng luôn khớp dù có chỗ cập nhật tồn không qua sổ kho.
/// VariantId null = dòng tồn cấp sản phẩm; có VariantId = tồn của biến thể.
/// </summary>
public class PosBranchStock
{
    [Key]
    public Guid Id { get; set; }

    public Guid StoreId { get; set; }

    public Guid BranchId { get; set; }

    public Guid ProductId { get; set; }

    public Guid? VariantId { get; set; }

    public decimal Qty { get; set; }

    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}

public enum PosStockTransferStatus
{
    /// <summary>Nháp — chưa trừ kho.</summary>
    Draft = 0,

    /// <summary>Đã xuất khỏi kho đi — hàng đang trên đường.</summary>
    Sent = 1,

    /// <summary>Kho nhận đã nhận hàng.</summary>
    Received = 2,

    Cancelled = 3,
}

/// <summary>Phiếu chuyển kho giữa hai chi nhánh (không đổi tổng tồn cửa hàng).</summary>
public class PosStockTransfer
{
    [Key]
    public Guid Id { get; set; }

    public Guid StoreId { get; set; }

    [MaxLength(30)]
    public string TransferNo { get; set; } = string.Empty;

    public Guid FromBranchId { get; set; }

    public Guid ToBranchId { get; set; }

    public PosStockTransferStatus Status { get; set; } = PosStockTransferStatus.Draft;

    [MaxLength(500)]
    public string? Note { get; set; }

    [MaxLength(200)]
    public string? CreatedByName { get; set; }

    [MaxLength(200)]
    public string? SentByName { get; set; }

    [MaxLength(200)]
    public string? ReceivedByName { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public DateTime? SentAt { get; set; }

    public DateTime? ReceivedAt { get; set; }

    public virtual ICollection<PosStockTransferLine> Lines { get; set; } = [];
}

public class PosStockTransferLine
{
    [Key]
    public Guid Id { get; set; }

    public Guid TransferId { get; set; }

    public virtual PosStockTransfer? Transfer { get; set; }

    public Guid ProductId { get; set; }

    public Guid? VariantId { get; set; }

    [MaxLength(300)]
    public string ProductName { get; set; } = string.Empty;

    [MaxLength(100)]
    public string? Sku { get; set; }

    [MaxLength(50)]
    public string? Unit { get; set; }

    public decimal Qty { get; set; }

    /// <summary>Số thực nhận (có thể thiếu so với số gửi — phần thiếu trả về kho đi).</summary>
    public decimal? ReceivedQty { get; set; }

    /// <summary>Seri máy chuyển theo dòng (mỗi seri một dòng) — hàng bắt buộc seri.</summary>
    public string? SerialNumbersText { get; set; }

    /// <summary>Lô lấy ra khi gửi (JSON [{lotId, qty}]) — để tạo lô tương ứng ở chi nhánh nhận hoặc hoàn lại khi thiếu / hủy.</summary>
    public string? LotAllocJson { get; set; }
}
