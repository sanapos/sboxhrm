using System.Runtime.ExceptionServices;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using static ZKTecoADMS.Api.Services.PosAiMenuJson;

namespace ZKTecoADMS.Api.Services;

public sealed record MenuSizeDto(string Name, decimal Price);

/// <summary>Thành phần combo đọc từ menu (tên món như trên menu).</summary>
public sealed record MenuComboPartDto(string Name, decimal Qty);

/// <summary>Một món đọc được từ ảnh menu / bảng tính (người dùng sửa trên màn xem trước rồi gửi lại để tạo hàng).</summary>
/// <param name="ProductType">Tên <see cref="PosProductType"/> (Goods / Service / Combo / Topping / Material). Null = theo mẫu / hàng hóa.</param>
/// <param name="Billing">Tên <see cref="PosServiceBillingMode"/> cho dịch vụ (Flat / PerHour / PerSession / PerDay).</param>
/// <param name="SessionCount">Số buổi khi dịch vụ bán theo gói buổi.</param>
/// <param name="ToppingFor">Topping: tên nhóm hàng / tên món được gắn topping này. Rỗng = mọi món trong lần nhập.</param>
/// <param name="ComboItems">Combo: các món thành phần.</param>
/// <param name="Warnings">Lưu ý khi đọc (giá đã nhân nghìn, khoảng giá, «thời giá», có thể trùng…) — hiện trên màn xem trước.</param>
/// <param name="PossibleDuplicateName">Hàng đã có tên gần giống (chỉ khác dấu) — chỉ cảnh báo, vẫn cho tạo.</param>
/// <param name="SampleCostPrice">Giá vốn sẽ chép từ món mẫu (hiện để người dùng biết / bỏ liên kết mẫu).</param>
/// <param name="SampleVatRate">% VAT sẽ chép từ món mẫu (0 khi mẫu không chịu thuế).</param>
/// <param name="SampleUnit">Đơn vị của món mẫu.</param>
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
    List<MenuComboPartDto>? ComboItems = null,
    List<string>? Warnings = null,
    string? PossibleDuplicateName = null,
    decimal? SampleCostPrice = null,
    decimal? SampleVatRate = null,
    string? SampleUnit = null);

/// <param name="Warnings">Lưu ý cả lần đọc (ảnh / phần file đọc lỗi, món AI trả sai định dạng…).</param>
/// <param name="FailedParts">Số thứ tự (từ 0) các ảnh / phần file chưa đọc được — đọc lại riêng phần đó.</param>
public sealed record MenuScanResultDto(
    List<MenuItemDto> Items,
    List<string> Categories,
    int CatalogSize,
    List<string>? Warnings = null,
    List<int>? FailedParts = null);

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
/// Chụp ảnh menu (hoặc file Excel / CSV lộn xộn) → Gemini đọc tên món / nhóm / giá / size / loại hàng, đồng thời
/// chọn món khớp trong catalog mẫu (PosProductSampleCatalog) để gắn ảnh → tạo nhóm hàng, hàng hóa, dịch vụ, combo,
/// biến thể size, nhóm topping gắn vào món.
/// </summary>
public sealed class PosAiMenuService(ZKTecoDbContext db, IGeminiAiService gemini)
{
    public const int MaxImages = 8;
    /// <summary>Mỗi ảnh gửi AI một lần gọi; inline Gemini ~20 MB / request sau base64 (+33%).</summary>
    public const long MaxImageBytes = 12 * 1024 * 1024;
    public const long MaxTotalBytes = 40 * 1024 * 1024;
    const int MaxCatalogInPrompt = 400;
    const string DefaultToppingGroup = "Topping";
    const int ScanMaxTokens = 32768;
    /// <summary>Token suy nghĩ ăn vào maxOutputTokens — giữ thấp để danh sách món dài không bị cắt.</summary>
    const int ScanThinkingBudget = 1024;
    const int ImageConcurrency = 3;
    const int SheetConcurrency = 4;
    /// <summary>Tổng thời gian chờ AI (dưới 200 s timeout của app).</summary>
    public static readonly TimeSpan AiTimeBudget = TimeSpan.FromSeconds(150);

    /// <summary>Đổi được trong test.</summary>
    public TimeSpan TimeBudget { get; init; } = AiTimeBudget;

    const string SchemaAndCommonRules = """
        - Mỗi món: tên đúng như nguồn (giữ tiếng Việt có dấu, sửa lỗi chính tả rõ ràng), nhóm (tiêu đề mục, vd "Cà phê", "Trà sữa", "Topping", "Massage"), giá bán.
        - Giá là số nguyên VND: "35k" = 35000, "35" (menu ghi đơn vị nghìn) = 35000, "1.2tr" = 1200000.
        - Giá cũ bị gạch ngang kèm giá mới → lấy GIÁ MỚI (đang bán).
        - Giá dạng khoảng ("25-30k") hoặc "thời giá" / "liên hệ" / "theo size" → ghi NGUYÊN VĂN chuỗi vào "price" (vd "25-30k", "thời giá"). Không thấy giá → "price": null. Không tự đoán giá.
        - Món có nhiều size / cỡ (S/M/L, nhỏ/vừa/lớn, ly/chai...) → "sizes" gồm tên size và giá từng size; "price" = giá size nhỏ nhất. Size không ghi giá → price null.
        - Bảng có cột "Nóng" / "Đá" (hoặc "Hot" / "Ice" / "Lạnh") → MỘT món với "sizes" là "Nóng", "Đá" kèm giá từng cột (cột trống thì bỏ size đó).
        - Món một giá → "sizes": [].
        - Cùng một món xuất hiện nhiều lần (lặp lại, ảnh chụp chồng lên nhau) → chỉ ghi MỘT lần.
        - "type" — loại hàng:
          "goods": món ăn, đồ uống, hàng bán (mặc định);
          "service": dịch vụ làm cho khách / thuê theo thời gian: cắt tóc, gội, nail, massage, spa, liệu trình, giờ hát karaoke, giờ bàn bi-a, phòng, gói tập, phí giao hàng...;
          "combo": combo / set / suất gồm nhiều món khác ("Combo 1: cơm + nước");
          "topping": món chỉ thêm vào món khác: trân châu, thạch, pudding, kem cheese, shot espresso thêm, thêm trứng, thêm thịt... (mục "Topping", "Món thêm", "Thêm", hoặc ghi "+5k");
          "material": nguyên liệu (chỉ khi nguồn là bảng nguyên liệu, không phải menu bán).
        - "billing" (chỉ dịch vụ): "hour" nếu giá theo giờ ("/giờ", "/h", "1 giờ"), "day" nếu theo ngày / đêm, "session" nếu là gói nhiều buổi (kèm "sessions" = số buổi), còn lại "flat".
        - "unit": đơn vị bán ngắn gọn: "Ly" (đồ uống pha), "Chai"/"Lon" (đóng chai), "Phần"/"Tô"/"Đĩa" (món ăn), "Lần" (dịch vụ), "Giờ" (tính giờ), "Gói", "Suất" (combo), "Cái"...
        - "toppingFor" (chỉ topping): tên các NHÓM món dùng kèm topping này (nguồn không ghi thì chọn các nhóm hợp lý, vd topping trà sữa → các nhóm trà sữa / trà trái cây).
        - "comboItems" (chỉ combo): các món thành phần, tên đúng như món trong nguồn, kèm số lượng.
        - TUYỆT ĐỐI không bịa món, không thêm món không có trong nguồn.
        - "catalogIndex": số thứ tự món trong DANH MỤC MẪU chỉ khi chắc chắn CÙNG một món (cùng tên, khác cách viết nhỏ); không chắc thì null.
        - Có thể bỏ các trường rỗng / mặc định ("sizes": [], "toppingFor": [], "comboItems": [], "description": null, "catalogIndex": null, "billing": "flat") để trả lời ngắn.
        Chỉ trả JSON đúng schema:
        {"items":[{"name":"","category":"","price":0,"sizes":[{"name":"","price":0}],"unit":"Ly","type":"goods","billing":"flat","sessions":0,"toppingFor":[],"comboItems":[{"name":"","qty":1}],"description":null,"catalogIndex":null}]}
        """;

    const string ImageSystemPrompt = """
        Bạn đọc ảnh chụp MENU / BẢNG GIÁ quán ăn, quán nước, spa, salon, karaoke, bi-a, phòng tập, cửa hàng tại Việt Nam và trích xuất danh sách món.
        Bỏ qua tiêu đề, khẩu hiệu, địa chỉ, số điện thoại, wifi, giờ mở cửa.
        Quy tắc:

        """ + SchemaAndCommonRules;

    const string SheetSystemPrompt = """
        Bạn đọc BẢNG TÍNH (Excel / CSV đã đổi sang dạng TSV: mỗi dòng một hàng của bảng, các cột cách nhau bằng dấu tab) là danh sách
        hàng hóa / menu / bảng giá của cửa hàng tại Việt Nam, có thể lộn xộn (tự làm, xuất từ phần mềm khác), và trích xuất danh sách món.
        Cách đọc bảng:
        - Dòng tiêu đề cột cho biết ý nghĩa cột (Tên / Tên món / Mặt hàng, Nhóm / Danh mục, Giá / Giá bán / Đơn giá, Size, Đơn vị...). Không lấy dòng tiêu đề làm món.
        - Bỏ dòng tổng cộng, dòng trống, ghi chú, thông tin cửa hàng. Cột giá vốn / tồn kho / mã hàng KHÔNG phải giá bán.
        - Dòng chỉ có một tên (không có giá) nằm trên một loạt món → thường là tên NHÓM cho các dòng bên dưới.
        - Cột tiêu đề ghi đơn vị nghìn ("Giá (k)", "nghìn đồng") → nhân 1000. Số trong ô là số thật (25000 = 25.000đ).
        - Nhiều dòng cùng tên món, khác size → một món có "sizes". Các cột giá theo size (Giá M, Giá L / Nóng, Đá) → "sizes".
        Quy tắc:

        """ + SchemaAndCommonRules;

    sealed record CatalogRow(
        Guid Id, string Name, string? CategoryName, string? ImageUrl, PosProductType ProductType,
        PosServiceBillingMode ServiceBillingMode, int SessionPackCount, string? UnitName,
        decimal? DefaultCostPrice, decimal VatRate, bool VatExempt);

    /// <summary>Một lần gọi AI: một ảnh hoặc một phần bảng tính.</summary>
    sealed record ScanPart(string Label, string Intro, string? Data, IReadOnlyList<AiFilePart>? Files);

    sealed record PartOutcome(List<RawItem> Items, int BadItems, string? Warning, Exception? Error);

    /// <summary>Đọc ảnh menu — mỗi ảnh một lần gọi AI (tối đa 3 ảnh cùng lúc), gộp và bỏ món trùng.</summary>
    public Task<MenuScanResultDto> ScanAsync(Guid storeId, IReadOnlyList<AiFilePart> images, CancellationToken ct) =>
        ScanPartsAsync(storeId, ImageSystemPrompt,
            images.Select((img, i) => new ScanPart($"Ảnh {i + 1}", "Đọc ảnh menu đính kèm.", null, [img])).ToList(),
            ImageConcurrency, ct);

    /// <summary>Đọc bảng tính (đã đổi TSV) — mỗi phần một lần gọi AI, cùng schema / màn xem trước như ảnh menu.</summary>
    public Task<MenuScanResultDto> ScanSheetAsync(Guid storeId, MenuSheetText sheet, CancellationToken ct) =>
        ScanPartsAsync(storeId, SheetSystemPrompt,
            sheet.Chunks.Select(c => new ScanPart(
                sheet.Chunks.Count == 1 ? "File" : $"Sheet «{c.SheetName}» dòng {c.FirstRow}–{c.LastRow}",
                "Đọc bảng tính bên dưới (sau DANH MỤC MẪU).", "BẢNG TÍNH:\n" + c.Text, null)).ToList(),
            SheetConcurrency, ct);

    async Task<MenuScanResultDto> ScanPartsAsync(
        Guid storeId, string systemPrompt, List<ScanPart> parts, int concurrency, CancellationToken ct)
    {
        var catalog = await LoadCatalogAsync(storeId, ct);
        var catalogText = new StringBuilder("DANH MỤC MẪU (số thứ tự | tên | nhóm):\n");
        for (var i = 0; i < catalog.Count; i++)
            catalogText.Append(i).Append(" | ").Append(catalog[i].Name).Append(" | ").Append(catalog[i].CategoryName).Append('\n');
        if (catalog.Count == 0) catalogText.Append("(trống — catalogIndex luôn null)\n");

        // AI thêm menu: mọi cửa hàng được dùng khóa AI chung (ưu tiên khóa riêng).
        var ai = gemini.AllowSharedKey();
        // Khởi tạo chọn khóa một lần trước khi gọi song song (lớp chọn khóa theo cửa hàng khởi tạo không an toàn đa luồng).
        _ = ai.IsConfigured;

        PartOutcome[] outcomes;
        using (var deadline = CancellationTokenSource.CreateLinkedTokenSource(ct))
        using (var gate = new SemaphoreSlim(Math.Max(1, concurrency)))
        using (GeminiAiService.UseJsonThinkingBudget(ScanThinkingBudget))
        {
            deadline.CancelAfter(TimeBudget);
            var tasks = parts.Select(p => RunPartAsync(ai, systemPrompt, p, catalogText.ToString(), gate, deadline.Token)).ToList();
            outcomes = await Task.WhenAll(tasks);
        }
        ct.ThrowIfCancellationRequested();

        var scanWarnings = new List<string>();
        var failed = new List<int>();
        for (var i = 0; i < outcomes.Length; i++)
        {
            if (outcomes[i].Error is Exception err)
            {
                failed.Add(i);
                scanWarnings.Add($"{parts[i].Label}: chưa đọc được — {PartErrorText(err)}");
            }
            else if (outcomes[i].Warning is string w) scanWarnings.Add(w);
        }
        if (failed.Count == outcomes.Length && outcomes.Length > 0)
            ExceptionDispatchInfo.Capture(outcomes[0].Error!).Throw();
        var bad = outcomes.Sum(o => o.BadItems);
        if (bad > 0) scanWarnings.Add($"{bad} món AI trả sai định dạng — đã bỏ qua, kiểm tra xem có thiếu món không.");

        var raw = outcomes.Where(o => o.Error == null).SelectMany(o => o.Items).ToList();
        var items = await BuildItemsAsync(storeId, raw, catalog, ct);
        var categories = items.Select(i => i.Category).Where(c => c != null).Cast<string>()
            .DistinctBy(PosProductNameMatch.ExactKey).ToList();
        return new MenuScanResultDto(items, categories, catalog.Count,
            scanWarnings.Count > 0 ? scanWarnings : null, failed.Count > 0 ? failed : null);
    }

    static async Task<PartOutcome> RunPartAsync(
        IGeminiAiService ai, string systemPrompt, ScanPart part, string catalogText, SemaphoreSlim gate, CancellationToken ct)
    {
        try
        {
            await gate.WaitAsync(ct);
        }
        catch (OperationCanceledException ex)
        {
            return new([], 0, null, ex);
        }
        try
        {
            var prompt = part.Intro + "\n\n" + catalogText + (part.Data == null ? "" : "\n" + part.Data);
            var json = await ai.GenerateJsonAsync(systemPrompt, prompt, part.Files, ScanMaxTokens, ct);
            try
            {
                var items = ParseItems(json, out var bad);
                return new(items, bad, null, null);
            }
            catch (JsonException ex)
            {
                // JSON hỏng (không phải do hết độ dài): vẫn giữ các món đã đọc đủ.
                var salvaged = ParseItems(SalvageTruncated(json), out var bad);
                return salvaged.Count > 0
                    ? new(salvaged, bad, $"{part.Label}: kết quả AI lỗi một phần — mới lấy được {salvaged.Count} món, kiểm tra thiếu món.", null)
                    : new([], 0, null, ex);
            }
        }
        catch (AiOutputTruncatedException ex)
        {
            var salvaged = ParseItems(SalvageTruncated(ex.PartialText), out var bad);
            return salvaged.Count > 0
                ? new(salvaged, bad,
                    $"{part.Label}: quá nhiều món cho một lần đọc — mới lấy được {salvaged.Count} món đầu. Chụp / chia nhỏ phần còn lại rồi đọc thêm.",
                    null)
                : new([], 0, null, ex);
        }
        catch (Exception ex) when (ex is AiApiException or InvalidOperationException or HttpRequestException
                                       or OperationCanceledException or JsonException)
        {
            return new([], 0, null, ex);
        }
        finally
        {
            gate.Release();
        }
    }

    static string PartErrorText(Exception ex) => ex switch
    {
        OperationCanceledException => "AI phản hồi quá lâu (hết thời gian chờ)",
        HttpRequestException => "mất kết nối tới máy chủ AI",
        JsonException => "AI trả kết quả không đọc được",
        _ => ex.Message,
    };

    /// <summary>
    /// Catalog mẫu theo hồ sơ ngành của cửa hàng (chưa thiết lập ngành → mọi mẫu), ưu tiên loại hợp ngành
    /// (F&amp;B: món ăn / đồ uống; bán lẻ: hàng đóng gói; ngành dịch vụ: dịch vụ) để bớt token gửi AI.
    /// </summary>
    async Task<List<CatalogRow>> LoadCatalogAsync(Guid storeId, CancellationToken ct)
    {
        var profile = await db.PosStoreSellSettings.AsNoTracking()
            .Where(s => s.StoreId == storeId && s.Deleted == null)
            .Select(s => (PosSellProfile?)s.SellProfile)
            .FirstOrDefaultAsync(ct);
        var q = db.PosProductSampleCatalog.AsNoTracking().Where(x => x.Deleted == null && x.IsActive);
        if (profile is PosSellProfile p) q = q.WhereMatches(p);
        var ordered = profile switch
        {
            null => q.OrderBy(x => x.SortOrder),
            PosSellProfile.Restaurant => q.OrderBy(x => x.Kind == PosProductSampleKind.Packaged ? 1 : 0).ThenBy(x => x.SortOrder),
            PosSellProfile.Retail => q.OrderBy(x => x.Kind == PosProductSampleKind.Packaged ? 0 : 1).ThenBy(x => x.SortOrder),
            _ => q.OrderBy(x => x.ProductType == PosProductType.Service ? 0 : x.Kind == PosProductSampleKind.Packaged ? 2 : 1)
                .ThenBy(x => x.SortOrder),
        };
        return await ordered.ThenBy(x => x.Name)
            .Take(MaxCatalogInPrompt)
            .Select(x => new CatalogRow(x.Id, x.Name, x.CategoryName, x.ImageUrl, x.ProductType, x.ServiceBillingMode,
                x.SessionPackCount, x.UnitName, x.DefaultCostPrice, x.VatRate, x.VatExempt))
            .ToListAsync(ct);
    }

    /// <summary>Món AI đọc → dòng xem trước: chuẩn giá, nhận món mẫu (kiểm tra tên), trùng hàng đã có, bỏ trùng giữa các ảnh.</summary>
    async Task<List<MenuItemDto>> BuildItemsAsync(Guid storeId, List<RawItem> raw, List<CatalogRow> catalog, CancellationToken ct)
    {
        var existing = await db.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null)
            .Select(p => new { p.Id, p.Name })
            .ToListAsync(ct);
        var existingExact = existing.GroupBy(p => PosProductNameMatch.ExactKey(p.Name)).ToDictionary(g => g.Key, g => g.First());
        var existingFold = existing.GroupBy(p => PosProductNameMatch.FoldKey(p.Name)).ToDictionary(g => g.Key, g => g.First());

        var items = new List<MenuItemDto>();
        var indexByKey = new Dictionary<string, int>();
        foreach (var r in raw)
        {
            var name = (r.Name ?? "").Trim();
            if (name.Length == 0) continue;
            var category = string.IsNullOrWhiteSpace(r.Category) ? null : r.Category.Trim();
            var warnings = new List<string>();

            // Chỉ nhận món mẫu AI chọn khi tên thật sự khớp; không có thì thử trùng tên.
            var match = r.CatalogIndex is int ci && ci >= 0 && ci < catalog.Count && PosProductNameMatch.SameDish(name, catalog[ci].Name)
                ? catalog[ci]
                : null;
            match ??= catalog.FirstOrDefault(c => PosProductNameMatch.ExactKey(c.Name) == PosProductNameMatch.ExactKey(name))
                ?? (PosProductNameMatch.HasNoDiacritics(name)
                    ? catalog.FirstOrDefault(c => PosProductNameMatch.FoldKey(c.Name) == PosProductNameMatch.FoldKey(name))
                    : null);

            // AI đọc loại theo ngữ cảnh menu; AI không trả thì lấy loại của món mẫu.
            var type = ParseAiType(r.Type) ?? match?.ProductType ?? PosProductType.Goods;
            var billing = type == PosProductType.Service
                ? ParseAiBilling(r.Billing) ?? match?.ServiceBillingMode ?? PosServiceBillingMode.Flat
                : PosServiceBillingMode.Flat;
            var sessions = billing == PosServiceBillingMode.PerSession
                ? Math.Max(0, r.Sessions ?? match?.SessionPackCount ?? 0)
                : 0;

            var itemPrice = CheckPrice(r.Price, type, null, warnings);
            var rawSizes = (r.Sizes ?? []).Select(s => new MenuSizeDto(s.Name ?? "", CheckPrice(s.Price, type, s.Name, warnings))).ToList();
            // Size thiếu giá vẫn giữ (giá 0) để màn xem trước báo cho người dùng điền.
            var (price, sizes) = NormalizePrice(itemPrice, rawSizes);

            Guid? dupId = null;
            string? dupName = null, maybeDup = null;
            if (existingExact.TryGetValue(PosProductNameMatch.ExactKey(name), out var dup))
                (dupId, dupName) = (dup.Id, dup.Name);
            else if (existingFold.TryGetValue(PosProductNameMatch.FoldKey(name), out var near))
            {
                maybeDup = near.Name;
                warnings.Add($"Có thể trùng hàng đã có «{near.Name}» (chỉ khác dấu) — kiểm tra trước khi tạo.");
            }

            var dto = new MenuItemDto(
                name,
                category,
                price,
                sizes,
                !string.IsNullOrWhiteSpace(r.Unit) ? r.Unit.Trim()
                    : !string.IsNullOrWhiteSpace(match?.UnitName) ? match!.UnitName!.Trim() : null,
                string.IsNullOrWhiteSpace(r.Description) ? null : r.Description.Trim(),
                string.IsNullOrWhiteSpace(match?.ImageUrl) ? null : match!.ImageUrl,
                match?.Id,
                match?.Name,
                dupId,
                dupName,
                type.ToString(),
                billing.ToString(),
                sessions,
                type == PosProductType.Topping ? CleanNames(r.ToppingFor) : [],
                type == PosProductType.Combo
                    ? (r.ComboItems ?? [])
                        .Where(c => !string.IsNullOrWhiteSpace(c.Name))
                        .Select(c => new MenuComboPartDto(c.Name!.Trim(), c.Qty is > 0 ? c.Qty.Value : 1))
                        .ToList()
                    : [],
                warnings.Count > 0 ? warnings : null,
                maybeDup,
                match?.DefaultCostPrice is > 0 ? match.DefaultCostPrice : null,
                match == null ? null : (decimal?)(match.VatExempt ? 0 : match.VatRate),
                string.IsNullOrWhiteSpace(match?.UnitName) ? null : match!.UnitName!.Trim());

            // Cùng món đọc được ở nhiều ảnh / nhiều phần file → giữ một dòng (ưu tiên dòng có giá / nhiều size hơn).
            var key = PosProductNameMatch.ExactKey(name) + "|" + PosProductNameMatch.ExactKey(category);
            if (indexByKey.TryGetValue(key, out var at))
            {
                var old = items[at];
                if ((old.Price <= 0 && dto.Price > 0) || dto.Sizes.Count > old.Sizes.Count) items[at] = dto;
                continue;
            }
            indexByKey[key] = items.Count;
            items.Add(dto);
        }
        return items;
    }

    /// <summary>Giá từ AI → số VND, ghi lưu ý: khoảng giá, «thời giá», không đọc được, thiếu «nghìn» (×1.000).</summary>
    static decimal CheckPrice(LenientPrice p, PosProductType type, string? sizeName, List<string> warnings)
    {
        var what = string.IsNullOrWhiteSpace(sizeName) ? "Giá" : $"Giá size {sizeName.Trim()}";
        switch (p.Flag)
        {
            case MenuPriceFlag.AskPrice:
                warnings.Add($"{what} ghi «{p.Raw}» — nhập giá bán trước khi tạo.");
                return 0;
            case MenuPriceFlag.Unreadable:
                warnings.Add($"{what} «{p.Raw}» không đọc được — nhập lại giá.");
                return 0;
        }
        var v = Math.Max(0, p.Value ?? 0);
        if (type == PosProductType.Material) return Math.Round(v, 0, MidpointRounding.AwayFromZero);
        var fixedPrice = MenuPriceParser.FixMissingThousand(v, out var scaled);
        if (p.Flag == MenuPriceFlag.Range)
            warnings.Add($"{what} dao động «{p.Raw}» — lấy giá thấp {Vnd(fixedPrice)}đ.");
        if (scaled)
            warnings.Add($"{what} đọc được {v:0.##} — hiểu là {Vnd(fixedPrice)}đ (menu ghi đơn vị nghìn), kiểm tra lại.");
        return fixedPrice;
    }

    /// <summary>
    /// Tạo nhóm hàng / hàng hóa / dịch vụ / combo / biến thể size / nhóm topping. Loại hàng theo màn xem trước
    /// (AI gợi ý, người dùng sửa); không có thì theo món mẫu, cuối cùng là hàng hóa. Món mẫu (nếu còn liên kết trên
    /// màn xem trước) cho đơn vị, VAT, giá vốn.
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
        // Trùng chắc chắn chỉ khi tên giống hệt (không phân biệt hoa thường / khoảng trắng); khác dấu chỉ cảnh báo.
        var existingNames = existingProducts.Select(p => PosProductNameMatch.ExactKey(p.Name)).ToHashSet();
        var existingFold = existingProducts.GroupBy(p => PosProductNameMatch.FoldKey(p.Name)).ToDictionary(g => g.Key, g => g.First().Name);
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
            if (name.Length > 500) name = name[..500];
            var exact = PosProductNameMatch.ExactKey(name);
            if (!importedNames.Add(exact))
            {
                skipped.Add($"{name} (trùng tên trong danh sách)");
                continue;
            }
            if (existingNames.Contains(exact))
            {
                skipped.Add($"{name} (đã có)");
                continue;
            }
            if (existingFold.TryGetValue(PosProductNameMatch.FoldKey(name), out var near))
                warnings.Add($"«{name}»: tên gần giống hàng đã có «{near}» (khác dấu) — đã tạo món mới, kiểm tra nếu bị trùng.");
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
            if (categoryName is { Length: > 200 }) categoryName = categoryName[..200];
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
            else if (basePrice < 1000 && type != PosProductType.Material)
                warnings.Add($"«{name}»: giá {basePrice:0.##}đ — dưới 1.000đ, kiểm tra lại (thiếu «nghìn»?).");
            var unit = !string.IsNullOrWhiteSpace(item.Unit) ? item.Unit.Trim()
                : !string.IsNullOrWhiteSpace(sample?.UnitName) ? sample!.UnitName!.Trim()
                : DefaultUnit(type);
            if (unit.Length > 100) unit = unit[..100];
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
                // Giá vốn / VAT theo món mẫu chỉ khi màn xem trước còn giữ liên kết mẫu (đã hiện cho người dùng).
                CostPrice = Math.Max(0, sample?.DefaultCostPrice ?? 0),
                VatRate = sample?.VatExempt == true ? 0 : sample?.VatRate ?? 8,
                VatExempt = sample?.VatExempt ?? false,
                BaseUnitName = unit,
                IsDirectSale = type is PosProductType.Goods or PosProductType.Service or PosProductType.Combo,
                IsTopping = type == PosProductType.Topping,
                Description = Cap(item.Description, 2000),
                ImageUrl = string.IsNullOrWhiteSpace(item.ImageUrl) || item.ImageUrl.Trim().Length > 500 ? null : item.ImageUrl.Trim(),
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

        // Thành phần combo: món vừa tạo hoặc hàng đã có của cửa hàng — ưu tiên trùng tên hệt, rồi mới bỏ dấu.
        var components = created.Select(c => (c.Product.Id, c.Product.Name, c.Product.ProductType))
            .Concat(existingProducts.Select(p => (p.Id, p.Name, p.ProductType)))
            .ToList();
        var compExact = components.GroupBy(c => PosProductNameMatch.ExactKey(c.Name)).ToDictionary(g => g.Key, g => g.First());
        var compFold = components.GroupBy(c => NameKey(c.Name)).ToDictionary(g => g.Key, g => g.First());
        foreach (var (combo, item) in created.Where(c => c.Product.ProductType == PosProductType.Combo))
        {
            var lineNo = 0;
            var usedComponents = new HashSet<Guid>();
            foreach (var part in item.ComboItems ?? [])
            {
                if (!compExact.TryGetValue(PosProductNameMatch.ExactKey(part.Name), out var comp)
                    && !compFold.TryGetValue(NameKey(part.Name), out comp))
                {
                    warnings.Add($"«{combo.Name}»: không thấy món «{part.Name}» — thêm thành phần này sau.");
                    continue;
                }
                if (comp.ProductType == PosProductType.Combo || comp.Id == combo.Id || !usedComponents.Add(comp.Id)) continue;
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
                    Id = Guid.NewGuid(), StoreId = storeId, Name = groupName.Length > 200 ? groupName[..200] : groupName,
                    SortOrder = groupByKey.Count, IsActive = true, CreatedBy = actor,
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
            .DistinctBy(s => PosProductNameMatch.ExactKey(s.Name))
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

    /// <summary>So tên không phân biệt dấu / hoa thường / khoảng trắng (tra cứu mềm: nhóm hàng, thành phần combo, topping).</summary>
    public static string NameKey(string? s) => PosProductNameMatch.FoldKey(s);

    /// <summary>«35.000» — dấu chấm phân cách nghìn, không phụ thuộc culture máy chủ.</summary>
    static string Vnd(decimal v) => v.ToString("#,##0", System.Globalization.CultureInfo.InvariantCulture).Replace(',', '.');

    static string? Cap(string? s, int max)
    {
        if (string.IsNullOrWhiteSpace(s)) return null;
        var t = s.Trim();
        return t.Length > max ? t[..max] : t;
    }

    static string Slug(string s)
    {
        var k = NameKey(s).ToUpperInvariant();
        return k.Length == 0 ? "SZ" : (k.Length > 8 ? k[..8] : k);
    }
}
