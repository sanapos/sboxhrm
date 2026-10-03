using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Một dòng của phiếu trả hàng bán (theo dòng hóa đơn gốc). Nguồn duy nhất cho «đã trả bao nhiêu»,
/// tiền hoàn và giá vốn hoàn — áp dụng cả hàng hóa, dịch vụ, combo, món định lượng (không phụ thuộc thẻ kho).
/// </summary>
public class PosSaleReturnLine : AuditableEntity<Guid>
{
    public Guid StoreId { get; set; }

    public Guid SaleOrderId { get; set; }

    /// <summary>Dòng hóa đơn gốc được trả.</summary>
    public Guid SaleOrderLineId { get; set; }

    /// <summary>Số phiếu trả (TH…) — trùng ReferenceNo trên thẻ kho.</summary>
    [MaxLength(50)]
    public string ReturnNo { get; set; } = string.Empty;

    public Guid ProductId { get; set; }

    public Guid? VariantId { get; set; }

    /// <summary>Số lượng trả theo đơn vị bán của dòng gốc.</summary>
    public decimal Qty { get; set; }

    /// <summary>Tiền hoàn (đã phân bổ giảm giá / voucher / điểm của đơn, chưa gồm VAT).</summary>
    public decimal RefundAmount { get; set; }

    /// <summary>Giá vốn hàng trả (cộng lại kho) — trừ khỏi giá vốn hàng bán.</summary>
    public decimal CostAmount { get; set; }

    public bool IsVoided { get; set; }

    public DateTime? VoidedAt { get; set; }
}
