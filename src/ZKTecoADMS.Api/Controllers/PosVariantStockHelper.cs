using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Tồn kho kiểu KiotViet: lưu theo đơn vị nhỏ nhất (cơ bản);
/// ĐVT quy đổi chỉ đổi cách hiển thị / nhập (× conversionRate).
/// </summary>
internal static class PosVariantStockHelper
{
    public static decimal ParseConversionRate(string? attributeJson)
    {
        if (string.IsNullOrWhiteSpace(attributeJson)) return 1;
        try
        {
            using var doc = JsonDocument.Parse(attributeJson);
            if (doc.RootElement.TryGetProperty("_conversion", out var el))
            {
                var raw = el.GetString();
                if (decimal.TryParse(raw, System.Globalization.NumberStyles.Any,
                        System.Globalization.CultureInfo.InvariantCulture, out var rate) && rate > 0)
                    return rate;
            }
        }
        catch { /* ignore */ }
        return 1;
    }

    public static bool IsUnitOnlyVariant(string? attributeJson)
    {
        if (string.IsNullOrWhiteSpace(attributeJson)) return false;
        try
        {
            using var doc = JsonDocument.Parse(attributeJson);
            if (!doc.RootElement.TryGetProperty("_unit", out var unitEl)) return false;
            if (string.IsNullOrWhiteSpace(unitEl.GetString())) return false;
            foreach (var prop in doc.RootElement.EnumerateObject())
            {
                if (prop.Name.StartsWith('_')) continue;
                if (!string.IsNullOrWhiteSpace(prop.Value.GetString())) return false;
            }
            return true;
        }
        catch
        {
            return false;
        }
    }

    public static decimal ToBaseQty(decimal qtyInUnit, decimal conversionRate) =>
        qtyInUnit * (conversionRate > 0 ? conversionRate : 1);

    public static decimal ToDisplayQty(decimal baseQty, decimal conversionRate) =>
        conversionRate > 0 ? baseQty / conversionRate : baseQty;

    public static decimal ResolveVariantDisplayQty(
        decimal productBaseQty, string? attributeJson, decimal storedVariantQty)
    {
        if (!IsUnitOnlyVariant(attributeJson)) return storedVariantQty;
        return ToDisplayQty(productBaseQty, ParseConversionRate(attributeJson));
    }

    public static async Task<bool> UsesSharedBaseStockAsync(ZKTecoDbContext db, Guid productId)
    {
        var jsonList = await db.PosProductVariants.AsNoTracking()
            .Where(v => v.ProductId == productId && v.Deleted == null && v.IsActive)
            .Select(v => v.AttributeJson)
            .ToListAsync();
        if (jsonList.Count == 0) return true;
        return jsonList.All(IsUnitOnlyVariant);
    }

    public static decimal ApplyStockDelta(
        PosProduct product,
        PosProductVariant? variant,
        decimal qtyInUnit,
        bool add)
    {
        if (variant != null && IsUnitOnlyVariant(variant.AttributeJson))
        {
            var baseDelta = ToBaseQty(qtyInUnit, ParseConversionRate(variant.AttributeJson));
            product.OnHandQty += add ? baseDelta : -baseDelta;
            return product.OnHandQty;
        }

        if (variant != null)
        {
            variant.OnHandQty += add ? qtyInUnit : -qtyInUnit;
            return variant.OnHandQty;
        }

        product.OnHandQty += add ? qtyInUnit : -qtyInUnit;
        return product.OnHandQty;
    }

    public static decimal StockDeltaInBase(PosProductVariant? variant, decimal qtyInUnit)
    {
        if (variant != null && IsUnitOnlyVariant(variant.AttributeJson))
            return ToBaseQty(qtyInUnit, ParseConversionRate(variant.AttributeJson));
        return qtyInUnit;
    }

    /// <summary>
    /// Ngược của StockDeltaInBase — quy đổi QtyChange đã lưu ở đơn vị cơ bản (do StockDeltaInBase
    /// tạo ra khi ghi PosStockTransaction) trở lại đơn vị bán (ĐVT quy đổi), để so sánh/hiển thị
    /// đúng với PosSaleOrderLine.Qty (luôn lưu theo ĐVT bán, không phải đơn vị cơ bản).
    /// Thiếu bước quy đổi này khiến "đã trả" hiển thị sai (VD: bán 3 Thùng, trả 2 Thùng nhưng
    /// hiển thị 5 nếu 1 Thùng = 2.5 đơn vị cơ bản).
    /// </summary>
    public static decimal ToSaleUnitQty(decimal baseQtyChange, string? variantAttributeJson)
    {
        if (!IsUnitOnlyVariant(variantAttributeJson)) return baseQtyChange;
        return ToDisplayQty(baseQtyChange, ParseConversionRate(variantAttributeJson));
    }

    public static bool TryApplyVariantStockEdit(
        ZKTecoDbContext db,
        Guid storeId,
        Guid productId,
        PosProductVariant entity,
        decimal newQtyInUnit,
        string? createdBy)
    {
        if (entity.Product == null) return false;

        if (IsUnitOnlyVariant(entity.AttributeJson))
        {
            var oldBase = entity.Product.OnHandQty;
            var newBase = ToBaseQty(newQtyInUnit, ParseConversionRate(entity.AttributeJson));
            if (oldBase == newBase) return false;
            entity.Product.OnHandQty = newBase;
            PosStockRecording.RecordAdjustIfChanged(
                db, storeId, productId, entity.Id, oldBase, newBase, createdBy);
            return true;
        }

        var oldQty = entity.OnHandQty;
        if (oldQty == newQtyInUnit) return false;
        entity.OnHandQty = newQtyInUnit;
        PosStockRecording.RecordAdjustIfChanged(
            db, storeId, productId, entity.Id, oldQty, newQtyInUnit, createdBy);
        return true;
    }

    public static async Task SyncParentStockFromVariantsAsync(ZKTecoDbContext db, PosProduct product)
    {
        if (await UsesSharedBaseStockAsync(db, product.Id))
            return;

        var tracked = await db.PosProducts.AsTracking()
            .FirstOrDefaultAsync(p => p.Id == product.Id && p.Deleted == null);
        if (tracked == null) return;

        var sum = await db.PosProductVariants
            .Where(v => v.ProductId == product.Id && v.Deleted == null && v.IsActive)
            .SumAsync(v => v.OnHandQty);
        var hasVariants = await db.PosProductVariants
            .AnyAsync(v => v.ProductId == product.Id && v.Deleted == null && v.IsActive);
        if (!hasVariants) return;

        tracked.OnHandQty = sum;
        var minPrice = await db.PosProductVariants
            .Where(v => v.ProductId == product.Id && v.Deleted == null && v.IsActive)
            .MinAsync(v => (decimal?)v.BasePrice);
        if (minPrice.HasValue)
            tracked.BasePrice = minPrice.Value;
        tracked.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();
    }
}
