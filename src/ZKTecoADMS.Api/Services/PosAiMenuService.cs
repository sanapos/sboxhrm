using System.Globalization;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

public sealed record MenuSizeDto(string Name, decimal Price);

/// <summary>Thành phần combo đọc từ menu (tên món như trên menu).</summary>
public sealed record MenuComboPartDto(string Name, decimal Qty);

/// <summary>Một món đọc được từ ảnh menu (người dùng sửa trên màn xem trước rồi gửi lại để tạo hàng).</summary>
/// <param name="ProductType">Tên <see cref="PosProductType"/> (Goods / Service / Combo / Topping / Material). Null = theo mẫu / hàng hóa.</param>
/// <param name="Billing">Tên <see cref="PosServiceBillingMode"/> cho dịch vụ (Flat / PerHour / PerSession / PerDay).</param>
/// <param name="SessionCount">Số buổi khi dịch vụ bán theo gói buổi.</param>
/// <param name="ToppingFor">Topping: tên nhóm hàng / tên món được gắn topping này. Rỗng = mọi món trong lần nhập.</param>
/// <param name="ComboItems">Combo: các món thành phần.</param>
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
    string? ExistingProductName,
    string? ProductType = null,
    string? Billing = null,
    int SessionCount = 0,
    List<string>? ToppingFor = null,
    List<MenuComboPartDto>? ComboItems = null);

public sealed record MenuScanResultDto(List<MenuItemDto> Items, List<string> Categories, int CatalogSize);

public sealed record MenuImportResultDto(
    int CategoriesCreated,
    int ProductsCreated,
    int VariantsCreated,
    List<string> Skipped,
    int ToppingGroupsCreated = 0,
    int ToppingLinksCreated = 0,
    int CombosCreated = 0,
    List<string>? Warnings = null);

/// <summary>
/// Chụp ảnh menu → Gemini đọc tên món / nhóm / giá / size / loại hàng, đồng thời chọn món khớp trong
/// catalog mẫu (PosProductSampleCatalog) để gắn ảnh → tạo nhóm hàng, hàng hóa, dịch vụ, combo,
/// biến thể size, nhóm topping gắn vào món.
/// </summary>
public sealed class PosAiMenuService(ZKTecoDbContext db, IGeminiAiService gemini)
{
    public const int MaxImages = 8;
    public const long MaxTotalBytes = 15 * 1024 * 1024; // Gemini inline ~20 MB / request (base64 +33%).
    const int MaxCatalogInPrompt = 600;
    const string DefaultToppingGroup = "Topping";

    const string SystemPrompt = """
        Bạn đọc ảnh chụp MENU / BẢNG GIÁ quán ăn, quán nước, spa, salon, karaoke, bi-a, phòng tập, cửa hàng tại Việt Nam và trích xuất danh sách món.
        Quy tắc:
        - Mỗi món: tên đúng như menu (giữ tiếng Việt có dấu, sửa lỗi chính tả rõ ràng), nhóm (tiêu đề mục trên menu, vd "Cà phê", "Trà sữa", "Topping", "Massage"), giá bán.
        - Giá là số nguyên VND: "35k" = 35000, "35" (menu ghi đơn vị nghìn) = 35000, "1.2tr" = 1200000.
        - Món có nhiều size / cỡ (S/M/L, nhỏ/vừa/lớn, ly/chai...) → "sizes" gồm tên size và giá từng size; "price" = giá size nhỏ nhất. Size không ghi giá → price 0.
        - Món một giá → "sizes": [].
        - "type" — loại hàng:
          "goods": món ăn, đồ uống, hàng bán (mặc định);
          "service": dịch vụ làm cho khách / thuê theo thời gian: cắt tóc, gội, nail, massage, spa, liệu trình, giờ hát karaoke, giờ bàn bi-a, phòng, gói tập, phí giao hàng...;
          "combo": combo / set / suất gồm nhiều món khác trên menu ("Combo 1: cơm + nước");
          "topping": món chỉ thêm vào món khác: trân châu, thạch, pudding, kem cheese, shot espresso thêm, thêm trứng, thêm thịt... (mục "Topping", "Món thêm", "Thêm", hoặc ghi "+5k");
          "material": nguyên liệu (chỉ khi ảnh là bảng nguyên liệu, không phải menu bán).
        - "billing" (chỉ dịch vụ): "hour" nếu giá theo giờ ("/giờ", "/h", "1 giờ"), "day" nếu theo ngày / đêm, "session" nếu là gói nhiều buổi (kèm "sessions" = số buổi), còn lại "flat". Món không phải dịch vụ: "flat".
        - "unit": đơn vị bán ngắn gọn: "Ly" (đồ uống pha), "Chai"/"Lon" (đóng chai), "Phần"/"Tô"/"Đĩa" (món ăn), "Lần" (dịch vụ), "Giờ" (tính giờ), "Gói", "Suất" (combo), "Cái"...
        - "toppingFor" (chỉ topping): tên các NHÓM món trên menu dùng kèm topping này (theo menu ghi; menu không ghi thì chọn các nhóm hợp lý, vd topping trà sữa → các nhóm trà sữa / trà trái cây). Món khác: [].
        - "comboItems" (chỉ combo): các món thành phần, tên đúng như món trên menu, kèm số lượng. Món khác: [].
        - Bỏ qua tiêu đề, khẩu hiệu, địa chỉ, số điện thoại, wifi; không bịa món không có trên ảnh.
        - "catalogIndex": số thứ tự món trong DANH MỤC MẪU cùng là một món (cùng loại đồ uống / món ăn / dịch vụ, khác cách viết vẫn tính), không chắc thì null.
        Chỉ trả JSON đúng schema:
        {"items":[{"name":"","category":"","price":0,"sizes":[{"name":"","price":0}],"unit":"Ly","type":"goods","billing":"flat","sessions":0,"toppingFor":[],"comboItems":[{"name":"","qty":1}],"description":null,"catalogIndex":null}]}
        """;

    public async Task<MenuScanResultDto> ScanAsync(Guid storeId, IReadOnlyList<AiFilePart> images, CancellationToken ct)
    {
        var catalog = await db.PosProductSampleCatalog.AsNoTracking()
            .Where(x => x.Deleted == null && x.IsActive)
            .OrderBy(x => x.SortOrder).ThenBy(x => x.Name)
            .Take(MaxCatalogInPrompt)
            .Select(x => new { x.Id, x.Name, x.CategoryName, x.ImageUrl, x.ProductType, x.ServiceBillingMode, x.SessionPackCount })
            .ToListAsync(ct);

        var prompt = new StringBuilder("Đọc các ảnh menu đính kèm.\n\nDANH MỤC MẪU (số thứ tự | tên | nhóm):\n");
        for (var i = 0; i < catalog.Count; i++)
            prompt.Append(i).Append(" | ").Append(catalog[i].Name).Append(" | ").Append(catalog[i].CategoryName).Append('\n');
        if (catalog.Count == 0) prompt.Append("(trống — catalogIndex luôn null)\n");

        // AI thêm menu: mọi cửa hàng được dùng khóa AI chung (ưu tiên khóa riêng).
        var json = await gemini.AllowSharedKey().GenerateJsonAsync(SystemPrompt, prompt.ToString(), images, 32768, ct);
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
            // Size thiếu giá vẫn giữ (giá 0) để màn xem trước báo cho người dùng điền.
            var (price, sizes) = NormalizePrice(r.Price, (r.Sizes ?? []).Select(s => new MenuSizeDto(s.Name ?? "", s.Price)));

            // Chỉ nhận index AI trả về nếu có thật; không có thì thử trùng tên tuyệt đối.
            var match = r.CatalogIndex is int ci && ci >= 0 && ci < catalog.Count ? catalog[ci] : null;
            match ??= catalog.FirstOrDefault(c => NameKey(c.Name) == NameKey(name));
            existingByKey.TryGetValue(NameKey(name), out var dup);

            // AI đọc loại theo ngữ cảnh menu; AI không trả thì lấy loại của món mẫu.
            var type = ParseAiType(r.Type) ?? match?.ProductType ?? PosProductType.Goods;
            var billing = type == PosProductType.Service
                ? ParseAiBilling(r.Billing) ?? match?.ServiceBillingMode ?? PosServiceBillingMode.Flat
                : PosServiceBillingMode.Flat;
            var sessions = billing == PosServiceBillingMode.PerSession
                ? Math.Max(0, r.Sessions ?? match?.SessionPackCount ?? 0)
                : 0;

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
                dup?.Name,
                type.ToString(),
                billing.ToString(),
                sessions,
                type == PosProductType.Topping ? CleanNames(r.ToppingFor) : [],
                type == PosProductType.Combo
                    ? (r.ComboItems ?? [])
                        .Where(c => !string.IsNullOrWhiteSpace(c.Name))
                        .Select(c => new MenuComboPartDto(c.Name!.Trim(), c.Qty is > 0 ? c.Qty.Value : 1))
                        .ToList()
                    : []));
        }

        var categories = items.Select(i => i.Category).Where(c => c != null).Cast<string>()
            .Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        return new MenuScanResultDto(items, categories, catalog.Count);
    }

    /// <summary>
    /// Tạo nhóm hàng / hàng hóa / dịch vụ / combo / biến thể size / nhóm topping. Loại hàng theo màn xem trước
    /// (AI gợi ý, người dùng sửa); không có thì theo món mẫu, cuối cùng là hàng hóa. Món mẫu cho đơn vị, VAT, giá vốn.
    /// </summary>
    public async Task<MenuImportResultDto> ImportAsync(Guid storeId, IReadOnlyList<MenuItemDto> items, string? actor, CancellationToken ct)
    {
        var skipped = new List<string>();
        var warnings = new List<string>();
        var sampleIds = items.Where(i => i.SampleCatalogId != null).Select(i => i.SampleCatalogId!.Value).Distinct().ToList();
        var samples = await db.PosProductSampleCatalog.AsNoTracking()
            .Where(x => sampleIds.Contains(x.Id))
            .ToDictionaryAsync(x => x.Id, ct);
        var categories = await db.PosProductCategories.AsTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null)
            .ToListAsync(ct);
        var catByKey = categories.GroupBy(c => NameKey(c.Name)).ToDictionary(g => g.Key, g => g.First().Id);
        var existingProducts = await db.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null)
            .Select(p => new { p.Id, p.Name, p.CategoryId, p.ProductType })
            .ToListAsync(ct);
        var existingNames = existingProducts.Select(p => NameKey(p.Name)).ToHashSet();
        var usedCodes = (await db.PosProducts.IgnoreQueryFilters().AsNoTracking()
                .Where(p => p.StoreId == storeId)
                .Select(p => p.ProductCode).ToListAsync(ct))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var usedSkus = (await db.PosProductVariants.IgnoreQueryFilters().AsNoTracking()
                .Where(v => v.StoreId == storeId)
                .Select(v => v.SkuCode).ToListAsync(ct))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        // Mã theo loại hàng như thêm hàng thường (HH / DV / CB / TP / NVL).
        var nextNo = new Dictionary<string, int>();
        string NextCode(PosProductType type)
        {
            var prefix = PosProductTypeRules.CodePrefix(type);
            var n = nextNo.GetValueOrDefault(prefix, 1);
            string code;
            do code = $"{prefix}{n++:D5}"; while (usedCodes.Contains(code));
            nextNo[prefix] = n;
            usedCodes.Add(code);
            return code;
        }

        // Lượt 1: lọc trùng, chốt loại hàng (combo cần biết trước các món thành phần có tồn tại không).
        var plan = new List<(MenuItemDto Item, string Name, PosProductType Type, PosProductSampleCatalog? Sample)>();
        var importedNames = new HashSet<string>();
        foreach (var item in items)
        {
            var name = (item.Name ?? "").Trim();
            if (name.Length == 0) continue;
            if (!importedNames.Add(NameKey(name)))
            {
                skipped.Add($"{name} (trùng tên trong danh sách)");
                continue;
            }
            if (existingNames.Contains(NameKey(name)))
            {
                skipped.Add($"{name} (đã có)");
                continue;
            }
            PosProductSampleCatalog? sample = null;
            if (item.SampleCatalogId is Guid sid) samples.TryGetValue(sid, out sample);
            var type = ParseTypeName(item.ProductType) ?? sample?.ProductType ?? PosProductType.Goods;
            if (!Enum.IsDefined(type)) type = PosProductType.Goods;
            plan.Add((item, name, type, sample));
        }

        var componentKeys = plan.Where(p => p.Type != PosProductType.Combo).Select(p => NameKey(p.Name))
            .Concat(existingProducts.Where(p => p.ProductType != PosProductType.Combo).Select(p => NameKey(p.Name)))
            .ToHashSet();
        for (var i = 0; i < plan.Count; i++)
        {
            var p = plan[i];
            if (p.Type != PosProductType.Combo) continue;
            if ((p.Item.ComboItems ?? []).Any(c => componentKeys.Contains(NameKey(c.Name)))) continue;
            // Combo không có thành phần sẽ luôn báo hết hàng khi bán → tạo hàng hóa thường.
            plan[i] = p with { Type = PosProductType.Goods };
            warnings.Add($"«{p.Name}»: không tìm thấy món thành phần của combo — tạo thành hàng hóa thường, thêm thành phần sau trong Hàng hóa.");
        }

        int catsCreated = 0, productsCreated = 0, variantsCreated = 0, combosCreated = 0;
        var sort = 0;
        var created = new List<(PosProduct Product, MenuItemDto Item)>();
        foreach (var (item, name, type, sample) in plan)
        {
            Guid? categoryId = null;
            var categoryName = !string.IsNullOrWhiteSpace(item.Category) ? item.Category.Trim()
                : type == PosProductType.Topping ? DefaultToppingGroup
                : null;
            if (categoryName != null)
            {
                var key = NameKey(categoryName);
                if (!catByKey.TryGetValue(key, out var cid))
                {
                    var cat = new PosProductCategory
                    {
                        Id = Guid.NewGuid(), StoreId = storeId, Name = categoryName,
                        IsActive = true, CreatedBy = actor,
                    };
                    db.PosProductCategories.Add(cat);
                    catByKey[key] = cid = cat.Id;
                    catsCreated++;
                }
                categoryId = cid;
            }

            // Combo / topping / nguyên liệu / dịch vụ tính giờ không bán theo size.
            var sizes = type is PosProductType.Goods or PosProductType.Service
                ? (item.Sizes ?? []).Where(s => !string.IsNullOrWhiteSpace(s.Name)).ToList()
                : [];
            // Mọi size chưa có giá → dùng giá món người dùng nhập.
            var sizeBase = BasePriceOf(sizes);
            var basePrice = sizeBase > 0 ? sizeBase : Math.Max(0, item.Price);
            if (basePrice <= 0 && type != PosProductType.Material)
                warnings.Add($"«{name}»: giá 0đ — nhớ sửa giá trong Hàng hóa.");
            var unit = !string.IsNullOrWhiteSpace(item.Unit) ? item.Unit.Trim()
                : !string.IsNullOrWhiteSpace(sample?.UnitName) ? sample!.UnitName!.Trim()
                : DefaultUnit(type);
            var code = NextCode(type);
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
                IsDirectSale = type is PosProductType.Goods or PosProductType.Service or PosProductType.Combo,
                IsTopping = type == PosProductType.Topping,
                Description = item.Description ?? sample?.Description,
                ImageUrl = string.IsNullOrWhiteSpace(item.ImageUrl) ? null : item.ImageUrl.Trim(),
                SortOrder = sort++,
                IsActive = true,
                CreatedBy = actor,
            };
            if (type == PosProductType.Service)
            {
                product.ServiceBillingMode = ParseBillingName(item.Billing)
                    ?? sample?.ServiceBillingMode ?? PosServiceBillingMode.Flat;
                if (product.ServiceBillingMode == PosServiceBillingMode.PerSession)
                {
                    product.SessionPackCount = item.SessionCount > 0 ? item.SessionCount : Math.Max(0, sample?.SessionPackCount ?? 0);
                    product.SessionPackValidDays = Math.Max(0, sample?.SessionPackValidDays ?? 0);
                    if (product.SessionPackCount > 0 && product.SessionPackValidDays <= 0)
                        product.SessionPackValidDays = 90;
                }
            }
            db.PosProducts.Add(product);
            db.PosProductUnits.Add(new PosProductUnit
            {
                Id = Guid.NewGuid(), StoreId = storeId, ProductId = product.Id,
                UnitName = unit, ConversionRate = 1, BasePrice = basePrice,
                IsDirectSale = product.IsDirectSale, IsBaseUnit = true, IsActive = true, CreatedBy = actor,
            });
            productsCreated++;
            created.Add((product, item));

            foreach (var size in sizes)
            {
                var sku = $"{code}-{Slug(size.Name)}";
                for (var n = 2; !usedSkus.Add(sku); n++) sku = $"{code}-{Slug(size.Name)}{n}";
                db.PosProductVariants.Add(new PosProductVariant
                {
                    Id = Guid.NewGuid(), StoreId = storeId, ProductId = product.Id,
                    SkuCode = sku,
                    Name = size.Name.Trim(),
                    // Cùng dạng biến thể tạo tay (thuộc tính + ĐVT gốc) để kho / màn bán đọc giống nhau.
                    AttributeJson = JsonSerializer.Serialize(new Dictionary<string, string>
                    {
                        ["Size"] = size.Name.Trim(),
                        ["_unit"] = unit,
                        ["_conversion"] = "1",
                    }),
                    BasePrice = size.Price > 0 ? size.Price : basePrice,
                    IsActive = true,
                    CreatedBy = actor,
                });
                variantsCreated++;
            }
        }

        // Thành phần combo: món vừa tạo hoặc hàng đã có của cửa hàng (trùng tên bỏ dấu).
        var newByKey = created.ToDictionary(c => NameKey(c.Product.Name), c => (c.Product.Id, c.Product.ProductType));
        var existingByKey = existingProducts.GroupBy(p => NameKey(p.Name)).ToDictionary(g => g.Key, g => (g.First().Id, g.First().ProductType));
        foreach (var (combo, item) in created.Where(c => c.Product.ProductType == PosProductType.Combo))
        {
            var lineNo = 0;
            foreach (var part in (item.ComboItems ?? []).DistinctBy(c => NameKey(c.Name)))
            {
                var key = NameKey(part.Name);
                if (!newByKey.TryGetValue(key, out var comp) && !existingByKey.TryGetValue(key, out comp))
                {
                    warnings.Add($"«{combo.Name}»: không thấy món «{part.Name}» — thêm thành phần này sau.");
                    continue;
                }
                if (comp.ProductType == PosProductType.Combo) continue;
                db.PosProductComboLines.Add(new PosProductComboLine
                {
                    Id = Guid.NewGuid(), StoreId = storeId, ComboProductId = combo.Id, ComponentProductId = comp.Id,
                    Qty = part.Qty > 0 ? part.Qty : 1,
                    TrackStock = PosProductTypeRules.TracksInventory(comp.ProductType),
                    IsActive = true, CreatedBy = actor,
                });
                lineNo++;
            }
            if (lineNo > 0) combosCreated++;
        }

        var (groupsCreated, linksCreated) = await LinkToppingsAsync(storeId, created, catByKey, existingProducts
            .Select(p => (p.Id, p.Name, p.CategoryId, p.ProductType)).ToList(), warnings, actor, ct);

        await db.SaveChangesAsync(ct);
        return new MenuImportResultDto(catsCreated, productsCreated, variantsCreated, skipped,
            groupsCreated, linksCreated, combosCreated, warnings);
    }

    /// <summary>
    /// Mỗi nhóm topping trên menu (vd mục «Topping») → một nhóm topping dùng chung (giá phụ thu = giá topping),
    /// gắn vào các món thuộc nhóm hàng / tên món AI ghi ở «toppingFor» (gồm cả hàng đã có của cửa hàng);
    /// không ghi → gắn mọi hàng hóa / combo vừa nhập. Món được gắn bật «cho chọn topping».
    /// </summary>
    async Task<(int GroupsCreated, int LinksCreated)> LinkToppingsAsync(
        Guid storeId,
        List<(PosProduct Product, MenuItemDto Item)> created,
        Dictionary<string, Guid> catByKey,
        List<(Guid Id, string Name, Guid? CategoryId, PosProductType Type)> existingProducts,
        List<string> warnings,
        string? actor,
        CancellationToken ct)
    {
        var toppings = created.Where(c => c.Product.ProductType == PosProductType.Topping).ToList();
        if (toppings.Count == 0) return (0, 0);

        static bool CanHaveToppings(PosProductType t) => t is PosProductType.Goods or PosProductType.Combo;
        var candidates = created.Where(c => CanHaveToppings(c.Product.ProductType))
            .Select(c => (c.Product.Id, c.Product.Name, c.Product.CategoryId, IsNew: true))
            .Concat(existingProducts.Where(p => CanHaveToppings(p.Type)).Select(p => (p.Id, p.Name, p.CategoryId, IsNew: false)))
            .ToList();

        var groups = await db.PosToppingGroups.AsTracking()
            .Where(g => g.StoreId == storeId && g.Deleted == null)
            .ToListAsync(ct);
        var groupByKey = groups.GroupBy(g => NameKey(g.Name)).ToDictionary(g => g.Key, g => g.First());
        var groupIds = groups.Select(g => g.Id).ToList();
        var existingLinks = (await db.PosProductToppingGroupLinks.AsNoTracking()
                .Where(l => l.StoreId == storeId && l.Deleted == null && groupIds.Contains(l.GroupId))
                .Select(l => new { l.ProductId, l.GroupId })
                .ToListAsync(ct))
            .Select(l => (l.ProductId, l.GroupId)).ToHashSet();
        var groupItemCount = (await db.PosToppingGroupItems.AsNoTracking()
                .Where(i => i.StoreId == storeId && i.Deleted == null && groupIds.Contains(i.GroupId))
                .GroupBy(i => i.GroupId)
                .Select(g => new { g.Key, Count = g.Count() })
                .ToListAsync(ct))
            .ToDictionary(x => x.Key, x => x.Count);

        int groupsCreated = 0, linksCreated = 0;
        var enableToppings = new HashSet<Guid>();
        foreach (var bucket in toppings.GroupBy(t => NameKey(t.Item.Category is { Length: > 0 } c ? c : DefaultToppingGroup)))
        {
            var groupName = bucket.First().Item.Category is { Length: > 0 } cn ? cn.Trim() : DefaultToppingGroup;
            if (!groupByKey.TryGetValue(bucket.Key, out var group))
            {
                group = new PosToppingGroup
                {
                    Id = Guid.NewGuid(), StoreId = storeId, Name = groupName, SortOrder = groupByKey.Count,
                    IsActive = true, CreatedBy = actor,
                };
                db.PosToppingGroups.Add(group);
                groupByKey[bucket.Key] = group;
                groupsCreated++;
            }
            var itemSort = groupItemCount.GetValueOrDefault(group.Id);
            foreach (var (topping, _) in bucket)
            {
                db.PosToppingGroupItems.Add(new PosToppingGroupItem
                {
                    Id = Guid.NewGuid(), StoreId = storeId, GroupId = group.Id, ToppingProductId = topping.Id,
                    ExtraPrice = null, // = giá bán của topping
                    SortOrder = itemSort++, IsActive = true, CreatedBy = actor,
                });
            }
            groupItemCount[group.Id] = itemSort;

            var forKeys = bucket.SelectMany(t => t.Item.ToppingFor ?? []).Select(NameKey).Where(k => k.Length > 0).ToHashSet();
            var forCategoryIds = forKeys.Where(catByKey.ContainsKey).Select(k => catByKey[k]).ToHashSet();
            var targets = forKeys.Count == 0
                ? candidates.Where(c => c.IsNew).ToList()
                : candidates.Where(c => forKeys.Contains(NameKey(c.Name))
                                        || (c.CategoryId is Guid cid && forCategoryIds.Contains(cid))).ToList();
            if (targets.Count == 0)
            {
                warnings.Add($"Nhóm topping «{groupName}»: chưa gắn món nào — vào Nhóm topping để chọn món.");
                continue;
            }
            foreach (var target in targets)
            {
                if (!existingLinks.Add((target.Id, group.Id))) continue;
                db.PosProductToppingGroupLinks.Add(new PosProductToppingGroupLink
                {
                    Id = Guid.NewGuid(), StoreId = storeId, ProductId = target.Id, GroupId = group.Id,
                    IsActive = true, CreatedBy = actor,
                });
                enableToppings.Add(target.Id);
                linksCreated++;
            }
        }

        foreach (var (product, _) in created.Where(c => enableToppings.Contains(c.Product.Id)))
            product.AllowToppings = true;
        var oldIds = enableToppings.Except(created.Select(c => c.Product.Id)).ToList();
        if (oldIds.Count > 0)
        {
            foreach (var p in await db.PosProducts.AsTracking().Where(p => oldIds.Contains(p.Id)).ToListAsync(ct))
                p.AllowToppings = true;
        }
        return (groupsCreated, linksCreated);
    }

    static string DefaultUnit(PosProductType type) => type switch
    {
        PosProductType.Service => "Lần",
        PosProductType.Combo => "Suất",
        PosProductType.Material => "Kg",
        _ => "Phần",
    };

    static PosProductType? ParseAiType(string? s) => (s ?? "").Trim().ToLowerInvariant() switch
    {
        "goods" or "hàng hóa" => PosProductType.Goods,
        "service" or "dịch vụ" => PosProductType.Service,
        "combo" => PosProductType.Combo,
        "topping" => PosProductType.Topping,
        "material" or "nguyên liệu" => PosProductType.Material,
        _ => ParseTypeName(s),
    };

    static PosProductType? ParseTypeName(string? s) =>
        Enum.TryParse<PosProductType>(s?.Trim(), true, out var t) && Enum.IsDefined(t) && !int.TryParse(s, out _) ? t : null;

    static PosServiceBillingMode? ParseAiBilling(string? s) => (s ?? "").Trim().ToLowerInvariant() switch
    {
        "flat" => PosServiceBillingMode.Flat,
        "hour" or "perhour" => PosServiceBillingMode.PerHour,
        "day" or "night" or "perday" => PosServiceBillingMode.PerDay,
        "session" or "persession" => PosServiceBillingMode.PerSession,
        _ => ParseBillingName(s),
    };

    static PosServiceBillingMode? ParseBillingName(string? s) =>
        Enum.TryParse<PosServiceBillingMode>(s?.Trim(), true, out var b) && Enum.IsDefined(b) && !int.TryParse(s, out _) ? b : null;

    static List<string> CleanNames(IEnumerable<string?>? names) => (names ?? [])
        .Where(n => !string.IsNullOrWhiteSpace(n))
        .Select(n => n!.Trim())
        .DistinctBy(NameKey)
        .ToList();

    /// <summary>
    /// Chuẩn hóa giá / size AI đọc: bỏ size trùng tên; chỉ 1 size = món một giá (giữ giá của size nếu AI để
    /// price = 0); giá món = size rẻ nhất có giá (size chưa đọc được giá không kéo giá món về 0).
    /// </summary>
    public static (decimal Price, List<MenuSizeDto> Sizes) NormalizePrice(decimal rawPrice, IEnumerable<MenuSizeDto>? rawSizes)
    {
        var sizes = (rawSizes ?? [])
            .Where(s => !string.IsNullOrWhiteSpace(s.Name))
            .Select(s => new MenuSizeDto(s.Name.Trim(), Math.Max(0, s.Price)))
            .DistinctBy(s => NameKey(s.Name))
            .ToList();
        var price = Math.Max(0, rawPrice);
        if (sizes.Count == 1)
        {
            if (price <= 0) price = sizes[0].Price;
            sizes.Clear();
        }
        return (sizes.Count > 0 ? BasePriceOf(sizes) : price, sizes);
    }

    static decimal BasePriceOf(IEnumerable<MenuSizeDto> sizes) =>
        sizes.Where(s => s.Price > 0).Select(s => s.Price).DefaultIfEmpty(0).Min();

    sealed class RawSize
    {
        public string? Name { get; set; }
        public decimal Price { get; set; }
    }

    sealed class RawComboItem
    {
        public string? Name { get; set; }
        public decimal? Qty { get; set; }
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
        public string? Type { get; set; }
        public string? Billing { get; set; }
        public int? Sessions { get; set; }
        public List<string?>? ToppingFor { get; set; }
        public List<RawComboItem>? ComboItems { get; set; }
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
