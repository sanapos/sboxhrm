using System.Globalization;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

public sealed record MenuSizeDto(string Name, decimal Price);

/// <summary>Một món đọc được từ ảnh menu (người dùng sửa trên màn xem trước rồi gửi lại để tạo hàng).</summary>
public sealed record MenuItemDto(
    string Name,
    string? Category,
    decimal Price,
    List<MenuSizeDto> Sizes,
    string? Unit,
    string? Description,
    string? ImageUrl,
    Guid? SampleCatalogId,
    string? SampleCatalogName,
    Guid? ExistingProductId,
    string? ExistingProductName);

public sealed record MenuScanResultDto(List<MenuItemDto> Items, List<string> Categories, int CatalogSize);

public sealed record MenuImportResultDto(int CategoriesCreated, int ProductsCreated, int VariantsCreated, List<string> Skipped);

/// <summary>
/// Chụp ảnh menu → Gemini đọc tên món / nhóm / giá / size, đồng thời chọn món khớp trong
/// catalog mẫu (PosProductSampleCatalog) để gắn ảnh → tạo nhóm hàng, hàng hóa, biến thể size.
/// </summary>
public sealed class PosAiMenuService(ZKTecoDbContext db, IGeminiAiService gemini)
{
    public const int MaxImages = 8;
    public const long MaxTotalBytes = 15 * 1024 * 1024; // Gemini inline ~20 MB / request (base64 +33%).
    const int MaxCatalogInPrompt = 600;

    const string SystemPrompt = """
        Bạn đọc ảnh chụp MENU quán ăn / quán nước / cửa hàng tại Việt Nam và trích xuất danh sách món.
        Quy tắc:
        - Mỗi món: tên đúng như menu (giữ tiếng Việt có dấu, sửa lỗi chính tả rõ ràng), nhóm (tiêu đề mục trên menu, vd "Cà phê", "Trà sữa", "Món chính"), giá bán.
        - Giá là số nguyên VND: "35k" = 35000, "35" (menu ghi đơn vị nghìn) = 35000, "1.2tr" = 1200000.
        - Món có nhiều size / cỡ (S/M/L, nhỏ/vừa/lớn, ly/chai...) → "sizes" gồm tên size và giá từng size; "price" = giá size nhỏ nhất.
        - Món một giá → "sizes": [].
        - "unit": đơn vị bán ngắn gọn đoán theo món: "Ly" (đồ uống pha), "Chai"/"Lon" (đóng chai), "Phần"/"Tô"/"Đĩa" (món ăn), "Cái"...
        - Bỏ qua tiêu đề, khẩu hiệu, địa chỉ, số điện thoại, wifi; không bịa món không có trên ảnh.
        - "catalogIndex": số thứ tự món trong DANH MỤC MẪU cùng là một món (cùng loại đồ uống / món ăn, khác cách viết vẫn tính), không chắc thì null.
        Chỉ trả JSON đúng schema:
        {"items":[{"name":"","category":"","price":0,"sizes":[{"name":"","price":0}],"unit":"Ly","description":null,"catalogIndex":null}]}
        """;

    public async Task<MenuScanResultDto> ScanAsync(Guid storeId, IReadOnlyList<AiFilePart> images, CancellationToken ct)
    {
        var catalog = await db.PosProductSampleCatalog.AsNoTracking()
            .Where(x => x.Deleted == null && x.IsActive)
            .OrderBy(x => x.SortOrder).ThenBy(x => x.Name)
            .Take(MaxCatalogInPrompt)
            .Select(x => new { x.Id, x.Name, x.CategoryName, x.ImageUrl })
            .ToListAsync(ct);

        var prompt = new StringBuilder("Đọc các ảnh menu đính kèm.\n\nDANH MỤC MẪU (số thứ tự | tên | nhóm):\n");
        for (var i = 0; i < catalog.Count; i++)
            prompt.Append(i).Append(" | ").Append(catalog[i].Name).Append(" | ").Append(catalog[i].CategoryName).Append('\n');
        if (catalog.Count == 0) prompt.Append("(trống — catalogIndex luôn null)\n");

        var json = await gemini.GenerateJsonAsync(SystemPrompt, prompt.ToString(), images, 32768, ct);
        var raw = Parse(json);

        var existing = await db.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null)
            .Select(p => new { p.Id, p.Name })
            .ToListAsync(ct);
        var existingByKey = existing
            .GroupBy(p => NameKey(p.Name))
            .ToDictionary(g => g.Key, g => g.First());

        var items = new List<MenuItemDto>();
        var seen = new HashSet<string>();
        foreach (var r in raw)
        {
            var name = (r.Name ?? "").Trim();
            if (name.Length == 0 || !seen.Add(NameKey(name) + "|" + NameKey(r.Category))) continue;
            var sizes = (r.Sizes ?? [])
                .Where(s => !string.IsNullOrWhiteSpace(s.Name))
                .Select(s => new MenuSizeDto(s.Name!.Trim(), Math.Max(0, s.Price)))
                .DistinctBy(s => NameKey(s.Name))
                .ToList();
            if (sizes.Count == 1) sizes.Clear(); // 1 size = món một giá
            var price = sizes.Count > 0 ? sizes.Min(s => s.Price) : Math.Max(0, r.Price);

            // Chỉ nhận index AI trả về nếu có thật; không có thì thử trùng tên tuyệt đối.
            var match = r.CatalogIndex is int ci && ci >= 0 && ci < catalog.Count ? catalog[ci] : null;
            match ??= catalog.FirstOrDefault(c => NameKey(c.Name) == NameKey(name));
            existingByKey.TryGetValue(NameKey(name), out var dup);

            items.Add(new MenuItemDto(
                name,
                string.IsNullOrWhiteSpace(r.Category) ? null : r.Category.Trim(),
                price,
                sizes,
                string.IsNullOrWhiteSpace(r.Unit) ? null : r.Unit.Trim(),
                string.IsNullOrWhiteSpace(r.Description) ? null : r.Description.Trim(),
                string.IsNullOrWhiteSpace(match?.ImageUrl) ? null : match!.ImageUrl,
                match?.Id,
                match?.Name,
                dup?.Id,
                dup?.Name));
        }

        var categories = items.Select(i => i.Category).Where(c => c != null).Cast<string>()
            .Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        return new MenuScanResultDto(items, categories, catalog.Count);
    }

    /// <summary>
    /// Tạo nhóm hàng / hàng hóa / biến thể size. Món khớp catalog mẫu lấy loại hàng, đơn vị, VAT
    /// của mẫu (giống thêm hàng từ mẫu); không khớp → hàng hóa, đơn vị AI đoán.
    /// </summary>
    public async Task<MenuImportResultDto> ImportAsync(Guid storeId, IReadOnlyList<MenuItemDto> items, string? actor, CancellationToken ct)
    {
        var skipped = new List<string>();
        var sampleIds = items.Where(i => i.SampleCatalogId != null).Select(i => i.SampleCatalogId!.Value).Distinct().ToList();
        var samples = await db.PosProductSampleCatalog.AsNoTracking()
            .Where(x => sampleIds.Contains(x.Id))
            .ToDictionaryAsync(x => x.Id, ct);
        var categories = await db.PosProductCategories.AsTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null)
            .ToListAsync(ct);
        var catByKey = categories.GroupBy(c => NameKey(c.Name)).ToDictionary(g => g.Key, g => g.First().Id);
        var existingNames = (await db.PosProducts.AsNoTracking()
                .Where(p => p.StoreId == storeId && p.Deleted == null)
                .Select(p => p.Name).ToListAsync(ct))
            .Select(NameKey).ToHashSet();
        var usedCodes = (await db.PosProducts.IgnoreQueryFilters().AsNoTracking()
                .Where(p => p.StoreId == storeId)
                .Select(p => p.ProductCode).ToListAsync(ct))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var usedSkus = (await db.PosProductVariants.IgnoreQueryFilters().AsNoTracking()
                .Where(v => v.StoreId == storeId)
                .Select(v => v.SkuCode).ToListAsync(ct))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        var nextNo = 1;
        string NextCode()
        {
            string code;
            do code = $"HH{nextNo++:D5}"; while (usedCodes.Contains(code));
            usedCodes.Add(code);
            return code;
        }

        int catsCreated = 0, productsCreated = 0, variantsCreated = 0;
        var sort = 0;
        foreach (var item in items)
        {
            var name = (item.Name ?? "").Trim();
            if (name.Length == 0) continue;
            if (!existingNames.Add(NameKey(name)))
            {
                skipped.Add($"{name} (đã có)");
                continue;
            }

            Guid? categoryId = null;
            if (!string.IsNullOrWhiteSpace(item.Category))
            {
                var key = NameKey(item.Category);
                if (!catByKey.TryGetValue(key, out var cid))
                {
                    var cat = new PosProductCategory
                    {
                        Id = Guid.NewGuid(), StoreId = storeId, Name = item.Category.Trim(),
                        IsActive = true, CreatedBy = actor,
                    };
                    db.PosProductCategories.Add(cat);
                    catByKey[key] = cid = cat.Id;
                    catsCreated++;
                }
                categoryId = cid;
            }

            var sizes = (item.Sizes ?? []).Where(s => !string.IsNullOrWhiteSpace(s.Name)).ToList();
            var basePrice = sizes.Count > 0 ? sizes.Min(s => s.Price) : item.Price;
            PosProductSampleCatalog? sample = null;
            if (item.SampleCatalogId is Guid sid) samples.TryGetValue(sid, out sample);
            var type = sample?.ProductType is PosProductType t && t is PosProductType.Goods or PosProductType.Service or PosProductType.Topping
                ? t
                : PosProductType.Goods;
            var unit = !string.IsNullOrWhiteSpace(item.Unit) ? item.Unit.Trim()
                : !string.IsNullOrWhiteSpace(sample?.UnitName) ? sample!.UnitName!.Trim()
                : "Phần";
            var code = NextCode();
            var product = new PosProduct
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                ProductCode = code,
                Name = name,
                CategoryId = categoryId,
                ProductType = type,
                BasePrice = basePrice,
                CostPrice = Math.Max(0, sample?.DefaultCostPrice ?? 0),
                VatRate = sample?.VatExempt == true ? 0 : sample?.VatRate ?? 8,
                VatExempt = sample?.VatExempt ?? false,
                BaseUnitName = unit,
                IsDirectSale = type != PosProductType.Topping,
                IsTopping = type == PosProductType.Topping,
                Description = item.Description ?? sample?.Description,
                ImageUrl = string.IsNullOrWhiteSpace(item.ImageUrl) ? null : item.ImageUrl.Trim(),
                SortOrder = sort++,
                IsActive = true,
                CreatedBy = actor,
            };
            db.PosProducts.Add(product);
            db.PosProductUnits.Add(new PosProductUnit
            {
                Id = Guid.NewGuid(), StoreId = storeId, ProductId = product.Id,
                UnitName = unit, ConversionRate = 1, BasePrice = basePrice,
                IsDirectSale = product.IsDirectSale, IsBaseUnit = true, IsActive = true, CreatedBy = actor,
            });
            productsCreated++;

            foreach (var size in sizes)
            {
                var sku = $"{code}-{Slug(size.Name)}";
                for (var n = 2; !usedSkus.Add(sku); n++) sku = $"{code}-{Slug(size.Name)}{n}";
                db.PosProductVariants.Add(new PosProductVariant
                {
                    Id = Guid.NewGuid(), StoreId = storeId, ProductId = product.Id,
                    SkuCode = sku,
                    Name = size.Name.Trim(),
                    AttributeJson = JsonSerializer.Serialize(new Dictionary<string, string> { ["Size"] = size.Name.Trim() }),
                    BasePrice = size.Price,
                    IsActive = true,
                    CreatedBy = actor,
                });
                variantsCreated++;
            }
        }

        await db.SaveChangesAsync(ct);
        return new MenuImportResultDto(catsCreated, productsCreated, variantsCreated, skipped);
    }

    sealed class RawSize
    {
        public string? Name { get; set; }
        public decimal Price { get; set; }
    }

    sealed class RawItem
    {
        public string? Name { get; set; }
        public string? Category { get; set; }
        public decimal Price { get; set; }
        public List<RawSize>? Sizes { get; set; }
        public string? Unit { get; set; }
        public string? Description { get; set; }
        public int? CatalogIndex { get; set; }
    }

    sealed class RawMenu
    {
        public List<RawItem>? Items { get; set; }
    }

    static List<RawItem> Parse(string json)
    {
        var opts = new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true,
            NumberHandling = System.Text.Json.Serialization.JsonNumberHandling.AllowReadingFromString,
        };
        try
        {
            return JsonSerializer.Deserialize<RawMenu>(json, opts)?.Items ?? [];
        }
        catch (JsonException)
        {
            // Một số model trả mảng trần.
            return JsonSerializer.Deserialize<List<RawItem>>(json, opts) ?? [];
        }
    }

    /// <summary>So tên không phân biệt dấu / hoa thường / khoảng trắng.</summary>
    public static string NameKey(string? s)
    {
        if (string.IsNullOrWhiteSpace(s)) return "";
        var sb = new StringBuilder();
        foreach (var ch in s.Trim().ToLowerInvariant().Normalize(NormalizationForm.FormD))
        {
            if (CharUnicodeInfo.GetUnicodeCategory(ch) == UnicodeCategory.NonSpacingMark) continue;
            var c = ch == 'đ' ? 'd' : ch;
            if (char.IsLetterOrDigit(c)) sb.Append(c);
        }
        return sb.ToString();
    }

    static string Slug(string s)
    {
        var k = NameKey(s).ToUpperInvariant();
        return k.Length == 0 ? "SZ" : (k.Length > 8 ? k[..8] : k);
    }
}
