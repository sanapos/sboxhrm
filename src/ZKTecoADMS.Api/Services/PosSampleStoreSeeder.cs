using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>Copy catalog mẫu + bàn/ghế/phòng vào cửa hàng theo hồ sơ ngành (CreatedBy = SampleData).</summary>
public static class PosSampleStoreSeeder
{
    public const string Marker = "SampleData";

    /// <summary>Tồn ban đầu của hàng mẫu có quản lý kho.</summary>
    const decimal SampleStockQty = 50;

    public sealed record Result(int Products, int Areas, int Resources);

    public static async Task<Result> SeedAsync(ZKTecoDbContext db, Guid storeId, CancellationToken ct)
    {
        var profile = await db.PosStoreSellSettings.AsNoTracking()
            .Where(s => s.StoreId == storeId && s.Deleted == null)
            .Select(s => s.SellProfile)
            .FirstOrDefaultAsync(ct);

        var catalog = await db.PosProductSampleCatalog.AsNoTracking()
            .Where(x => x.Deleted == null && x.IsActive)
            .WhereMatches(profile)
            .OrderBy(x => x.Kind).ThenBy(x => x.SortOrder).ThenBy(x => x.Name)
            .ToListAsync(ct);

        var existingNames = (await db.PosProducts.AsNoTracking()
                .IgnoreQueryFilters()
                .Where(p => p.StoreId == storeId && p.Deleted == null)
                .Select(p => p.Name)
                .ToListAsync(ct))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        var existingCodes = await db.PosProducts.AsNoTracking()
            .IgnoreQueryFilters()
            .Where(p => p.StoreId == storeId)
            .Select(p => p.ProductCode)
            .ToListAsync(ct);
        var codeSet = existingCodes.ToHashSet(StringComparer.OrdinalIgnoreCase);
        var nextByPrefix = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);

        var products = 0;
        foreach (var sample in catalog)
        {
            if (sample.ProductType == PosProductType.Combo) continue;
            if (existingNames.Contains(sample.Name)) continue;

            var categoryId = await EnsureCategoryAsync(db, storeId, sample.CategoryName, ct);
            var brandId = await EnsureBrandAsync(db, storeId, sample.BrandName, ct);
            var type = Enum.IsDefined(sample.ProductType) ? sample.ProductType : PosProductType.Goods;
            var unit = string.IsNullOrWhiteSpace(sample.UnitName) ? "Cái" : sample.UnitName.Trim();
            var isDirect = type is PosProductType.Goods or PosProductType.Service;
            if (type is PosProductType.Topping or PosProductType.Material)
                isDirect = false;

            var entity = new PosProduct
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                ProductCode = NextCode(type, codeSet, nextByPrefix),
                Barcode = string.IsNullOrWhiteSpace(sample.Barcode) ? null : sample.Barcode.Trim(),
                Name = sample.Name.Trim(),
                CategoryId = categoryId,
                BrandId = brandId,
                ProductType = type,
                Description = sample.Description,
                CostPrice = Math.Max(0, sample.DefaultCostPrice ?? 0),
                BasePrice = Math.Max(0, sample.DefaultPrice ?? 0),
                VatRate = sample.VatExempt ? 0 : sample.VatRate,
                VatExempt = sample.VatExempt,
                BaseUnitName = unit,
                ImageUrl = string.IsNullOrWhiteSpace(sample.ImageUrl) ? null : sample.ImageUrl.Trim(),
                IsDirectSale = isDirect,
                IsTopping = type == PosProductType.Topping,
                ServiceBillingMode = type == PosProductType.Service
                    ? sample.ServiceBillingMode
                    : PosServiceBillingMode.Flat,
                SessionPackCount = type == PosProductType.Service ? Math.Max(0, sample.SessionPackCount) : 0,
                SessionPackValidDays = type == PosProductType.Service
                    ? Math.Max(0, sample.SessionPackValidDays)
                    : 0,
                IsActive = true,
                CreatedAt = DateTime.UtcNow,
                CreatedBy = Marker,
            };
            if (entity.SessionPackCount > 0 && entity.SessionPackValidDays <= 0)
                entity.SessionPackValidDays = 90;
            // Hàng có quản lý tồn: cho sẵn tồn mẫu để bán thử được ngay — trước đây tồn 0, bán thử báo
            // «Không đủ tồn kho». Ghi thẻ kho như tạo hàng có tồn đầu kỳ.
            if (PosProductTypeRules.TracksInventory(type))
                entity.OnHandQty = SampleStockQty;

            db.PosProducts.Add(entity);
            if (entity.OnHandQty != 0)
                ZKTecoADMS.Api.Controllers.PosStockRecording.RecordAdjustIfChanged(
                    db, storeId, entity.Id, null, 0, entity.OnHandQty, Marker, "Tồn mẫu ban đầu");
            db.PosProductUnits.Add(new PosProductUnit
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                ProductId = entity.Id,
                UnitName = unit,
                ConversionRate = 1,
                BasePrice = entity.BasePrice,
                IsDirectSale = isDirect,
                IsBaseUnit = true,
                IsActive = true,
                CreatedAt = DateTime.UtcNow,
                CreatedBy = Marker,
            });
            existingNames.Add(entity.Name);
            products++;
        }

        var (areas, resources) = await SeedResourcesAsync(db, storeId, profile, ct);
        await db.SaveChangesAsync(ct);
        return new Result(products, areas, resources);
    }

    /// <summary>
    /// Xóa mềm hàng / khu / bàn mẫu — như nút Xóa hàng hóa: đơn đã bán thử bằng hàng mẫu vẫn mở được.
    /// Trước đây xóa cứng: vướng xmin của PosProducts (lỗi «expected to affect 1 row») và FK Restrict
    /// từ dòng đơn khi đã bán thử → không xóa được mẫu.
    /// </summary>
    public static async Task<(int Products, int Areas, int Resources)> DeleteAsync(
        ZKTecoDbContext db, Guid storeId, CancellationToken ct)
    {
        var now = DateTime.UtcNow;
        const string by = "SampleData.Delete";
        var productIds = db.PosProducts.IgnoreQueryFilters()
            .Where(p => p.StoreId == storeId && p.CreatedBy == Marker && p.Deleted == null)
            .Select(p => p.Id);

        await db.PosProductUnits.IgnoreQueryFilters()
            .Where(u => u.StoreId == storeId && u.Deleted == null && productIds.Contains(u.ProductId))
            .ExecuteUpdateAsync(s => s
                .SetProperty(u => u.IsActive, false)
                .SetProperty(u => u.Deleted, now)
                .SetProperty(u => u.DeletedBy, by), ct);

        await db.PosProductVariants.IgnoreQueryFilters()
            .Where(v => v.StoreId == storeId && v.Deleted == null && productIds.Contains(v.ProductId))
            .ExecuteUpdateAsync(s => s
                .SetProperty(v => v.IsActive, false)
                .SetProperty(v => v.Deleted, now)
                .SetProperty(v => v.DeletedBy, by), ct);

        var products = await db.PosProducts.IgnoreQueryFilters()
            .Where(p => p.StoreId == storeId && p.CreatedBy == Marker && p.Deleted == null)
            .ExecuteUpdateAsync(s => s
                .SetProperty(p => p.IsActive, false)
                .SetProperty(p => p.Deleted, now)
                .SetProperty(p => p.DeletedBy, by)
                .SetProperty(p => p.UpdatedAt, now), ct);

        var resources = await db.PosServiceResources.IgnoreQueryFilters()
            .Where(r => r.StoreId == storeId && r.CreatedBy == Marker && r.Deleted == null)
            .ExecuteUpdateAsync(s => s
                .SetProperty(r => r.IsActive, false)
                .SetProperty(r => r.Deleted, now)
                .SetProperty(r => r.DeletedBy, by), ct);

        var areas = await db.PosServiceAreas.IgnoreQueryFilters()
            .Where(a => a.StoreId == storeId && a.CreatedBy == Marker && a.Deleted == null)
            .ExecuteUpdateAsync(s => s
                .SetProperty(a => a.IsActive, false)
                .SetProperty(a => a.Deleted, now)
                .SetProperty(a => a.DeletedBy, by), ct);

        return (products, areas, resources);
    }

    static string NextCode(
        PosProductType type,
        HashSet<string> existing,
        Dictionary<string, int> nextByPrefix)
    {
        var prefix = PosProductTypeRules.CodePrefix(type);
        if (!nextByPrefix.TryGetValue(prefix, out var next))
        {
            next = 1;
            foreach (var code in existing)
            {
                if (!code.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) continue;
                var tail = code[prefix.Length..];
                if (tail.Length == 0 || !tail.All(char.IsDigit)) continue;
                if (int.TryParse(tail, out var n) && n >= next) next = n + 1;
            }
        }

        for (var i = 0; i < 50; i++)
        {
            var candidate = $"{prefix}{next + i:D5}";
            if (existing.Add(candidate))
            {
                nextByPrefix[prefix] = next + i + 1;
                return candidate;
            }
        }

        var fallback = $"{prefix}{DateTime.UtcNow:yyMMddHHmmss}";
        existing.Add(fallback);
        return fallback;
    }

    static async Task<Guid?> EnsureCategoryAsync(
        ZKTecoDbContext db, Guid storeId, string? name, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(name)) return null;
        var key = name.Trim().ToLower();
        var cat = await db.PosProductCategories
            .FirstOrDefaultAsync(c => c.StoreId == storeId && c.Deleted == null && c.Name.ToLower() == key, ct);
        if (cat != null) return cat.Id;
        cat = new PosProductCategory
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            Name = name.Trim(),
            IsActive = true,
            CreatedAt = DateTime.UtcNow,
            CreatedBy = Marker,
        };
        db.PosProductCategories.Add(cat);
        return cat.Id;
    }

    static async Task<Guid?> EnsureBrandAsync(
        ZKTecoDbContext db, Guid storeId, string? name, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(name)) return null;
        var key = name.Trim().ToLower();
        var brand = await db.PosProductBrands
            .FirstOrDefaultAsync(b => b.StoreId == storeId && b.Deleted == null && b.Name.ToLower() == key, ct);
        if (brand != null) return brand.Id;
        brand = new PosProductBrand
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            Name = name.Trim(),
            IsActive = true,
            CreatedAt = DateTime.UtcNow,
            CreatedBy = Marker,
        };
        db.PosProductBrands.Add(brand);
        return brand.Id;
    }

    static async Task<(int Areas, int Resources)> SeedResourcesAsync(
        ZKTecoDbContext db, Guid storeId, PosSellProfile profile, CancellationToken ct)
    {
        if (profile is PosSellProfile.Retail or PosSellProfile.Gym)
            return (0, 0);

        if (await db.PosServiceResources.IgnoreQueryFilters()
                .AnyAsync(r => r.StoreId == storeId && r.Deleted == null, ct))
            return (0, 0);

        var now = DateTime.UtcNow;
        PosServiceArea Area(string name, string code, string type, int sort)
        {
            var a = new PosServiceArea
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                Name = name,
                Code = code,
                AreaType = type,
                SortOrder = sort,
                IsActive = true,
                CreatedAt = now,
                CreatedBy = Marker,
            };
            db.PosServiceAreas.Add(a);
            return a;
        }

        void Resource(PosServiceArea area, string code, string name, PosResourceKind kind, int cap, int sort)
        {
            db.PosServiceResources.Add(new PosServiceResource
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                AreaId = area.Id,
                Code = code,
                Name = name,
                ResourceKind = kind,
                Capacity = cap,
                SortOrder = sort,
                IsActive = true,
                CreatedAt = now,
                CreatedBy = Marker,
            });
        }

        switch (profile)
        {
            case PosSellProfile.Restaurant:
            {
                var a = Area("Tầng 1", "T1", "table", 1);
                for (var i = 1; i <= 6; i++)
                    Resource(a, $"B{i:00}", $"Bàn {i}", PosResourceKind.Table, 4, i);
                return (1, 6);
            }
            case PosSellProfile.Salon:
            {
                var a = Area("Khu ghế", "GHE", "chair", 1);
                for (var i = 1; i <= 4; i++)
                    Resource(a, $"G{i:00}", $"Ghế {i}", PosResourceKind.Chair, 1, i);
                return (1, 4);
            }
            case PosSellProfile.RoomHourly:
            {
                var a = Area("Khu phòng", "P", "room", 1);
                Resource(a, "P01", "Phòng karaoke 1", PosResourceKind.Room, 8, 1);
                Resource(a, "P02", "Phòng karaoke VIP", PosResourceKind.Room, 12, 2);
                Resource(a, "BA01", "Bàn bi-a 1", PosResourceKind.Table, 4, 3);
                return (1, 3);
            }
            case PosSellProfile.Hotel:
            {
                var a = Area("Tầng 1", "T1", "room", 1);
                Resource(a, "101", "Phòng 101", PosResourceKind.Room, 2, 1);
                Resource(a, "102", "Phòng 102", PosResourceKind.Room, 2, 2);
                Resource(a, "103", "Phòng 103 Deluxe", PosResourceKind.Room, 2, 3);
                Resource(a, "104", "Phòng 104 Deluxe", PosResourceKind.Room, 2, 4);
                return (1, 4);
            }
            default:
                return (0, 0);
        }
    }
}
