using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Mã vạch đang dùng ở đâu trong cửa hàng (hàng hóa, biến thể, đơn vị bán) — chặn gán trùng: một mã vạch
/// quét ra hai thứ thì máy bán không biết thêm thứ nào.
/// </summary>
public static class PosBarcodeUsage
{
    /// <summary>Mô tả nơi đang dùng mã (vd «Hàng Bia Tiger (SP0012)»), null = chưa dùng.</summary>
    public static async Task<string?> FindOwnerAsync(
        ZKTecoDbContext db,
        Guid storeId,
        string code,
        Guid? excludeUnitId = null,
        CancellationToken ct = default)
    {
        var c = code.Trim();
        if (c.Length == 0) return null;
        var lower = c.ToLower();

        var product = await db.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null &&
                        ((p.Barcode != null && p.Barcode.ToLower() == lower) || p.ProductCode.ToLower() == lower))
            .Select(p => new { p.Name, p.ProductCode })
            .FirstOrDefaultAsync(ct);
        if (product != null) return $"hàng «{product.Name}» ({product.ProductCode})";

        var variant = await db.PosProductVariants.AsNoTracking()
            .Where(v => v.StoreId == storeId && v.Deleted == null &&
                        ((v.Barcode != null && v.Barcode.ToLower() == lower) || v.SkuCode.ToLower() == lower))
            .Select(v => new { v.Name, ProductName = v.Product!.Name })
            .FirstOrDefaultAsync(ct);
        if (variant != null) return $"biến thể «{variant.ProductName} · {variant.Name}»";

        var unit = await db.PosProductUnits.AsNoTracking()
            .Where(u => u.StoreId == storeId && u.Deleted == null && u.Barcode != null &&
                        u.Barcode.ToLower() == lower && (excludeUnitId == null || u.Id != excludeUnitId))
            .Select(u => new { u.UnitName, ProductName = u.Product!.Name })
            .FirstOrDefaultAsync(ct);
        return unit == null ? null : $"đơn vị «{unit.ProductName} · {unit.UnitName}»";
    }
}
