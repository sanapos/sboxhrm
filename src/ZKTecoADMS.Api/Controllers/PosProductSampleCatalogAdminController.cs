using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Super Admin — catalog hàng mẫu / menu món (ảnh dùng chung toàn hệ thống).</summary>
[Authorize(Roles = nameof(Roles.SuperAdmin))]
[Route("api/system-admin/pos-sample-catalog")]
public class PosProductSampleCatalogAdminController(
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
        string? ImageUrl,
        string? Description,
        string Kind,
        string ProductType,
        decimal? DefaultPrice,
        decimal? DefaultCostPrice,
        decimal VatRate,
        bool VatExempt,
        int SortOrder,
        bool IsActive);

    public record SampleUpsertDto(
        string? Barcode,
        string Name,
        string? UnitName,
        string? BrandName,
        string? CategoryName,
        string? Description = null,
        PosProductSampleKind Kind = PosProductSampleKind.Packaged,
        PosProductType ProductType = PosProductType.Goods,
        decimal? DefaultPrice = null,
        decimal? DefaultCostPrice = null,
        decimal? VatRate = null,
        bool VatExempt = false,
        int SortOrder = 0,
        bool IsActive = true);

    static SampleDto Map(PosProductSampleCatalog x) => new(
        x.Id, x.Barcode, x.Name, x.UnitName, x.BrandName, x.CategoryName, x.ImageUrl, x.Description,
        x.Kind.ToString(), x.ProductType.ToString(), x.DefaultPrice, x.DefaultCostPrice,
        x.VatRate, x.VatExempt, x.SortOrder, x.IsActive);

    [HttpGet]
    public async Task<ActionResult<AppResponse<object>>> List(
        [FromQuery] string? search = null,
        [FromQuery] PosProductSampleKind? kind = null,
        [FromQuery] PosProductType? productType = null,
        [FromQuery] bool includeInactive = false,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 200);
        var q = dbContext.PosProductSampleCatalog.AsNoTracking()
            .Where(x => x.Deleted == null);
        if (!includeInactive) q = q.Where(x => x.IsActive);
        if (kind.HasValue) q = q.Where(x => x.Kind == kind);
        if (productType.HasValue) q = q.Where(x => x.ProductType == productType);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            q = q.Where(x =>
                x.Name.ToLower().Contains(s) ||
                (x.Barcode != null && x.Barcode.ToLower().Contains(s)) ||
                (x.CategoryName != null && x.CategoryName.ToLower().Contains(s)) ||
                (x.BrandName != null && x.BrandName.ToLower().Contains(s)));
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
            CreatedBy = CurrentUserEmail,
        };
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
        entity.CategoryName = EmptyToNull(dto.CategoryName);
        entity.Description = EmptyToNull(dto.Description);
        entity.Kind = dto.Kind;
        entity.ProductType = productType;
        entity.DefaultPrice = dto.DefaultPrice is > 0 ? dto.DefaultPrice : null;
        entity.DefaultCostPrice = dto.DefaultCostPrice is > 0 ? dto.DefaultCostPrice : null;
        entity.VatRate = vatRate;
        entity.VatExempt = vatExempt;
        entity.SortOrder = dto.SortOrder;
        entity.IsActive = dto.IsActive;
        entity.UpdatedAt = DateTime.UtcNow;
        entity.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<SampleDto>.Success(Map(entity)));
    }

    [HttpDelete("{id:guid}")]
    public async Task<ActionResult<AppResponse<object>>> Delete(Guid id)
    {
        var entity = await dbContext.PosProductSampleCatalog
            .FirstOrDefaultAsync(x => x.Id == id && x.Deleted == null);
        if (entity == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy mẫu"));
        entity.Deleted = DateTime.UtcNow;
        entity.DeletedBy = CurrentUserEmail;
        entity.IsActive = false;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { id }));
    }

    [HttpPost("{id:guid}/image")]
    [RequestSizeLimit(10_000_000)]
    [Consumes("multipart/form-data")]
    public async Task<ActionResult<AppResponse<object>>> UploadImage(Guid id, [FromForm] IFormFile? file)
    {
        if (file == null || file.Length == 0)
            return BadRequest(AppResponse<object>.Fail("Chưa chọn ảnh"));

        var entity = await dbContext.PosProductSampleCatalog
            .FirstOrDefaultAsync(x => x.Id == id && x.Deleted == null);
        if (entity == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy mẫu"));

        var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
        if (ext is not (".jpg" or ".jpeg" or ".png" or ".webp" or ".gif" or ".jfif"))
            ext = ".jpg";

        try
        {
            await using var raw = file.OpenReadStream();
            var (optimized, uploadName, _) = await ImageOptimizeHelper.OptimizeAsync(
                raw,
                $"{id:N}{ext}",
                ImageOptimizeHelper.ProductMaxEdge,
                ImageOptimizeHelper.ProductJpegQuality);
            await using (optimized)
            {
                var path = await fileStorageService.UploadAsync(
                    optimized, uploadName, "catalog/pos-samples");
                var imagePath = path.TrimStart('/');
                entity.ImageUrl = imagePath;
                entity.UpdatedAt = DateTime.UtcNow;
                entity.UpdatedBy = CurrentUserEmail;
                await dbContext.SaveChangesAsync();
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
        return Ok(AppResponse<object>.Success(new { created, enriched }));
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

        // Thêm mẫu loại DV/TP/NVL/CB nếu chưa có
        async Task EnsureExtra(PosProductSampleKind kind, PosProductType type, string name, string unit, string cat,
            decimal? price, decimal? cost, bool vatExempt = false, string? desc = null, int sort = 50)
        {
            if (await db.PosProductSampleCatalog.AnyAsync(x => x.Deleted == null && x.Name == name))
                return;
            db.PosProductSampleCatalog.Add(new PosProductSampleCatalog
            {
                Id = Guid.NewGuid(),
                Kind = kind,
                ProductType = type,
                Name = name,
                UnitName = unit,
                CategoryName = cat,
                DefaultPrice = price,
                DefaultCostPrice = cost,
                VatRate = vatExempt ? 0 : 8,
                VatExempt = vatExempt,
                Description = desc,
                SortOrder = sort,
                IsActive = true,
                CreatedBy = by ?? "enrich",
            });
            n++;
        }

        await EnsureExtra(PosProductSampleKind.Food, PosProductType.Service, "Phí giao hàng", "Lần", "Dịch vụ", 15000, 0, desc: "Phí ship nội thành", sort: 10);
        await EnsureExtra(PosProductSampleKind.Drink, PosProductType.Topping, "Trân châu đen", "Phần", "Topping", 5000, 2000, sort: 11);
        await EnsureExtra(PosProductSampleKind.Drink, PosProductType.Topping, "Thạch rau câu", "Phần", "Topping", 5000, 1500, sort: 12);
        await EnsureExtra(PosProductSampleKind.Food, PosProductType.Material, "Gạo tấm", "Kg", "Nguyên liệu", 0, 18000, vatExempt: true, desc: "NVL — không bán trực tiếp", sort: 13);
        await EnsureExtra(PosProductSampleKind.Food, PosProductType.Combo, "Combo cơm + nước", "Suất", "Combo", 59000, 32000, desc: "Combo mẫu", sort: 14);

        if (n > 0) await db.SaveChangesAsync();
        return n;
    }

    public static async Task<int> SeedDefaultSamplesAsync(ZKTecoDbContext db, string? by)
    {
        if (await db.PosProductSampleCatalog.AnyAsync(x => x.Deleted == null))
            return 0;

        var rows = new List<PosProductSampleCatalog>();
        void Add(
            PosProductSampleKind kind,
            PosProductType type,
            string name,
            string unit,
            string cat,
            string? barcode = null,
            decimal? price = null,
            decimal? cost = null,
            string? brand = null,
            decimal vat = 8,
            bool vatExempt = false,
            int sort = 0,
            string? desc = null)
        {
            rows.Add(new PosProductSampleCatalog
            {
                Id = Guid.NewGuid(),
                Kind = kind,
                ProductType = type,
                Name = name,
                UnitName = unit,
                CategoryName = cat,
                BrandName = brand,
                Barcode = barcode,
                DefaultPrice = price,
                DefaultCostPrice = cost,
                VatRate = vatExempt ? 0 : vat,
                VatExempt = vatExempt,
                Description = desc,
                SortOrder = sort,
                IsActive = true,
                CreatedBy = by ?? "seed",
            });
        }

        // Hàng hóa đóng gói
        Add(PosProductSampleKind.Packaged, PosProductType.Goods, "Coca Cola 330ml", "Lon", "Nước giải khát",
            "8934588012013", 10000, 7000, "Coca-Cola", sort: 1);
        Add(PosProductSampleKind.Packaged, PosProductType.Goods, "Pepsi 330ml", "Lon", "Nước giải khát",
            "8934588012020", 10000, 7000, "Pepsi", sort: 2);
        Add(PosProductSampleKind.Packaged, PosProductType.Goods, "Sting dâu 330ml", "Lon", "Nước giải khát",
            "8934588012037", 11000, 7500, "Sting", sort: 3);
        Add(PosProductSampleKind.Packaged, PosProductType.Goods, "Aquafina 500ml", "Chai", "Nước suối",
            "8934588060014", 7000, 4000, "Aquafina", sort: 4);

        // Món / đồ uống F&B
        Add(PosProductSampleKind.Food, PosProductType.Goods, "Cơm tấm sườn", "Phần", "Món chính",
            price: 45000, cost: 25000, sort: 1);
        Add(PosProductSampleKind.Food, PosProductType.Goods, "Phở bò", "Tô", "Món chính",
            price: 55000, cost: 30000, sort: 2);
        Add(PosProductSampleKind.Food, PosProductType.Goods, "Bún chả", "Suất", "Món chính",
            price: 50000, cost: 28000, sort: 3);
        Add(PosProductSampleKind.Food, PosProductType.Goods, "Bánh mì thịt", "Cái", "Ăn nhanh",
            price: 25000, cost: 12000, sort: 4);
        Add(PosProductSampleKind.Food, PosProductType.Goods, "Gỏi cuốn", "Phần", "Khai vị",
            price: 35000, cost: 18000, sort: 5);
        Add(PosProductSampleKind.Food, PosProductType.Goods, "Nem rán", "Phần", "Khai vị",
            price: 30000, cost: 15000, sort: 6);

        Add(PosProductSampleKind.Drink, PosProductType.Goods, "Trà sữa truyền thống", "Ly", "Trà sữa",
            price: 30000, cost: 12000, sort: 1);
        Add(PosProductSampleKind.Drink, PosProductType.Goods, "Trà đào cam sả", "Ly", "Trà trái cây",
            price: 35000, cost: 14000, sort: 2);
        Add(PosProductSampleKind.Drink, PosProductType.Goods, "Cà phê sữa đá", "Ly", "Cà phê",
            price: 25000, cost: 8000, sort: 3);
        Add(PosProductSampleKind.Drink, PosProductType.Goods, "Cà phê đen", "Ly", "Cà phê",
            price: 20000, cost: 6000, sort: 4);
        Add(PosProductSampleKind.Drink, PosProductType.Goods, "Nước cam ép", "Ly", "Nước ép",
            price: 35000, cost: 15000, sort: 5);
        Add(PosProductSampleKind.Drink, PosProductType.Goods, "Sinh tố bơ", "Ly", "Sinh tố",
            price: 40000, cost: 18000, sort: 6);

        // Dịch vụ / topping / NVL / combo mẫu
        Add(PosProductSampleKind.Food, PosProductType.Service, "Phí giao hàng", "Lần", "Dịch vụ",
            price: 15000, cost: 0, vat: 8, sort: 10, desc: "Phí ship nội thành");
        Add(PosProductSampleKind.Drink, PosProductType.Topping, "Trân châu đen", "Phần", "Topping",
            price: 5000, cost: 2000, sort: 11);
        Add(PosProductSampleKind.Drink, PosProductType.Topping, "Thạch rau câu", "Phần", "Topping",
            price: 5000, cost: 1500, sort: 12);
        Add(PosProductSampleKind.Food, PosProductType.Material, "Gạo tấm", "Kg", "Nguyên liệu",
            price: 0, cost: 18000, vatExempt: true, sort: 13, desc: "NVL — không bán trực tiếp");
        Add(PosProductSampleKind.Food, PosProductType.Combo, "Combo cơm + nước", "Suất", "Combo",
            price: 59000, cost: 32000, sort: 14, desc: "Combo mẫu");

        db.PosProductSampleCatalog.AddRange(rows);
        await db.SaveChangesAsync();
        return rows.Count;
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
