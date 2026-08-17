using ClosedXML.Excel;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

public partial class PosProductsController
{
    public record BarcodeCatalogDto(
        Guid Id,
        string Barcode,
        string Name,
        string? UnitName,
        string? BrandName,
        string? CategoryName,
        string? ImageUrl);

    public record ProductQuickCreateDto(
        string? Barcode,
        string Name,
        decimal BasePrice,
        decimal CostPrice = 0,
        string? BaseUnitName = null,
        string? CategoryName = null,
        Guid? CategoryId = null,
        string? BrandName = null,
        Guid? BrandId = null,
        string? ImageUrl = null,
        string? Description = null,
        Guid? SampleCatalogId = null,
        PosProductType? ProductType = null,
        decimal? VatRate = null,
        bool? VatExempt = null);

    /// <summary>Tạo hàng hóa nhanh từ mã vạch / catalog mẫu (quét bán / menu mẫu).</summary>
    [HttpPost("quick")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<PosProductDto>>> QuickCreate([FromBody] ProductQuickCreateDto dto)
    {
        var storeId = RequiredStoreId;
        var name = (dto.Name ?? "").Trim();
        if (string.IsNullOrEmpty(name))
            return BadRequest(AppResponse<PosProductDto>.Fail("Thiếu tên hàng"));
        if (dto.BasePrice < 0)
            return BadRequest(AppResponse<PosProductDto>.Fail("Giá bán không hợp lệ"));

        PosProductSampleCatalog? sample = null;
        if (dto.SampleCatalogId.HasValue)
        {
            sample = await dbContext.PosProductSampleCatalog.AsNoTracking()
                .FirstOrDefaultAsync(x =>
                    x.Id == dto.SampleCatalogId && x.Deleted == null && x.IsActive);
            if (sample == null)
                return BadRequest(AppResponse<PosProductDto>.Fail("Không tìm thấy hàng mẫu"));
        }

        string? barcode = (dto.Barcode ?? sample?.Barcode)?.Trim();
        if (string.IsNullOrEmpty(barcode))
            barcode = null;

        if (barcode != null)
        {
            var exists = await dbContext.PosProducts.AsNoTracking().AnyAsync(p =>
                p.StoreId == storeId && p.Deleted == null && p.IsActive &&
                p.Barcode == barcode);
            if (exists)
                return BadRequest(AppResponse<PosProductDto>.Fail("Mã vạch đã có trong hàng hóa"));
        }

        Guid? categoryId = dto.CategoryId;
        if (categoryId.HasValue)
        {
            var ok = await dbContext.PosProductCategories.AsNoTracking().AnyAsync(c =>
                c.Id == categoryId && c.StoreId == storeId && c.Deleted == null);
            if (!ok) categoryId = null;
        }

        var categoryName = !string.IsNullOrWhiteSpace(dto.CategoryName)
            ? dto.CategoryName.Trim()
            : sample?.CategoryName;
        if (!categoryId.HasValue && !string.IsNullOrWhiteSpace(categoryName))
        {
            var key = categoryName.Trim().ToLower();
            var cat = await dbContext.PosProductCategories
                .FirstOrDefaultAsync(c => c.StoreId == storeId && c.Deleted == null && c.Name.ToLower() == key);
            if (cat == null)
            {
                cat = new PosProductCategory
                {
                    Id = Guid.NewGuid(),
                    StoreId = storeId,
                    Name = categoryName.Trim(),
                    IsActive = true,
                    CreatedBy = CurrentUserEmail,
                };
                dbContext.PosProductCategories.Add(cat);
            }
            categoryId = cat.Id;
        }

        Guid? brandId = dto.BrandId;
        if (brandId.HasValue)
        {
            var ok = await dbContext.PosProductBrands.AsNoTracking().AnyAsync(b =>
                b.Id == brandId && b.StoreId == storeId && b.Deleted == null);
            if (!ok) brandId = null;
        }

        var brandName = !string.IsNullOrWhiteSpace(dto.BrandName)
            ? dto.BrandName.Trim()
            : sample?.BrandName;
        if (!brandId.HasValue && !string.IsNullOrWhiteSpace(brandName))
        {
            var key = brandName.Trim().ToLower();
            var brand = await dbContext.PosProductBrands
                .FirstOrDefaultAsync(b => b.StoreId == storeId && b.Deleted == null && b.Name.ToLower() == key);
            if (brand == null)
            {
                brand = new PosProductBrand
                {
                    Id = Guid.NewGuid(),
                    StoreId = storeId,
                    Name = brandName.Trim(),
                    IsActive = true,
                    CreatedBy = CurrentUserEmail,
                };
                dbContext.PosProductBrands.Add(brand);
            }
            brandId = brand.Id;
        }

        var unit = string.IsNullOrWhiteSpace(dto.BaseUnitName)
            ? (sample?.UnitName ?? "Cái")
            : dto.BaseUnitName.Trim();
        if (string.IsNullOrWhiteSpace(unit)) unit = "Cái";

        // Ảnh dùng chung từ catalog mẫu — không upload lại lên store.
        var imageUrl = !string.IsNullOrWhiteSpace(dto.ImageUrl)
            ? NormalizeStoredImageUrl(dto.ImageUrl!)
            : sample?.ImageUrl;

        var description = !string.IsNullOrWhiteSpace(dto.Description)
            ? dto.Description.Trim()
            : sample?.Description;

        // Ưu tiên loại hàng thu ngân chọn trên form; fallback mẫu.
        var productType = dto.ProductType
            ?? sample?.ProductType
            ?? PosProductType.Goods;
        if (!Enum.IsDefined(productType))
            productType = PosProductType.Goods;

        var vatExempt = dto.VatExempt ?? sample?.VatExempt ?? false;
        var vatRate = vatExempt
            ? 0
            : Math.Clamp(dto.VatRate ?? sample?.VatRate ?? 8m, 0, 100);
        var costPrice = dto.CostPrice > 0
            ? dto.CostPrice
            : Math.Max(0, sample?.DefaultCostPrice ?? 0);

        var entity = new PosProduct
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            ProductCode = await GenerateProductCodeAsync(storeId, productType),
            Barcode = barcode,
            Name = name,
            CategoryId = categoryId,
            BrandId = brandId,
            ProductType = productType,
            Description = string.IsNullOrWhiteSpace(description) ? null : description,
            CostPrice = costPrice,
            BasePrice = dto.BasePrice,
            VatRate = vatRate,
            VatExempt = vatExempt,
            BaseUnitName = unit,
            ImageUrl = string.IsNullOrWhiteSpace(imageUrl) ? null : imageUrl.Trim(),
            IsDirectSale = productType is PosProductType.Goods or PosProductType.Service or PosProductType.Combo,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };
        if (productType == PosProductType.Topping)
        {
            entity.IsTopping = true;
            entity.IsDirectSale = false;
        }
        if (productType == PosProductType.Material)
            entity.IsDirectSale = false;
        NormalizeByProductType(entity);
        dbContext.PosProducts.Add(entity);
        if (barcode != null)
        {
            await UpsertBarcodeCatalogAsync(
                storeId, barcode, name, unit, brandName, categoryName, entity.ImageUrl);
        }
        await dbContext.SaveChangesAsync();
        await EnsureBaseUnitAsync(entity);

        var mapped = await MapProductAsync(entity.Id, storeId);
        return Ok(AppResponse<PosProductDto>.Success(mapped!));
    }

    /// <summary>Duyệt catalog mẫu Super Admin (menu món / đồ uống / hàng có mã).</summary>
    [HttpGet("sample-catalog")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> ListSampleCatalog(
        [FromQuery] string? search = null,
        [FromQuery] PosProductSampleKind? kind = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 60)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 200);
        var q = dbContext.PosProductSampleCatalog.AsNoTracking()
            .Where(x => x.Deleted == null && x.IsActive);
        if (kind.HasValue) q = q.Where(x => x.Kind == kind);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            q = q.Where(x =>
                x.Name.ToLower().Contains(s) ||
                (x.Barcode != null && x.Barcode.ToLower().Contains(s)) ||
                (x.CategoryName != null && x.CategoryName.ToLower().Contains(s)));
        }
        var total = await q.CountAsync();
        var items = await q.OrderBy(x => x.Kind).ThenBy(x => x.SortOrder).ThenBy(x => x.Name)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(x => new
            {
                x.Id,
                x.Barcode,
                x.Name,
                x.UnitName,
                x.BrandName,
                x.CategoryName,
                x.ImageUrl,
                x.Description,
                Kind = x.Kind.ToString(),
                ProductType = x.ProductType.ToString(),
                x.DefaultPrice,
                x.DefaultCostPrice,
                x.VatRate,
                x.VatExempt,
                x.SortOrder,
            })
            .ToListAsync();
        return Ok(AppResponse<object>.Success(new { total, page, pageSize, items }));
    }

    [HttpGet("sample-catalog/{id:guid}/image")]
    [ResponseCache(Duration = 3600)]
    public async Task<IActionResult> GetSampleCatalogImage(Guid id)
    {
        var imageUrl = await dbContext.PosProductSampleCatalog.AsNoTracking()
            .Where(x => x.Id == id && x.Deleted == null)
            .Select(x => x.ImageUrl)
            .FirstOrDefaultAsync();
        if (string.IsNullOrWhiteSpace(imageUrl))
            return NotFound();
        var fullPath = ResolveProductImagePath(imageUrl);
        if (fullPath == null)
            return NotFound();
        var ext = Path.GetExtension(fullPath).ToLowerInvariant();
        var contentType = ext switch
        {
            ".png" => "image/png",
            ".webp" => "image/webp",
            ".gif" => "image/gif",
            _ => "image/jpeg",
        };
        return PhysicalFile(fullPath, contentType, enableRangeProcessing: true);
    }

    [HttpGet("barcode-catalog")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> ListBarcodeCatalog(
        [FromQuery] string? search = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 200);
        var q = dbContext.PosBarcodeCatalog.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            q = q.Where(x => x.Barcode.ToLower().Contains(s) || x.Name.ToLower().Contains(s));
        }
        var total = await q.CountAsync();
        var items = await q.OrderBy(x => x.Name)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(x => new BarcodeCatalogDto(x.Id, x.Barcode, x.Name, x.UnitName, x.BrandName, x.CategoryName, x.ImageUrl))
            .ToListAsync();
        return Ok(AppResponse<object>.Success(new { total, page, pageSize, items }));
    }

    [HttpGet("barcode-catalog/template")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public IActionResult BarcodeCatalogTemplate()
    {
        using var wb = new XLWorkbook();
        var ws = wb.Worksheets.Add("Tu dien ma vach");
        var headers = new[] { "Mã vạch", "Tên hàng", "Đơn vị", "Nhóm hàng", "Thương hiệu", "Hình ảnh" };
        for (var i = 0; i < headers.Length; i++)
        {
            ws.Cell(1, i + 1).Value = headers[i];
            ws.Cell(1, i + 1).Style.Font.Bold = true;
        }
        ws.Cell(2, 1).Value = "8934588012013";
        ws.Cell(2, 2).Value = "Coca Cola 330ml";
        ws.Cell(2, 3).Value = "Lon";
        ws.Cell(2, 4).Value = "Nước giải khát";
        ws.Cell(2, 5).Value = "Coca-Cola";
        ws.Cell(2, 6).Value = "";
        ws.Cell(3, 1).Value = "8934588012020";
        ws.Cell(3, 2).Value = "Pepsi 330ml";
        ws.Cell(3, 3).Value = "Lon";
        ws.Cell(3, 4).Value = "Nước giải khát";
        ws.Cell(3, 5).Value = "Pepsi";
        ws.Cell(3, 6).Value = "";
        ws.Columns(1, 6).AdjustToContents();
        using var stream = new MemoryStream();
        wb.SaveAs(stream);
        return File(stream.ToArray(),
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "Mau_tu_dien_ma_vach.xlsx");
    }

    [HttpPost("barcode-catalog/import/excel")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Create)]
    [RequestSizeLimit(20_000_000)]
    public async Task<ActionResult<AppResponse<object>>> ImportBarcodeCatalog(IFormFile file)
    {
        if (file == null || file.Length == 0)
            return BadRequest(AppResponse<object>.Fail("File không hợp lệ"));

        List<BarcodeCatalogImportRow> rows;
        try
        {
            await using var stream = file.OpenReadStream();
            rows = PosBarcodeCatalogExcelParser.Parse(stream);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Barcode catalog import parse failed");
            return BadRequest(AppResponse<object>.Fail("Không đọc được file Excel. Cần cột Mã vạch và Tên hàng."));
        }

        if (rows.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Không có dòng hợp lệ (cần Mã vạch + Tên hàng)"));

        var storeId = RequiredStoreId;
        var existing = await dbContext.PosBarcodeCatalog
            .AsTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null)
            .ToDictionaryAsync(x => x.Barcode.ToLower(), x => x, StringComparer.OrdinalIgnoreCase);

        var created = 0;
        var updated = 0;
        foreach (var row in rows)
        {
            var key = row.Barcode.ToLower();
            if (existing.TryGetValue(key, out var entity))
            {
                entity.Name = row.Name;
                if (!string.IsNullOrWhiteSpace(row.UnitName)) entity.UnitName = row.UnitName;
                if (!string.IsNullOrWhiteSpace(row.BrandName)) entity.BrandName = row.BrandName;
                if (!string.IsNullOrWhiteSpace(row.CategoryName)) entity.CategoryName = row.CategoryName;
                if (!string.IsNullOrWhiteSpace(row.ImageUrl)) entity.ImageUrl = row.ImageUrl;
                entity.UpdatedAt = DateTime.UtcNow;
                entity.UpdatedBy = CurrentUserEmail;
                updated++;
            }
            else
            {
                entity = new PosBarcodeCatalog
                {
                    Id = Guid.NewGuid(),
                    StoreId = storeId,
                    Barcode = row.Barcode,
                    Name = row.Name,
                    UnitName = row.UnitName,
                    BrandName = row.BrandName,
                    CategoryName = row.CategoryName,
                    ImageUrl = row.ImageUrl,
                    IsActive = true,
                    CreatedBy = CurrentUserEmail,
                };
                dbContext.PosBarcodeCatalog.Add(entity);
                existing[key] = entity;
                created++;
            }
        }

        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new
        {
            created,
            updated,
            total = rows.Count,
        }));
    }

    async Task UpsertBarcodeCatalogAsync(
        Guid storeId,
        string barcode,
        string name,
        string? unitName,
        string? brandName,
        string? categoryName,
        string? imageUrl = null)
    {
        if (string.IsNullOrWhiteSpace(barcode) || string.IsNullOrWhiteSpace(name)) return;
        var key = barcode.Trim();
        var entity = await dbContext.PosBarcodeCatalog
            .AsTracking()
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.Deleted == null && x.Barcode == key);
        if (entity == null)
        {
            dbContext.PosBarcodeCatalog.Add(new PosBarcodeCatalog
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                Barcode = key,
                Name = name.Trim(),
                UnitName = string.IsNullOrWhiteSpace(unitName) ? null : unitName.Trim(),
                BrandName = string.IsNullOrWhiteSpace(brandName) ? null : brandName.Trim(),
                CategoryName = string.IsNullOrWhiteSpace(categoryName) ? null : categoryName.Trim(),
                ImageUrl = string.IsNullOrWhiteSpace(imageUrl) ? null : imageUrl.Trim(),
                IsActive = true,
                CreatedBy = CurrentUserEmail,
            });
            return;
        }
        entity.Name = name.Trim();
        if (!string.IsNullOrWhiteSpace(unitName)) entity.UnitName = unitName.Trim();
        if (!string.IsNullOrWhiteSpace(brandName)) entity.BrandName = brandName.Trim();
        if (!string.IsNullOrWhiteSpace(categoryName)) entity.CategoryName = categoryName.Trim();
        if (!string.IsNullOrWhiteSpace(imageUrl)) entity.ImageUrl = imageUrl.Trim();
        entity.UpdatedAt = DateTime.UtcNow;
        entity.UpdatedBy = CurrentUserEmail;
    }
}

internal record BarcodeCatalogImportRow(
    string Barcode,
    string Name,
    string? UnitName,
    string? BrandName,
    string? CategoryName,
    string? ImageUrl);

internal static class PosBarcodeCatalogExcelParser
{
    public static List<BarcodeCatalogImportRow> Parse(Stream stream)
    {
        using var wb = new XLWorkbook(stream);
        var ws = wb.Worksheets.First();
        var headerRow = 1;
        var lastHeader = Math.Min(8, ws.LastRowUsed()?.RowNumber() ?? 1);
        for (var r = 1; r <= lastHeader; r++)
        {
            var line = string.Join(' ', ws.Row(r).CellsUsed().Select(c => c.GetString()));
            if (LooksLikeHeader(line))
            {
                headerRow = r;
                break;
            }
        }

        int barcodeCol = -1, nameCol = -1, unitCol = -1, brandCol = -1, catCol = -1, imageCol = -1;
        const int scanCols = 12;
        for (var c = 1; c <= scanCols; c++)
        {
            var h = Norm(ws.Cell(headerRow, c).GetString());
            if (h.Length == 0) continue;
            if (barcodeCol < 0 && (h.Contains("mavach") || h.Contains("barcode") || h.Contains("ean")))
                barcodeCol = c;
            if (nameCol < 0 && (h.Contains("tenhang") || h.Contains("tensp") || h == "tensanpham" || h == "name" || h == "ten"))
                nameCol = c;
            if (unitCol < 0 && (h.Contains("donvi") || h.Contains("unit") || h == "dvt" || h.Contains("donvitinh")))
                unitCol = c;
            if (catCol < 0 && (h.Contains("nhom") || h.Contains("category") || h.Contains("loaihang")))
                catCol = c;
            if (brandCol < 0 && (h.Contains("thuonghieu") || h.Contains("brand") || h.Contains("nhanhieu")))
                brandCol = c;
            if (imageCol < 0 && (h.Contains("hinhanh") || h.Contains("image") || h == "anh" || h.Contains("photourl") || h == "url"))
                imageCol = c;
        }

        if (barcodeCol < 0) barcodeCol = 1;
        if (nameCol < 0) nameCol = 2;
        if (unitCol < 0 && ws.Cell(headerRow, 3).GetString().Trim().Length > 0) unitCol = 3;
        if (catCol < 0 && ws.Cell(headerRow, 4).GetString().Trim().Length > 0) catCol = 4;
        if (brandCol < 0 && ws.Cell(headerRow, 5).GetString().Trim().Length > 0) brandCol = 5;
        if (imageCol < 0 && ws.Cell(headerRow, 6).GetString().Trim().Length > 0) imageCol = 6;

        var lastRow = ws.LastRowUsed()?.RowNumber() ?? headerRow;
        var rows = new List<BarcodeCatalogImportRow>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        for (var r = headerRow + 1; r <= lastRow; r++)
        {
            var barcode = ws.Cell(r, barcodeCol).GetString().Trim();
            var name = ws.Cell(r, nameCol).GetString().Trim();
            if (barcode.Length == 0 || name.Length == 0) continue;
            if (!seen.Add(barcode)) continue;
            rows.Add(new BarcodeCatalogImportRow(
                barcode,
                name,
                unitCol > 0 ? EmptyToNull(ws.Cell(r, unitCol).GetString()) : null,
                brandCol > 0 ? EmptyToNull(ws.Cell(r, brandCol).GetString()) : null,
                catCol > 0 ? EmptyToNull(ws.Cell(r, catCol).GetString()) : null,
                imageCol > 0 ? EmptyToNull(ws.Cell(r, imageCol).GetString()) : null));
        }
        return rows;
    }

    static bool LooksLikeHeader(string line)
    {
        var n = Norm(line);
        return n.Contains("mavach") || n.Contains("barcode") || n.Contains("tenhang");
    }

    static string Norm(string s)
    {
        var form = s.Trim().ToLowerInvariant().Normalize(System.Text.NormalizationForm.FormD);
        var chars = form.Where(c => System.Globalization.CharUnicodeInfo.GetUnicodeCategory(c)
            != System.Globalization.UnicodeCategory.NonSpacingMark).ToArray();
        return new string(chars)
            .Replace(" ", "")
            .Replace("_", "")
            .Replace('\u0111', 'd')
            .Replace('\u0110', 'd')
            .Replace("đ", "d")
            .Replace("Đ", "d");
    }

    static string? EmptyToNull(string s)
    {
        var t = s.Trim();
        return t.Length == 0 ? null : t;
    }
}
