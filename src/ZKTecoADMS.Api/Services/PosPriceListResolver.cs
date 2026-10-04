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
        // Tránh ToDictionary nổ khi có dòng trùng khóa (schema cũ không UNIQUE).
        return items
            .GroupBy(x => ItemKey(x.ProductId, x.VariantId, x.UnitId))
            .ToDictionary(g => g.Key, g => g.Last().Price);
    }

    /// <summary>
    /// Bảng giá tự áp khi hóa đơn không chọn bảng: «Mặc định» còn hiệu lực → bảng không giới hạn ngày →
    /// bảng bất kỳ còn hiệu lực. Dùng chung cho thu ngân và QR bàn / online để cùng một giá.
    /// </summary>
    public static PosPriceList? PickDefault(IEnumerable<PosPriceList> activeLists, DateTime day)
    {
        var candidates = activeLists
            .OrderByDescending(x => x.IsDefault).ThenBy(x => x.SortOrder)
            .ToList();
        return candidates.FirstOrDefault(x => x.IsDefault && IsApplicableOn(x, day))
            ?? candidates.FirstOrDefault(x => !x.ValidFrom.HasValue && !x.ValidTo.HasValue)
            ?? candidates.FirstOrDefault(x => IsApplicableOn(x, day));
    }

    /// <summary>Bảng giá mặc định hôm nay (giờ VN) + bảng giá đã nạp — null nếu cửa hàng chưa có bảng giá.</summary>
    public static async Task<(PosPriceList? List, Dictionary<string, decimal> Overrides)> LoadDefaultForTodayAsync(
        ZKTecoDbContext db, Guid storeId, CancellationToken ct = default)
    {
        var lists = await db.PosPriceLists.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null && x.IsActive)
            .ToListAsync(ct);
        var pick = PickDefault(lists, DateTime.UtcNow.AddHours(7).Date);
        if (pick == null) return (null, new Dictionary<string, decimal>());
        return (pick, await LoadOverridesAsync(db, storeId, pick.Id, ct));
    }

    /// <summary>True nếu bảng giá áp dụng cho ngày hóa đơn (theo ValidFrom/ValidTo).</summary>
    public static bool IsApplicableOn(PosPriceList list, DateTime day)
    {
        var d = day.Date;
        if (list.ValidFrom.HasValue && d < list.ValidFrom.Value.Date) return false;
        if (list.ValidTo.HasValue && d > list.ValidTo.Value.Date) return false;
        return true;
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
