using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Ghi biến động tồn kho khi sửa trực tiếp số lượng (form hàng hóa / sửa nhanh).</summary>
internal static class PosStockRecording
{
    public static void RecordAdjustIfChanged(
        ZKTecoDbContext db,
        Guid storeId,
        Guid productId,
        Guid? variantId,
        decimal oldQty,
        decimal newQty,
        string? createdBy,
        string? note = null)
    {
        if (oldQty == newQty) return;

        db.PosStockTransactions.Add(new PosStockTransaction
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            ProductId = productId,
            VariantId = variantId,
            TransactionType = PosStockTransactionType.Adjust,
            QtyChange = newQty - oldQty,
            QtyAfter = newQty,
            ReferenceNo = PosStockDocumentNo.NewAdjust(),
            Note = note?.Trim() ?? "Cập nhật tồn từ sửa hàng hóa",
            IsActive = true,
            CreatedBy = createdBy,
        });
    }

    /// <summary>Ghi thẻ kho khi đổi giá vốn (SL = 0, kiểu KiotViet CP…).</summary>
    public static void RecordCostChangeIfChanged(
        ZKTecoDbContext db,
        Guid storeId,
        Guid productId,
        Guid? variantId,
        decimal qtyAfter,
        decimal oldCost,
        decimal newCost,
        string? createdBy)
    {
        if (oldCost == newCost) return;

        db.PosStockTransactions.Add(new PosStockTransaction
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            ProductId = productId,
            VariantId = variantId,
            TransactionType = PosStockTransactionType.Adjust,
            QtyChange = 0,
            QtyAfter = qtyAfter,
            ReferenceNo = PosStockDocumentNo.NewCostUpdate(),
            Note = $"Cập nhật giá vốn: {oldCost:N0} → {newCost:N0}",
            IsActive = true,
            CreatedBy = createdBy,
        });
    }
}
