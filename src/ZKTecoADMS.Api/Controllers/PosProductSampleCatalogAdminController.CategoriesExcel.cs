using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Application.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

public partial class PosProductSampleCatalogAdminController
{
    public record CategoryDto(
        Guid Id,
        string Name,
        Guid? ParentId,
        string? Kind,
        int SortOrder,
        bool IsActive,
        int SampleCount);

    public record CategoryUpsertDto(
        string Name,
        Guid? ParentId = null,
        PosProductSampleKind? Kind = null,
        int SortOrder = 0,
        bool IsActive = true);

    [HttpGet("facets")]
    public async Task<ActionResult<AppResponse<object>>> Facets()
    {
        var samples = dbContext.PosProductSampleCatalog.AsNoTracking()
            .Where(x => x.Deleted == null);
        var categories = await dbContext.PosProductSampleCategory.AsNoTracking()
            .Where(x => x.Deleted == null)
            .OrderBy(x => x.SortOrder).ThenBy(x => x.Name)
            .Select(x => new
            {
                x.Id,
                x.Name,
                x.ParentId,
                Kind = x.Kind.HasValue ? x.Kind.ToString() : null,
                x.SortOrder,
                x.IsActive,
            })
            .ToListAsync();
        var catCounts = await dbContext.PosProductSampleCatalog.AsNoTracking()
            .Where(x => x.Deleted == null && x.CategoryId != null)
            .GroupBy(x => x.CategoryId!.Value)
            .Select(g => new { id = g.Key, n = g.Count() })
            .ToDictionaryAsync(x => x.id, x => x.n);

        var brands = await samples
            .Where(x => x.BrandName != null && x.BrandName != "")
            .GroupBy(x => x.BrandName!)
            .Select(g => new { name = g.Key, count = g.Count() })
            .OrderBy(x => x.name)
            .ToListAsync();

        var kinds = await samples.GroupBy(x => x.Kind)
            .Select(g => new { kind = g.Key.ToString(), count = g.Count() })
            .ToListAsync();
        var types = await samples.GroupBy(x => x.ProductType)
            .Select(g => new { productType = g.Key.ToString(), count = g.Count() })
            .ToListAsync();
        var withImage = await samples.CountAsync(x => x.ImageUrl != null && x.ImageUrl != "");
        var total = await samples.CountAsync();

        return Ok(AppResponse<object>.Success(new
        {
            categories = categories.Select(x => new
            {
                x.Id,
                x.Name,
                x.ParentId,
                x.Kind,
                x.SortOrder,
                x.IsActive,
                SampleCount = catCounts.GetValueOrDefault(x.Id),
            }),
            brands,
            kinds,
            productTypes = types,
            total,
            withImage,
            withoutImage = total - withImage,
        }));
    }

    [HttpGet("categories")]
    public async Task<ActionResult<AppResponse<object>>> ListCategories(
        [FromQuery] bool includeInactive = true)
    {
        var q = dbContext.PosProductSampleCategory.AsNoTracking()
            .Where(x => x.Deleted == null);
        if (!includeInactive) q = q.Where(x => x.IsActive);
        var items = await q.OrderBy(x => x.SortOrder).ThenBy(x => x.Name).ToListAsync();
        var counts = await dbContext.PosProductSampleCatalog.AsNoTracking()
            .Where(x => x.Deleted == null && x.CategoryId != null)
            .GroupBy(x => x.CategoryId!.Value)
            .Select(g => new { id = g.Key, n = g.Count() })
            .ToDictionaryAsync(x => x.id, x => x.n);

        return Ok(AppResponse<object>.Success(items.Select(x => new CategoryDto(
            x.Id, x.Name, x.ParentId,
            x.Kind?.ToString(), x.SortOrder, x.IsActive,
            counts.GetValueOrDefault(x.Id))).ToList()));
    }

    [HttpPost("categories")]
    public async Task<ActionResult<AppResponse<CategoryDto>>> CreateCategory([FromBody] CategoryUpsertDto dto)
    {
        var name = (dto.Name ?? "").Trim();
        if (string.IsNullOrEmpty(name))
            return BadRequest(AppResponse<CategoryDto>.Fail("Thiếu tên nhóm hàng"));

        var dup = await dbContext.PosProductSampleCategory.AsNoTracking().AnyAsync(x =>
            x.Deleted == null && x.Name.ToLower() == name.ToLower());
        if (dup)
            return BadRequest(AppResponse<CategoryDto>.Fail("Nhóm hàng đã tồn tại"));

        var entity = new PosProductSampleCategory
        {
            Id = Guid.NewGuid(),
            Name = name,
            ParentId = dto.ParentId,
            Kind = dto.Kind,
            SortOrder = dto.SortOrder,
            IsActive = dto.IsActive,
            CreatedBy = CurrentUserEmail,
        };
        dbContext.PosProductSampleCategory.Add(entity);
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<CategoryDto>.Success(
            new CategoryDto(entity.Id, entity.Name, entity.ParentId, entity.Kind?.ToString(),
                entity.SortOrder, entity.IsActive, 0)));
    }

    [HttpPut("categories/{id:guid}")]
    public async Task<ActionResult<AppResponse<CategoryDto>>> UpdateCategory(Guid id, [FromBody] CategoryUpsertDto dto)
    {
        var entity = await dbContext.PosProductSampleCategory
            .FirstOrDefaultAsync(x => x.Id == id && x.Deleted == null);
        if (entity == null)
            return NotFound(AppResponse<CategoryDto>.Fail("Không tìm thấy nhóm hàng"));

        var name = (dto.Name ?? "").Trim();
        if (string.IsNullOrEmpty(name))
            return BadRequest(AppResponse<CategoryDto>.Fail("Thiếu tên nhóm hàng"));

        var dup = await dbContext.PosProductSampleCategory.AsNoTracking().AnyAsync(x =>
            x.Deleted == null && x.Id != id && x.Name.ToLower() == name.ToLower());
        if (dup)
            return BadRequest(AppResponse<CategoryDto>.Fail("Nhóm hàng đã tồn tại"));

        var oldName = entity.Name;
        entity.Name = name;
        entity.ParentId = dto.ParentId == id ? entity.ParentId : dto.ParentId;
        entity.Kind = dto.Kind;
        entity.SortOrder = dto.SortOrder;
        entity.IsActive = dto.IsActive;
        entity.UpdatedAt = DateTime.UtcNow;
        entity.UpdatedBy = CurrentUserEmail;

        if (!string.Equals(oldName, name, StringComparison.Ordinal))
        {
            await dbContext.PosProductSampleCatalog
                .Where(x => x.Deleted == null && x.CategoryId == id)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(x => x.CategoryName, name)
                    .SetProperty(x => x.UpdatedAt, DateTime.UtcNow));
        }

        await dbContext.SaveChangesAsync();
        var count = await dbContext.PosProductSampleCatalog.CountAsync(x =>
            x.Deleted == null && x.CategoryId == id);
        return Ok(AppResponse<CategoryDto>.Success(
            new CategoryDto(entity.Id, entity.Name, entity.ParentId, entity.Kind?.ToString(),
                entity.SortOrder, entity.IsActive, count)));
    }

    [HttpDelete("categories/{id:guid}")]
    public async Task<ActionResult<AppResponse<object>>> DeleteCategory(Guid id)
    {
        await dbContext.PosProductSampleCatalog
            .Where(x => x.Deleted == null && x.CategoryId == id)
            .ExecuteUpdateAsync(s => s
                .SetProperty(x => x.CategoryId, (Guid?)null)
                .SetProperty(x => x.UpdatedAt, DateTime.UtcNow));

        var n = await dbContext.PosProductSampleCategory
            .IgnoreQueryFilters()
            .Where(x => x.Id == id && x.Deleted == null)
            .ExecuteUpdateAsync(s => s
                .SetProperty(x => x.Deleted, DateTime.UtcNow)
                .SetProperty(x => x.DeletedBy, CurrentUserEmail)
                .SetProperty(x => x.IsActive, false)
                .SetProperty(x => x.UpdatedAt, DateTime.UtcNow)
                .SetProperty(x => x.UpdatedBy, CurrentUserEmail));
        if (n == 0)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy nhóm hàng"));
        return Ok(AppResponse<object>.Success(new { id }));
    }

    [HttpGet("excel-template")]
    public IActionResult ExcelTemplate()
    {
        var bytes = PosProductSampleCatalogExcel.BuildWorkbook(
        [
            new SampleCatalogExcelRow(null, "Coca Cola 330ml", "8934588012013", "Lon",
                "Coca-Cola", "Nước giải khát", PosProductSampleKind.Packaged, PosProductType.Goods,
                10000, 7000, 8, false, null, 1, true),
            new SampleCatalogExcelRow(null, "Cơm tấm sườn", null, "Phần",
                null, "Món chính", PosProductSampleKind.Food, PosProductType.Goods,
                45000, 25000, 8, false, null, 1, true),
        ],
        [
            ("Nước giải khát", "Có mã vạch", 1),
            ("Món chính", "Món ăn", 2),
        ]);
        return File(bytes,
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "Mau_catalog_mau_POS.xlsx");
    }

    [HttpGet("export/excel")]
    public async Task<IActionResult> ExportExcel(
        [FromQuery] string? search = null,
        [FromQuery] PosProductSampleKind? kind = null,
        [FromQuery] PosProductType? productType = null,
        [FromQuery] string? category = null,
        [FromQuery] Guid? categoryId = null,
        [FromQuery] string? brand = null,
        [FromQuery] bool? hasImage = null,
        [FromQuery] bool includeInactive = true)
    {
        var q = dbContext.PosProductSampleCatalog.AsNoTracking()
            .Where(x => x.Deleted == null);
        if (!includeInactive) q = q.Where(x => x.IsActive);
        if (kind.HasValue) q = q.Where(x => x.Kind == kind);
        if (productType.HasValue) q = q.Where(x => x.ProductType == productType);
        if (categoryId.HasValue) q = q.Where(x => x.CategoryId == categoryId);
        if (!string.IsNullOrWhiteSpace(category))
        {
            var c = category.Trim().ToLower();
            q = q.Where(x => x.CategoryName != null && x.CategoryName.ToLower() == c);
        }
        if (!string.IsNullOrWhiteSpace(brand))
        {
            var b = brand.Trim().ToLower();
            q = q.Where(x => x.BrandName != null && x.BrandName.ToLower() == b);
        }
        if (hasImage == true)
            q = q.Where(x => x.ImageUrl != null && x.ImageUrl != "");
        else if (hasImage == false)
            q = q.Where(x => x.ImageUrl == null || x.ImageUrl == "");
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            q = q.Where(x =>
                x.Name.ToLower().Contains(s) ||
                (x.Barcode != null && x.Barcode.ToLower().Contains(s)));
        }

        var items = await q.OrderBy(x => x.Kind).ThenBy(x => x.SortOrder).ThenBy(x => x.Name)
            .Take(10000)
            .ToListAsync();
        var cats = await dbContext.PosProductSampleCategory.AsNoTracking()
            .Where(x => x.Deleted == null)
            .OrderBy(x => x.SortOrder).ThenBy(x => x.Name)
            .Select(x => new { x.Name, Kind = x.Kind, x.SortOrder })
            .ToListAsync();

        var bytes = PosProductSampleCatalogExcel.BuildWorkbook(
            items.Select(x => new SampleCatalogExcelRow(
                x.Id, x.Name, x.Barcode, x.UnitName, x.BrandName, x.CategoryName,
                x.Kind, x.ProductType, x.DefaultPrice, x.DefaultCostPrice,
                x.VatRate, x.VatExempt, x.Description, x.SortOrder, x.IsActive, x.SellProfiles)).ToList(),
            cats.Select(c => (
                c.Name,
                c.Kind.HasValue ? PosProductSampleCatalogExcel.KindLabel(c.Kind.Value) : "",
                c.SortOrder)).ToList());
        return File(bytes,
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "Catalog_mau_POS.xlsx");
    }

    [HttpPost("import/excel")]
    [RequestSizeLimit(20_000_000)]
    [Consumes("multipart/form-data")]
    public async Task<ActionResult<AppResponse<object>>> ImportExcel(IFormFile? file)
    {
        if (file == null || file.Length == 0)
            return BadRequest(AppResponse<object>.Fail("File không hợp lệ"));

        List<SampleCatalogExcelRow> rows;
        try
        {
            await using var stream = file.OpenReadStream();
            rows = PosProductSampleCatalogExcel.Parse(stream);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Sample catalog Excel parse failed");
            return BadRequest(AppResponse<object>.Fail("Không đọc được file Excel. Cần cột Tên hàng."));
        }

        if (rows.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Không có dòng dữ liệu hợp lệ"));

        var created = 0;
        var updated = 0;
        foreach (var row in rows)
        {
            PosProductSampleCatalog? entity = null;
            if (row.Id.HasValue)
            {
                entity = await dbContext.PosProductSampleCatalog
                    .FirstOrDefaultAsync(x => x.Id == row.Id && x.Deleted == null);
            }
            if (entity == null && !string.IsNullOrWhiteSpace(row.Barcode))
            {
                var bc = row.Barcode.Trim().ToLower();
                entity = await dbContext.PosProductSampleCatalog
                    .FirstOrDefaultAsync(x => x.Deleted == null && x.Barcode != null &&
                                              x.Barcode.ToLower() == bc);
            }
            if (entity == null)
            {
                var n = row.Name.Trim().ToLower();
                entity = await dbContext.PosProductSampleCatalog
                    .FirstOrDefaultAsync(x => x.Deleted == null && x.Name.ToLower() == n);
            }

            var cat = await ResolveCategoryAsync(null, row.CategoryName, row.Kind);
            if (entity == null)
            {
                entity = new PosProductSampleCatalog
                {
                    Id = Guid.NewGuid(),
                    Name = row.Name.Trim(),
                    CreatedBy = CurrentUserEmail,
                };
                dbContext.PosProductSampleCatalog.Add(entity);
                created++;
            }
            else
            {
                updated++;
            }

            entity.Barcode = string.IsNullOrWhiteSpace(row.Barcode) ? entity.Barcode : row.Barcode.Trim();
            entity.Name = row.Name.Trim();
            entity.UnitName = row.UnitName ?? entity.UnitName ?? DefaultUnit(row.Kind);
            entity.BrandName = row.BrandName ?? entity.BrandName;
            entity.CategoryId = cat?.Id;
            entity.CategoryName = cat?.Name ?? row.CategoryName ?? entity.CategoryName;
            entity.Kind = row.Kind;
            entity.ProductType = row.ProductType;
            entity.DefaultPrice = row.DefaultPrice is > 0 ? row.DefaultPrice : entity.DefaultPrice;
            entity.DefaultCostPrice = row.DefaultCostPrice is > 0 ? row.DefaultCostPrice : entity.DefaultCostPrice;
            entity.VatExempt = row.VatExempt;
            entity.VatRate = row.VatExempt ? 0 : row.VatRate;
            entity.Description = row.Description ?? entity.Description;
            entity.SortOrder = row.SortOrder;
            entity.IsActive = row.IsActive;
            entity.SellProfiles = PosSampleSellProfileHelper.Normalize(row.SellProfiles) ?? entity.SellProfiles;
            entity.UpdatedAt = DateTime.UtcNow;
            entity.UpdatedBy = CurrentUserEmail;
        }

        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { created, updated, total = rows.Count }));
    }

    async Task<PosProductSampleCategory?> ResolveCategoryAsync(
        Guid? categoryId,
        string? categoryName,
        PosProductSampleKind kind)
    {
        if (categoryId.HasValue)
        {
            var byId = await dbContext.PosProductSampleCategory
                .FirstOrDefaultAsync(x => x.Id == categoryId && x.Deleted == null);
            if (byId != null) return byId;
        }

        var name = EmptyToNull(categoryName);
        if (name == null) return null;

        var existing = await dbContext.PosProductSampleCategory
            .FirstOrDefaultAsync(x => x.Deleted == null && x.Name.ToLower() == name.ToLower());
        if (existing != null) return existing;

        var created = new PosProductSampleCategory
        {
            Id = Guid.NewGuid(),
            Name = name,
            Kind = kind,
            IsActive = true,
            CreatedBy = CurrentUserEmail ?? "catalog",
        };
        dbContext.PosProductSampleCategory.Add(created);
        await dbContext.SaveChangesAsync();
        return created;
    }

    public static async Task<int> SyncCategoriesFromSamplesAsync(ZKTecoDbContext db, string? by)
    {
        var names = await db.PosProductSampleCatalog.AsNoTracking()
            .Where(x => x.Deleted == null && x.CategoryName != null && x.CategoryName != "")
            .Select(x => new { x.CategoryName, x.Kind })
            .ToListAsync();

        var existing = await db.PosProductSampleCategory
            .Where(x => x.Deleted == null)
            .ToListAsync();
        var byName = existing.ToDictionary(x => x.Name.Trim().ToLower(), x => x);

        var created = 0;
        var sort = existing.Count == 0 ? 0 : existing.Max(x => x.SortOrder);
        foreach (var row in names)
        {
            var key = row.CategoryName!.Trim().ToLower();
            if (key.Length == 0 || byName.ContainsKey(key)) continue;
            sort++;
            var cat = new PosProductSampleCategory
            {
                Id = Guid.NewGuid(),
                Name = row.CategoryName!.Trim(),
                Kind = row.Kind,
                SortOrder = sort,
                IsActive = true,
                CreatedBy = by ?? "sync",
            };
            db.PosProductSampleCategory.Add(cat);
            byName[key] = cat;
            created++;
        }

        if (created > 0) await db.SaveChangesAsync();

        foreach (var kv in byName)
        {
            var cat = kv.Value;
            await db.PosProductSampleCatalog
                .Where(x => x.Deleted == null &&
                            x.CategoryName != null &&
                            x.CategoryName.ToLower() == kv.Key &&
                            (x.CategoryId == null || x.CategoryId != cat.Id))
                .ExecuteUpdateAsync(s => s
                    .SetProperty(x => x.CategoryId, cat.Id));
        }

        return created;
    }
}
