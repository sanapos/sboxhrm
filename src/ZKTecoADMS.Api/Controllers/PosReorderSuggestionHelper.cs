using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Hàng cần nhập thêm (dùng chung cho báo cáo «Gợi ý nhập hàng» và trợ lý ảo): tồn ≤ tồn tối thiểu.
/// Gợi ý nhập = tồn tối đa − tồn (chưa đặt tồn tối đa → 2 × tối thiểu − tồn), tối thiểu 1.
/// </summary>
public static class PosReorderSuggestionHelper
{
    public sealed record Row(
        Guid ProductId, string ProductCode, string Name, string UnitName,
        decimal OnHand, decimal MinStock, decimal MaxStock, decimal SuggestQty, decimal CostPrice,
        Guid? SupplierId, string? SupplierName)
    {
        public bool OutOfStock => OnHand <= 0;
        public decimal Amount => SuggestQty * CostPrice;
    }

    static readonly PosProductType[] Tracked = [PosProductType.Goods, PosProductType.Material, PosProductType.Topping];

    public static async Task<List<Row>> LoadAsync(ZKTecoDbContext db, Guid storeId, CancellationToken ct = default)
    {
        var rows = await db.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.IsActive &&
                        Tracked.Contains(p.ProductType) && p.MinStockQty > 0 && p.OnHandQty <= p.MinStockQty)
            .Select(p => new
            {
                p.Id, p.ProductCode, p.Name, p.BaseUnitName, p.OnHandQty, p.MinStockQty, p.MaxStockQty,
                p.CostPrice, p.SupplierId, SupplierName = p.Supplier != null ? p.Supplier.Name : null,
            })
            .OrderBy(p => p.SupplierName).ThenBy(p => p.OnHandQty)
            .ToListAsync(ct);
        return rows.Select(p =>
        {
            var target = p.MaxStockQty > p.MinStockQty ? p.MaxStockQty : p.MinStockQty * 2;
            var suggest = Math.Max(Math.Ceiling(target - Math.Max(p.OnHandQty, 0)), 1);
            return new Row(p.Id, p.ProductCode, p.Name, p.BaseUnitName, p.OnHandQty, p.MinStockQty, p.MaxStockQty,
                suggest, p.CostPrice, p.SupplierId, p.SupplierName);
        }).ToList();
    }
}
