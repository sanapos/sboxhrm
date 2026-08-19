using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Application.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Super Admin — catalog hàng mẫu / menu món (ảnh dùng chung toàn hệ thống).</summary>
[Authorize(Roles = nameof(Roles.SuperAdmin))]
[Route("api/system-admin/pos-sample-catalog")]
public partial class PosProductSampleCatalogAdminController(
    ZKTecoDbContext dbContext,
    IFileStorageService fileStorageService,
    IWebHostEnvironment webHostEnvironment,
    ILogger<PosProductSampleCatalogAdminController> logger) : AuthenticatedControllerBase
{
    public record SampleDto(
        Guid Id,
        string? Barcode,
        string Name,
        string? UnitName,
        string? BrandName,
        string? CategoryName,
        Guid? CategoryId,
        string? ImageUrl,
        bool HasImage,
        string? Description,
        string Kind,
        string ProductType,
        decimal? DefaultPrice,
        decimal? DefaultCostPrice,
        decimal VatRate,
        bool VatExempt,
        string? SellProfiles,
        string ServiceBillingMode,
        int SessionPackCount,
        int SessionPackValidDays,
        int SortOrder,
        bool IsActive);

    public record SampleUpsertDto(
        string? Barcode,
        string Name,
        string? UnitName,
        string? BrandName,
        string? CategoryName,
        Guid? CategoryId = null,
        string? Description = null,
        PosProductSampleKind Kind = PosProductSampleKind.Packaged,
        PosProductType ProductType = PosProductType.Goods,
        decimal? DefaultPrice = null,
        decimal? DefaultCostPrice = null,
        decimal? VatRate = null,
        bool VatExempt = false,
        string? SellProfiles = null,
        PosServiceBillingMode ServiceBillingMode = PosServiceBillingMode.Flat,
        int SessionPackCount = 0,
        int SessionPackValidDays = 0,
        int SortOrder = 0,
        bool IsActive = true);

    static SampleDto Map(PosProductSampleCatalog x) => new(
        x.Id, x.Barcode, x.Name, x.UnitName, x.BrandName, x.CategoryName, x.CategoryId,
        x.ImageUrl, !string.IsNullOrWhiteSpace(x.ImageUrl), x.Description,
        x.Kind.ToString(), x.ProductType.ToString(), x.DefaultPrice, x.DefaultCostPrice,
        x.VatRate, x.VatExempt, x.SellProfiles, x.ServiceBillingMode.ToString(),
        x.SessionPackCount, x.SessionPackValidDays, x.SortOrder, x.IsActive);

    [HttpGet]
    public async Task<ActionResult<AppResponse<object>>> List(
        [FromQuery] string? search = null,
        [FromQuery] PosProductSampleKind? kind = null,
        [FromQuery] PosProductType? productType = null,
        [FromQuery] string? category = null,
        [FromQuery] Guid? categoryId = null,
        [FromQuery] string? brand = null,
        [FromQuery] string? sellProfile = null,
        [FromQuery] bool? hasImage = null,
        [FromQuery] bool? isActive = null,
        [FromQuery] bool includeInactive = false,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 500);
        var q = dbContext.PosProductSampleCatalog.AsNoTracking()
            .Where(x => x.Deleted == null);
        if (isActive.HasValue) q = q.Where(x => x.IsActive == isActive.Value);
        else if (!includeInactive) q = q.Where(x => x.IsActive);
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
        if (!string.IsNullOrWhiteSpace(sellProfile) &&
            PosSellProfileDefaults.TryParse(sellProfile, out var profileFilter))
            q = q.WhereMatches(profileFilter);
        if (hasImage == true)
            q = q.Where(x => x.ImageUrl != null && x.ImageUrl != "");
        else if (hasImage == false)
            q = q.Where(x => x.ImageUrl == null || x.ImageUrl == "");
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            q = q.Where(x =>
                x.Name.ToLower().Contains(s) ||
                (x.Barcode != null && x.Barcode.ToLower().Contains(s)) ||
                (x.CategoryName != null && x.CategoryName.ToLower().Contains(s)) ||
                (x.BrandName != null && x.BrandName.ToLower().Contains(s)) ||
                (x.Description != null && x.Description.ToLower().Contains(s)));
        }
        var total = await q.CountAsync();
        var items = await q.OrderBy(x => x.Kind).ThenBy(x => x.SortOrder).ThenBy(x => x.Name)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .ToListAsync();
        return Ok(AppResponse<object>.Success(new
        {
            total,
            page,
            pageSize,
            items = items.Select(Map).ToList(),
        }));
    }

    [HttpPost]
    public async Task<ActionResult<AppResponse<SampleDto>>> Create([FromBody] SampleUpsertDto dto)
    {
        var name = (dto.Name ?? "").Trim();
        if (string.IsNullOrEmpty(name))
            return BadRequest(AppResponse<SampleDto>.Fail("Thiếu tên hàng mẫu"));

        var barcode = string.IsNullOrWhiteSpace(dto.Barcode) ? null : dto.Barcode.Trim();
        if (barcode != null)
        {
            var dup = await dbContext.PosProductSampleCatalog.AsNoTracking().AnyAsync(x =>
                x.Deleted == null && x.Barcode != null && x.Barcode.ToLower() == barcode.ToLower());
            if (dup)
                return BadRequest(AppResponse<SampleDto>.Fail("Mã vạch đã có trong catalog mẫu"));
        }

        var productType = Enum.IsDefined(dto.ProductType) ? dto.ProductType : PosProductType.Goods;
        var vatExempt = dto.VatExempt;
        var vatRate = vatExempt ? 0 : Math.Clamp(dto.VatRate ?? 8m, 0, 100);

        var entity = new PosProductSampleCatalog
        {
            Id = Guid.NewGuid(),
            Barcode = barcode,
            Name = name,
            UnitName = EmptyToNull(dto.UnitName) ?? DefaultUnit(dto.Kind),
            BrandName = EmptyToNull(dto.BrandName),
            CategoryName = EmptyToNull(dto.CategoryName) ?? DefaultCategory(dto.Kind),
            Description = EmptyToNull(dto.Description),
            Kind = dto.Kind,
            ProductType = productType,
            DefaultPrice = dto.DefaultPrice is > 0 ? dto.DefaultPrice : null,
            DefaultCostPrice = dto.DefaultCostPrice is > 0 ? dto.DefaultCostPrice : null,
            VatRate = vatRate,
            VatExempt = vatExempt,
            SortOrder = dto.SortOrder,
            IsActive = dto.IsActive,
            SellProfiles = PosSampleSellProfileHelper.Normalize(dto.SellProfiles),
            ServiceBillingMode = Enum.IsDefined(dto.ServiceBillingMode)
                ? dto.ServiceBillingMode
                : PosServiceBillingMode.Flat,
            SessionPackCount = Math.Max(0, dto.SessionPackCount),
            SessionPackValidDays = Math.Max(0, dto.SessionPackValidDays),
            CreatedBy = CurrentUserEmail,
        };
        var resolved = await ResolveCategoryAsync(dto.CategoryId, dto.CategoryName, dto.Kind);
        entity.CategoryId = resolved?.Id;
        entity.CategoryName = resolved?.Name ?? entity.CategoryName;
        dbContext.PosProductSampleCatalog.Add(entity);
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<SampleDto>.Success(Map(entity)));
    }

    [HttpPut("{id:guid}")]
    public async Task<ActionResult<AppResponse<SampleDto>>> Update(Guid id, [FromBody] SampleUpsertDto dto)
    {
        var entity = await dbContext.PosProductSampleCatalog
            .FirstOrDefaultAsync(x => x.Id == id && x.Deleted == null);
        if (entity == null)
            return NotFound(AppResponse<SampleDto>.Fail("Không tìm thấy mẫu"));

        var name = (dto.Name ?? "").Trim();
        if (string.IsNullOrEmpty(name))
            return BadRequest(AppResponse<SampleDto>.Fail("Thiếu tên hàng mẫu"));

        var barcode = string.IsNullOrWhiteSpace(dto.Barcode) ? null : dto.Barcode.Trim();
        if (barcode != null)
        {
            var dup = await dbContext.PosProductSampleCatalog.AsNoTracking().AnyAsync(x =>
                x.Deleted == null && x.Id != id && x.Barcode != null &&
                x.Barcode.ToLower() == barcode.ToLower());
            if (dup)
                return BadRequest(AppResponse<SampleDto>.Fail("Mã vạch đã có trong catalog mẫu"));
        }

        var productType = Enum.IsDefined(dto.ProductType) ? dto.ProductType : entity.ProductType;
        var vatExempt = dto.VatExempt;
        var vatRate = vatExempt ? 0 : Math.Clamp(dto.VatRate ?? entity.VatRate, 0, 100);

        entity.Barcode = barcode;
        entity.Name = name;
        entity.UnitName = EmptyToNull(dto.UnitName) ?? entity.UnitName;
        entity.BrandName = EmptyToNull(dto.BrandName);
        var cat = await ResolveCategoryAsync(dto.CategoryId, dto.CategoryName, dto.Kind);
        entity.CategoryId = cat?.Id;
        entity.CategoryName = cat?.Name ?? EmptyToNull(dto.CategoryName);
        entity.Description = EmptyToNull(dto.Description);
        entity.Kind = dto.Kind;
        entity.ProductType = productType;
        entity.DefaultPrice = dto.DefaultPrice is > 0 ? dto.DefaultPrice : null;
        entity.DefaultCostPrice = dto.DefaultCostPrice is > 0 ? dto.DefaultCostPrice : null;
        entity.VatRate = vatRate;
        entity.VatExempt = vatExempt;
        entity.SortOrder = dto.SortOrder;
        entity.IsActive = dto.IsActive;
        entity.SellProfiles = PosSampleSellProfileHelper.Normalize(dto.SellProfiles);
        entity.ServiceBillingMode = Enum.IsDefined(dto.ServiceBillingMode)
            ? dto.ServiceBillingMode
            : entity.ServiceBillingMode;
        entity.SessionPackCount = Math.Max(0, dto.SessionPackCount);
        entity.SessionPackValidDays = Math.Max(0, dto.SessionPackValidDays);
        entity.UpdatedAt = DateTime.UtcNow;
        entity.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<SampleDto>.Success(Map(entity)));
    }

    [HttpDelete("{id:guid}")]
    public async Task<ActionResult<AppResponse<object>>> Delete(Guid id)
    {
        var n = await dbContext.PosProductSampleCatalog
            .IgnoreQueryFilters()
            .Where(x => x.Id == id && x.Deleted == null)
            .ExecuteUpdateAsync(s => s
                .SetProperty(x => x.Deleted, DateTime.UtcNow)
                .SetProperty(x => x.DeletedBy, CurrentUserEmail)
                .SetProperty(x => x.IsActive, false)
                .SetProperty(x => x.UpdatedAt, DateTime.UtcNow)
                .SetProperty(x => x.UpdatedBy, CurrentUserEmail));
        if (n == 0)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy mẫu"));
        return Ok(AppResponse<object>.Success(new { id }));
    }

    [HttpPost("{id:guid}/image")]
    [RequestSizeLimit(15_000_000)]
    [Consumes("multipart/form-data")]
    public async Task<ActionResult<AppResponse<object>>> UploadImage(Guid id, [FromForm] IFormFile? file)
    {
        if (file == null || file.Length == 0)
            return BadRequest(AppResponse<object>.Fail("Chưa chọn ảnh"));

        var exists = await dbContext.PosProductSampleCatalog
            .AsNoTracking()
            .AnyAsync(x => x.Id == id && x.Deleted == null);
        if (!exists)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy mẫu"));

        var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
        if (ext is not (".jpg" or ".jpeg" or ".png" or ".webp" or ".gif" or ".jfif"))
            ext = ".jpg";

        try
        {
            await using var raw = file.OpenReadStream();
            var (optimized, uploadName, _) = await ImageOptimizeHelper.OptimizeAsync(
                raw,
                string.IsNullOrWhiteSpace(Path.GetExtension(file.FileName))
                    ? $"{id:N}{ext}"
                    : file.FileName,
                ImageOptimizeHelper.SampleCatalogMaxEdge,
                ImageOptimizeHelper.SampleCatalogJpegQuality);
            await using (optimized)
            {
                var path = await fileStorageService.UploadAsync(
                    optimized, uploadName, "catalog/pos-samples");
                var imagePath = path.TrimStart('/');
                var updatedBy = CurrentUserEmail ?? "API";
                var now = DateTime.UtcNow;
                // ExecuteUpdate: change-tracker thường không persist ImageUrl.
                var rows = await dbContext.PosProductSampleCatalog
                    .Where(x => x.Id == id && x.Deleted == null)
                    .ExecuteUpdateAsync(s => s
                        .SetProperty(x => x.ImageUrl, imagePath)
                        .SetProperty(x => x.UpdatedAt, now)
                        .SetProperty(x => x.UpdatedBy, updatedBy));
                if (rows == 0)
                    return NotFound(AppResponse<object>.Fail("Không cập nhật được ảnh mẫu"));
                logger.LogInformation(
                    "Sample catalog image saved: {Id} -> {ImageUrl}", id, imagePath);
                return Ok(AppResponse<object>.Success(new { imageUrl = imagePath }));
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Sample catalog image upload failed {Id}", id);
            return BadRequest(AppResponse<object>.Fail("Không lưu được ảnh"));
        }
    }

    [HttpGet("{id:guid}/image")]
    [ResponseCache(Duration = 3600)]
    [AllowAnonymous]
    public async Task<IActionResult> GetImage(Guid id)
    {
        var imageUrl = await dbContext.PosProductSampleCatalog.AsNoTracking()
            .Where(x => x.Id == id && x.Deleted == null)
            .Select(x => x.ImageUrl)
            .FirstOrDefaultAsync();
        if (string.IsNullOrWhiteSpace(imageUrl))
            return NotFound();

        var wwwroot = Path.GetFullPath(Path.Combine(webHostEnvironment.ContentRootPath, "wwwroot"));
        var rel = imageUrl.Trim().TrimStart('/').Replace('\\', '/');
        if (rel.StartsWith("wwwroot/", StringComparison.OrdinalIgnoreCase))
            rel = rel["wwwroot/".Length..];
        var full = Path.GetFullPath(Path.Combine(wwwroot, rel.Replace('/', Path.DirectorySeparatorChar)));
        if (!full.StartsWith(wwwroot, StringComparison.OrdinalIgnoreCase) || !System.IO.File.Exists(full))
            return NotFound();

        var ext = Path.GetExtension(full).ToLowerInvariant();
        var contentType = ext switch
        {
            ".png" => "image/png",
            ".webp" => "image/webp",
            ".gif" => "image/gif",
            _ => "image/jpeg",
        };
        return PhysicalFile(full, contentType, enableRangeProcessing: true);
    }

    [HttpPost("seed-defaults")]
    public async Task<ActionResult<AppResponse<object>>> SeedDefaults()
    {
        var created = await SeedDefaultSamplesAsync(dbContext, CurrentUserEmail);
        var enriched = await EnrichExistingSamplesAsync(dbContext, CurrentUserEmail);
        var groups = await SyncCategoriesFromSamplesAsync(dbContext, CurrentUserEmail);
        return Ok(AppResponse<object>.Success(new { created, enriched, groups }));
    }

    /// <summary>Bổ sung brand/cost/vat/description cho mẫu cũ thiếu cột mới.</summary>
    public static async Task<int> EnrichExistingSamplesAsync(ZKTecoDbContext db, string? by)
    {
        var rows = await db.PosProductSampleCatalog
            .Where(x => x.Deleted == null)
            .ToListAsync();
        if (rows.Count == 0) return 0;

        var map = new Dictionary<string, (string? brand, decimal? cost, PosProductType? type, string? desc, bool? vatExempt)>(StringComparer.OrdinalIgnoreCase)
        {
            ["Coca Cola 330ml"] = ("Coca-Cola", 7000, PosProductType.Goods, null, false),
            ["Pepsi 330ml"] = ("Pepsi", 7000, PosProductType.Goods, null, false),
            ["Sting dâu 330ml"] = ("Sting", 7500, PosProductType.Goods, null, false),
            ["Aquafina 500ml"] = ("Aquafina", 4000, PosProductType.Goods, null, false),
            ["Cơm tấm sườn"] = (null, 25000, PosProductType.Goods, null, false),
            ["Phở bò"] = (null, 30000, PosProductType.Goods, null, false),
            ["Bún chả"] = (null, 28000, PosProductType.Goods, null, false),
            ["Bánh mì thịt"] = (null, 12000, PosProductType.Goods, null, false),
            ["Gỏi cuốn"] = (null, 18000, PosProductType.Goods, null, false),
            ["Nem rán"] = (null, 15000, PosProductType.Goods, null, false),
            ["Trà sữa truyền thống"] = (null, 12000, PosProductType.Goods, null, false),
            ["Trà đào cam sả"] = (null, 14000, PosProductType.Goods, null, false),
            ["Cà phê sữa đá"] = (null, 8000, PosProductType.Goods, null, false),
            ["Cà phê đen"] = (null, 6000, PosProductType.Goods, null, false),
            ["Nước cam ép"] = (null, 15000, PosProductType.Goods, null, false),
            ["Sinh tố bơ"] = (null, 18000, PosProductType.Goods, null, false),
        };

        var n = 0;
        foreach (var row in rows)
        {
            if (!map.TryGetValue((row.Name ?? "").Trim(), out var meta)) continue;
            var changed = false;
            if (row.DefaultCostPrice is null && meta.cost is not null)
            {
                row.DefaultCostPrice = meta.cost;
                changed = true;
            }
            if (string.IsNullOrWhiteSpace(row.BrandName) && !string.IsNullOrWhiteSpace(meta.brand))
            {
                row.BrandName = meta.brand!.Trim();
                changed = true;
            }
            if (string.IsNullOrWhiteSpace(row.Description) && !string.IsNullOrWhiteSpace(meta.desc))
            {
                row.Description = meta.desc;
                changed = true;
            }
            if (changed)
            {
                row.UpdatedAt = DateTime.UtcNow;
                row.UpdatedBy = by ?? "enrich";
                n++;
            }
        }

        // Force SQL patch (tracker đôi khi không persist decimal? null → value)
        foreach (var kv in map)
        {
            var name = kv.Key;
            var cost = kv.Value.cost;
            var brand = kv.Value.brand;
            if (cost is null && string.IsNullOrWhiteSpace(brand)) continue;
            var q = db.PosProductSampleCatalog.Where(x => x.Deleted == null && x.Name == name);
            if (cost is not null)
            {
                var affected = await q.Where(x => x.DefaultCostPrice == null)
                    .ExecuteUpdateAsync(s => s
                        .SetProperty(x => x.DefaultCostPrice, cost)
                        .SetProperty(x => x.UpdatedAt, DateTime.UtcNow)
                        .SetProperty(x => x.UpdatedBy, by ?? "enrich"));
                if (affected > 0) n += affected;
            }
            if (!string.IsNullOrWhiteSpace(brand))
            {
                var affected = await db.PosProductSampleCatalog
                    .Where(x => x.Deleted == null && x.Name == name &&
                                (x.BrandName == null || x.BrandName == ""))
                    .ExecuteUpdateAsync(s => s
                        .SetProperty(x => x.BrandName, brand)
                        .SetProperty(x => x.UpdatedAt, DateTime.UtcNow)
                        .SetProperty(x => x.UpdatedBy, by ?? "enrich"));
                if (affected > 0) n += affected;
            }
        }

        foreach (var row in rows)
        {
            if (!string.IsNullOrWhiteSpace(row.SellProfiles)) continue;
            row.SellProfiles = PosSampleSellProfileHelper.Infer(row.Kind, row.ProductType, row.Name);
            row.UpdatedAt = DateTime.UtcNow;
            row.UpdatedBy = by ?? "enrich";
            n++;
        }

        var existingNames = rows
            .Select(x => x.Name)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var def in PosSampleCatalogDefaults.All())
        {
            if (existingNames.Contains(def.Name)) continue;
            db.PosProductSampleCatalog.Add(PosSampleCatalogDefaults.ToEntity(def, by ?? "enrich"));
            existingNames.Add(def.Name);
            n++;
        }

        if (n > 0) await db.SaveChangesAsync();
        return n;
    }

    public static async Task<int> SeedDefaultSamplesAsync(ZKTecoDbContext db, string? by)
    {
        if (await db.PosProductSampleCatalog.AnyAsync(x => x.Deleted == null))
            return 0;

        var entities = PosSampleCatalogDefaults.All()
            .Select(r => PosSampleCatalogDefaults.ToEntity(r, by ?? "seed"))
            .ToList();
        db.PosProductSampleCatalog.AddRange(entities);
        await db.SaveChangesAsync();
        return entities.Count;
    }

    static string? EmptyToNull(string? s)
    {
        var t = s?.Trim();
        return string.IsNullOrEmpty(t) ? null : t;
    }

    static string DefaultUnit(PosProductSampleKind kind) => kind switch
    {
        PosProductSampleKind.Food => "Phần",
        PosProductSampleKind.Drink => "Ly",
        _ => "Cái",
    };

    static string DefaultCategory(PosProductSampleKind kind) => kind switch
    {
        PosProductSampleKind.Food => "Món ăn",
        PosProductSampleKind.Drink => "Đồ uống",
        _ => "Hàng hóa",
    };
}
