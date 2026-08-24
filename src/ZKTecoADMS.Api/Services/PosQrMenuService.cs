using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

public record PosQrMenuItemDto(
    Guid ProductId,
    string ProductName,
    string? ProductCode,
    decimal StorePrice,
    decimal? QrPrice,
    bool ShowOnTable,
    bool ShowOnOnline,
    int SortOrder,
    string? ImageUrl,
    Guid? CategoryId,
    string? CategoryName);

public record PosQrMenuCatalogItemDto(
    Guid ProductId,
    string ProductName,
    string? ProductCode,
    decimal StorePrice,
    string? ImageUrl,
    Guid? CategoryId,
    string? CategoryName);

public record PosQrMenuSaveItem(
    Guid ProductId,
    decimal? QrPrice,
    bool ShowOnTable,
    bool ShowOnOnline,
    int SortOrder);

public class PosQrMenuService(ZKTecoDbContext db)
{
    public async Task<Dictionary<Guid, PosQrMenuItem>> LoadMapAsync(Guid storeId, CancellationToken ct = default)
    {
        var items = await db.PosQrMenuItems.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null && x.IsActive)
            .ToListAsync(ct);
        return items.ToDictionary(x => x.ProductId);
    }

    public static bool UseCustomMenu(string? extraJson) =>
        QrOrderLockHelper.Parse(extraJson).UseCustomMenu;

    public static List<PosProduct> FilterProducts(
        List<PosProduct> products,
        IReadOnlyDictionary<Guid, PosQrMenuItem> menuMap,
        bool useCustomMenu,
        bool online)
    {
        if (!useCustomMenu || menuMap.Count == 0)
            return products;
        return products
            .Where(p => menuMap.TryGetValue(p.Id, out var m)
                        && (online ? m.ShowOnOnline : m.ShowOnTable))
            .OrderBy(p => menuMap[p.Id].SortOrder)
            .ThenBy(p => p.Name)
            .ToList();
    }

    public static bool IsProductAllowed(
        Guid productId,
        IReadOnlyDictionary<Guid, PosQrMenuItem> menuMap,
        bool useCustomMenu,
        bool online)
    {
        if (!useCustomMenu || menuMap.Count == 0) return true;
        return menuMap.TryGetValue(productId, out var m)
               && (online ? m.ShowOnOnline : m.ShowOnTable);
    }

    public static decimal ResolveProductPrice(PosProduct product, PosQrMenuItem? menu) =>
        menu?.QrPrice ?? product.BasePrice;

    public static decimal ResolveVariantPrice(PosProduct product, PosProductVariant variant, PosQrMenuItem? menu)
    {
        if (menu?.QrPrice == null) return variant.BasePrice;
        if (product.BasePrice <= 0) return menu.QrPrice.Value;
        return Math.Round(menu.QrPrice.Value * variant.BasePrice / product.BasePrice, 0,
            MidpointRounding.AwayFromZero);
    }

    public static decimal ResolveUnitPrice(PosProduct product, PosProductUnit unit, PosQrMenuItem? menu)
    {
        var basePrice = ResolveProductPrice(product, menu);
        var rate = unit.ConversionRate > 0 ? unit.ConversionRate : 1;
        var configured = unit.BasePrice;
        if (rate > 1 && product.BasePrice > 0
            && (configured <= 0 || Math.Abs(configured - product.BasePrice) < 0.01m))
            return Math.Round(basePrice * rate, 0, MidpointRounding.AwayFromZero);
        if (configured > 0)
        {
            if (menu?.QrPrice != null && product.BasePrice > 0)
                return Math.Round(basePrice * configured / product.BasePrice, 0, MidpointRounding.AwayFromZero);
            return configured;
        }
        return Math.Round(basePrice * rate, 0, MidpointRounding.AwayFromZero);
    }

    public async Task<List<PosProduct>> LoadCatalogProductsAsync(Guid storeId, CancellationToken ct = default) =>
        await db.PosProducts.AsNoTracking()
            .Include(p => p.Category)
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.IsActive && p.IsDirectSale
                        && !p.IsTopping
                        && !p.RequiresSerial
                        && !(p.ProductType == PosProductType.Service
                             && p.ServiceBillingMode != PosServiceBillingMode.Flat))
            .OrderBy(p => p.SortOrder).ThenBy(p => p.Name)
            .ToListAsync(ct);

    public async Task<(bool UseCustomMenu, List<PosQrMenuItemDto> Items, List<PosQrMenuCatalogItemDto> Catalog)>
        LoadAdminAsync(Guid storeId, string? extraJson, CancellationToken ct = default)
    {
        var useCustom = UseCustomMenu(extraJson);
        var catalog = await LoadCatalogProductsAsync(storeId, ct);
        var menuRows = await db.PosQrMenuItems.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null && x.IsActive)
            .ToListAsync(ct);
        var menuByProduct = menuRows.ToDictionary(x => x.ProductId);
        var items = catalog
            .Where(p => menuByProduct.ContainsKey(p.Id))
            .OrderBy(p => menuByProduct[p.Id].SortOrder)
            .ThenBy(p => p.Name)
            .Select(p =>
            {
                var m = menuByProduct[p.Id];
                return new PosQrMenuItemDto(
                    p.Id, p.Name, p.ProductCode, p.BasePrice, m.QrPrice,
                    m.ShowOnTable, m.ShowOnOnline, m.SortOrder,
                    p.ImageUrl, p.CategoryId, p.Category?.Name);
            })
            .ToList();
        var catalogDto = catalog.Select(p => new PosQrMenuCatalogItemDto(
            p.Id, p.Name, p.ProductCode, p.BasePrice,
            p.ImageUrl, p.CategoryId, p.Category?.Name)).ToList();
        return (useCustom, items, catalogDto);
    }

    public async Task SaveAsync(
        Guid storeId,
        PosStoreSellSettings settings,
        bool useCustomMenu,
        IReadOnlyList<PosQrMenuSaveItem> items,
        string? userEmail,
        CancellationToken ct = default)
    {
        settings.ExtraJson = QrOrderLockHelper.MergeCustomMenu(settings.ExtraJson, useCustomMenu);
        settings.UpdatedAt = DateTime.UtcNow;
        settings.UpdatedBy = userEmail;

        var existing = await db.PosQrMenuItems
            .Where(x => x.StoreId == storeId && x.Deleted == null)
            .ToListAsync(ct);
        var byProduct = existing.ToDictionary(x => x.ProductId);
        var keep = new HashSet<Guid>();
        var now = DateTime.UtcNow;

        foreach (var item in items)
        {
            if (item.ProductId == Guid.Empty) continue;
            keep.Add(item.ProductId);
            decimal? price = item.QrPrice is > 0 ? Math.Round(item.QrPrice.Value, 0, MidpointRounding.AwayFromZero) : null;
            if (byProduct.TryGetValue(item.ProductId, out var row))
            {
                row.ShowOnTable = item.ShowOnTable;
                row.ShowOnOnline = item.ShowOnOnline;
                row.QrPrice = price;
                row.SortOrder = item.SortOrder;
                row.IsActive = true;
                row.UpdatedAt = now;
                row.UpdatedBy = userEmail;
                row.LastModified = now;
                row.LastModifiedBy = userEmail;
            }
            else
            {
                db.PosQrMenuItems.Add(new PosQrMenuItem
                {
                    Id = Guid.NewGuid(),
                    StoreId = storeId,
                    ProductId = item.ProductId,
                    ShowOnTable = item.ShowOnTable,
                    ShowOnOnline = item.ShowOnOnline,
                    QrPrice = price,
                    SortOrder = item.SortOrder,
                    IsActive = true,
                    CreatedAt = now,
                    CreatedBy = userEmail,
                });
            }
        }

        foreach (var row in existing.Where(x => !keep.Contains(x.ProductId)))
        {
            row.Deleted = now;
            row.DeletedBy = userEmail;
            row.IsActive = false;
        }

        await db.SaveChangesAsync(ct);
    }
}
