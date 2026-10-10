using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Sổ công nợ khách hàng / nhà cung cấp — một dòng cho mỗi lần công nợ đổi (bán / nhập, hủy, trả hàng, thu / trả tiền).
/// Dùng cho sổ đối chiếu công nợ (đầu kỳ, phát sinh, cuối kỳ). Dữ liệu trước khi có sổ: một dòng «Số dư đầu».
/// </summary>
public class PosDebtLedgerEntry : Entity<Guid>
{
    public Guid StoreId { get; set; }

    /// <summary>customer | supplier</summary>
    public string PartyType { get; set; } = "customer";
    public Guid PartyId { get; set; }

    /// <summary>Thời điểm phát sinh (UTC).</summary>
    public DateTime At { get; set; }

    /// <summary>Opening | Sale | SaleCancel | Return | ReturnVoid | Payment | Receipt | ReceiptCancel | PurchaseReturn | Adjust</summary>
    public string DocType { get; set; } = "";
    public Guid? DocId { get; set; }
    public string? DocNo { get; set; }

    /// <summary>+ tăng nợ, − giảm nợ.</summary>
    public decimal Delta { get; set; }
    public decimal BalanceAfter { get; set; }
    public string? Note { get; set; }
}
