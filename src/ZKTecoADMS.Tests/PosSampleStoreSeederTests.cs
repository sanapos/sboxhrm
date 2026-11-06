using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>Cài mẫu POS: nhiều món cùng nhóm / thương hiệu chỉ tạo một nhóm / thương hiệu.</summary>
public class PosSampleStoreSeederTests
{
    static ZKTecoDbContext NewDb() => new(new DbContextOptionsBuilder<ZKTecoDbContext>()
        .UseInMemoryDatabase(Guid.NewGuid().ToString())
        .Options);

    static PosProductSampleCatalog Sample(string name, string category, string? brand, int sort) => new()
    {
        Id = Guid.NewGuid(),
        Name = name,
        CategoryName = category,
        BrandName = brand,
        UnitName = "Phần",
        DefaultPrice = 10000,
        SortOrder = sort,
        IsActive = true,
    };

    [Fact]
    public async Task SeedAsync_SameCategoryAndBrand_CreatesOneOfEach()
    {
        await using var db = NewDb();
        var storeId = Guid.NewGuid();
        db.PosProductSampleCatalog.AddRange(
            Sample("Phở bò", "Món chính", "Bếp Việt", 1),
            Sample("Bún chả", "Món chính", "Bếp Việt", 2),
            Sample("Cơm tấm", " món chính ", "bếp việt", 3),
            Sample("Cà phê đen", "Cà phê", null, 4));
        await db.SaveChangesAsync();

        var result = await PosSampleStoreSeeder.SeedAsync(db, storeId, CancellationToken.None);

        Assert.Equal(4, result.Products);
        var categories = await db.PosProductCategories.IgnoreQueryFilters()
            .Where(c => c.StoreId == storeId).ToListAsync();
        Assert.Equal(2, categories.Count);
        var brands = await db.PosProductBrands.IgnoreQueryFilters()
            .Where(b => b.StoreId == storeId).ToListAsync();
        Assert.Single(brands);
        var mainId = categories.Single(c => c.Name == "Món chính").Id;
        var products = await db.PosProducts.IgnoreQueryFilters()
            .Where(p => p.StoreId == storeId).ToListAsync();
        Assert.Equal(3, products.Count(p => p.CategoryId == mainId));
        Assert.Equal(3, products.Count(p => p.BrandId == brands[0].Id));
    }

    [Fact]
    public async Task SeedAsync_ExistingCategory_IsReused()
    {
        await using var db = NewDb();
        var storeId = Guid.NewGuid();
        var existing = new PosProductCategory
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            Name = "Món chính",
            IsActive = true,
        };
        db.PosProductCategories.Add(existing);
        db.PosProductSampleCatalog.Add(Sample("Phở bò", "Món chính", null, 1));
        await db.SaveChangesAsync();

        await PosSampleStoreSeeder.SeedAsync(db, storeId, CancellationToken.None);

        var categories = await db.PosProductCategories.IgnoreQueryFilters()
            .Where(c => c.StoreId == storeId).ToListAsync();
        Assert.Equal(existing.Id, Assert.Single(categories).Id);
    }
}
