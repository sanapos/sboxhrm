using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Dòng tồn kho dùng chung cho báo cáo Tồn kho (KPI, danh sách, Excel) và Sức khỏe kho: cùng một định nghĩa
/// tình trạng, cùng tồn theo chi nhánh đang xem, cùng giá trị tồn theo biến thể. Trước đây mỗi nơi tự tính
/// → bấm lọc «Dưới tối thiểu» ra số khác ô KPI, Excel lấy tồn cả cửa hàng khi đang xem một chi nhánh.
/// </summary>
public partial class PosReportsController
{
    internal sealed record PosStockRow(
        Guid Id,
        string ProductCode,
        string? Barcode,
        string Name,
        string? BaseUnitName,
        string? CategoryName,
        Guid? SupplierId,
        decimal OnHandQty,
        decimal MinStockQty,
        decimal MaxStockQty,
        decimal CostPrice,
        decimal StockValue,
        string ProductType,
        string Status);

    /// <summary>Hết hàng (≤ 0) → dưới tối thiểu (0 &lt; tồn &lt; min) → vượt tối đa → đủ hàng. Mỗi mặt hàng đúng một nhóm.</summary>
    internal static string PosStockStatus(decimal qty, decimal min, decimal max) =>
        qty <= 0 ? "OutOfStock"
        : min > 0 && qty < min ? "BelowMin"
        : max > 0 && qty > max ? "AboveMax"
        : "Ok";

    /// <summary>Tồn theo (hàng, biến thể) của các chi nhánh đang xem; null = không chia chi nhánh → dùng tồn cửa hàng.</summary>
    private async Task<Dictionary<(Guid, Guid?), decimal>?> BranchQtyFullScopeAsync(Guid storeId)
    {
        var b = HttpContext.BranchContext();
        if (b is not { StoreUsesBranches: true }) return null;
        IReadOnlyCollection<Guid>? ids = b.FilterBranchId is Guid f ? new[] { f } : b.AllowedBranchIds;
        if (ids == null) return null;
        var res = new Dictionary<(Guid, Guid?), decimal>();
        foreach (var bid in ids)
            foreach (var kv in await BranchStockService.GetBranchQtyAsync(dbContext, storeId, bid, b.HeadquarterBranchId))
                res[kv.Key] = res.GetValueOrDefault(kv.Key) + kv.Value;
        return res;
    }

    internal async Task<List<PosStockRow>> LoadStockRowsAsync(Guid storeId, string? search = null)
    {
        var query = StockTracked(dbContext.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.IsActive));
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            query = query.Where(p =>
                p.Name.ToLower().Contains(s) ||
                p.ProductCode.ToLower().Contains(s) ||
                (p.Barcode != null && p.Barcode.ToLower().Contains(s)));
        }

        var products = await query.Select(p => new
        {
            p.Id, p.ProductCode, p.Barcode, p.Name, p.BaseUnitName,
            CategoryName = p.Category != null ? p.Category.Name : null,
            p.SupplierId, p.OnHandQty, p.MinStockQty, p.MaxStockQty, p.CostPrice,
            ProductType = p.ProductType.ToString(),
        }).ToListAsync();
        if (products.Count == 0) return [];

        var ids = products.Select(p => p.Id).ToList();
        var variants = (await dbContext.PosProductVariants.AsNoTracking()
                .Where(v => v.StoreId == storeId && v.Deleted == null && v.IsActive && ids.Contains(v.ProductId))
                .Select(v => new { v.Id, v.ProductId, v.AttributeJson, v.OnHandQty, v.CostPrice })
                .ToListAsync())
            .Where(v => !PosVariantStockHelper.IsUnitOnlyVariant(v.AttributeJson))
            .GroupBy(v => v.ProductId)
            .ToDictionary(g => g.Key, g => g.ToList());

        var branch = await BranchQtyFullScopeAsync(storeId);
        return products.Select(p =>
        {
            var qty = branch == null ? p.OnHandQty : branch.GetValueOrDefault((p.Id, null));
            // Hàng có biến thể riêng (màu / size): giá trị = Σ tồn × giá vốn từng biến thể (giống tổng KPI).
            var value = variants.TryGetValue(p.Id, out var vs)
                ? vs.Sum(v => (branch == null ? v.OnHandQty : branch.GetValueOrDefault((p.Id, v.Id))) * v.CostPrice)
                : qty * p.CostPrice;
            return new PosStockRow(p.Id, p.ProductCode, p.Barcode, p.Name, p.BaseUnitName, p.CategoryName, p.SupplierId,
                qty, p.MinStockQty, p.MaxStockQty, p.CostPrice, value, p.ProductType,
                PosStockStatus(qty, p.MinStockQty, p.MaxStockQty));
        }).ToList();
    }

    internal static IEnumerable<PosStockRow> FilterStockRows(IEnumerable<PosStockRow> rows, string? filter) =>
        Enum.TryParse<PosStockFilter>(filter, true, out var f) && f != PosStockFilter.All
            ? rows.Where(r => r.Status == f.ToString())
            : rows;

    /// <summary>Ngày hôm nay theo giờ Việt Nam (HSD, số ngày chưa bán…). DateTime.UtcNow.Date lệch 1 ngày từ 0h–7h sáng.</summary>
    internal static DateTime VnToday => DateTime.UtcNow.AddHours(7).Date;

    /// <summary>Ngưỡng cảnh báo HSD của hàng; 0 / chưa đặt (dữ liệu cũ) → 30 ngày — một quy tắc cho KPI, bộ lọc và nhãn.</summary>
    internal static int ExpiryWarnDays(int? days) => days is > 0 ? days.Value : 30;
}
