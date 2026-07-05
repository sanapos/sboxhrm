using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

public static class PosPriceListResolver
{
    public static string ItemKey(Guid productId, Guid? variantId, Guid? unitId)
    {
        if (variantId.HasValue && unitId.HasValue)
            return $"{productId}|v:{variantId}|u:{unitId}";
        if (variantId.HasValue)
            return $"{productId}|v:{variantId}";
        if (unitId.HasValue)
            return $"{productId}|u:{unitId}";
        return productId.ToString();
    }

    public static decimal? ResolvePrice(
        IReadOnlyDictionary<string, decimal> overrides,
        Guid productId,
        Guid? variantId,
        Guid? unitId)
    {
        if (variantId.HasValue && unitId.HasValue &&
            overrides.TryGetValue(ItemKey(productId, variantId, unitId), out var both))
            return both;
        if (variantId.HasValue &&
            overrides.TryGetValue(ItemKey(productId, variantId, null), out var v))
            return v;
        if (unitId.HasValue &&
            overrides.TryGetValue(ItemKey(productId, null, unitId), out var u))
            return u;
        if (overrides.TryGetValue(ItemKey(productId, null, null), out var p))
            return p;
        return null;
    }

    public static async Task<Dictionary<string, decimal>> LoadOverridesAsync(
        ZKTecoDbContext db, Guid storeId, Guid priceListId, CancellationToken ct = default)
    {
        var items = await db.PosPriceListItems.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.PriceListId == priceListId && x.Deleted == null && x.IsActive)
            .Select(x => new { x.ProductId, x.VariantId, x.UnitId, x.Price })
            .ToListAsync(ct);
        return items.ToDictionary(
            x => ItemKey(x.ProductId, x.VariantId, x.UnitId),
            x => x.Price);
    }

    public static async Task<PosPriceList> EnsureDefaultAsync(ZKTecoDbContext db, Guid storeId, string? user)
    {
        var existing = await db.PosPriceLists.AsTracking()
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.IsDefault && x.Deleted == null);
        if (existing != null) return existing;

        var any = await db.PosPriceLists.AnyAsync(x => x.StoreId == storeId && x.Deleted == null);
        var pl = new PosPriceList
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            Name = "Bảng giá chung",
            IsDefault = true,
            IsActive = true,
            SortOrder = 0,
            CreatedBy = user,
        };
        db.PosPriceLists.Add(pl);
        await db.SaveChangesAsync();
        return pl;
    }
}
