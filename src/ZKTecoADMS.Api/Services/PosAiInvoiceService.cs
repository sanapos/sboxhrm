using System.Globalization;
using System.Runtime.ExceptionServices;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>NCC in trên hóa đơn + NCC đã có khớp được (MatchedBy: taxCode / phone / name / fuzzy).</summary>
public sealed record InvoiceSupplierDto(
    string? Name, string? Phone, string? TaxCode, string? Address,
    Guid? MatchedSupplierId, string? MatchedSupplierName, string? MatchedBy);

public sealed record InvoiceProductRefDto(Guid Id, string Name, string? Code = null, string? BaseUnit = null);

/// <summary>Một dòng hóa đơn đã chuẩn hóa + đối chiếu hàng.</summary>
/// <param name="Discount">Chiết khấu dòng (tiền).</param>
/// <param name="VatRate">% thuế GTGT của dòng (null = hóa đơn không ghi).</param>
/// <param name="MatchedBy">remembered / name / barcode / code / fold / fuzzy; null = chưa khớp.</param>
/// <param name="MatchedUnitId">Dòng PosProductUnits của ĐVT khớp (gốc hoặc quy đổi).</param>
/// <param name="UnitName">ĐVT dùng trên phiếu nhập (ĐVT của hàng khi khớp được, không thì ĐVT hóa đơn).</param>
/// <param name="UnitFactor">1 ĐVT hóa đơn = UnitFactor × ĐVT gốc.</param>
/// <param name="UnitStatus">base / unit / remembered / unknown / none (chưa khớp hàng).</param>
/// <param name="BaseQty">SL quy về ĐVT gốc (= Qty × UnitFactor).</param>
/// <param name="Page">Ảnh thứ mấy (từ 0).</param>
public sealed record InvoiceLineDto(
    string Name, string? Code, decimal Qty, string? Unit, decimal UnitPrice, decimal LineTotal, decimal Discount,
    decimal? VatRate, bool VatExempt,
    Guid? MatchedProductId, string? MatchedProductName, string? MatchedBy,
    Guid? MatchedUnitId, string? UnitName, decimal UnitFactor, string UnitStatus, decimal BaseQty, string? BaseUnitName,
    double Confidence, List<string> Warnings, List<InvoiceProductRefDto> PossibleMatches, int Page = 0);

/// <summary>Tổng in trên hóa đơn (null = không đọc được) và tổng tính lại từ các dòng.</summary>
public sealed record InvoiceTotalsDto(
    decimal? Subtotal, decimal? Discount, decimal? Vat, decimal? Total,
    decimal LinesSubtotal, decimal LinesVat, decimal LinesTotal);

/// <param name="PricesIncludeVat">Đơn giá in trên hóa đơn đã gồm thuế (hóa đơn bán lẻ / ghi «giá đã có VAT»).</param>
/// <param name="FailedParts">Số thứ tự (từ 0) các ảnh chưa đọc được.</param>
public sealed record InvoiceScanResultDto(
    InvoiceSupplierDto Supplier, string? InvoiceNo, DateTime? InvoiceDate, bool PricesIncludeVat,
    List<InvoiceLineDto> Lines, InvoiceTotalsDto Totals, List<string>? Warnings = null, List<int>? FailedParts = null);

/// <summary>Dòng người dùng đã duyệt trên màn xem trước.</summary>
/// <param name="InvoiceName">Tên in trên hóa đơn (để nhớ ánh xạ).</param>
/// <param name="CreateProduct">Chưa có hàng → tạo hàng hóa mới (giá vốn = đơn giá nhập).</param>
/// <param name="UnitFactor">Hệ số người dùng nhập khi ĐVT hóa đơn chưa khai báo cho hàng (vd 1 thùng = 24).</param>
/// <param name="Remember">Nhớ «tên trên hóa đơn → hàng này» cho lần sau.</param>
public sealed record InvoiceConfirmLineDto(
    string? InvoiceName, Guid? ProductId, bool CreateProduct, string? NewProductName,
    decimal Qty, string? UnitName, decimal UnitPrice, decimal Discount,
    decimal VatRate, bool VatExempt, bool VatIncluded, decimal UnitFactor = 1, bool Remember = true,
    string? InvoiceUnit = null);

public sealed record InvoiceConfirmRequest(
    Guid? SupplierId, bool CreateSupplier, string? SupplierName, string? SupplierPhone, string? SupplierTaxCode,
    string? SupplierAddress, string? InvoiceNo, DateTime? InvoiceDate, decimal DiscountAmount,
    bool Complete, decimal PaidAmount, string? PaymentMethod, string? Note, List<InvoiceConfirmLineDto> Lines);

public sealed record InvoiceConfirmResultDto(
    Guid ReceiptId, string ReceiptNo, string Status, decimal GrandTotal, decimal PaidAmount,
    Guid? SupplierId, bool SupplierCreated, int ProductsCreated, int MappingsSaved, List<string>? Warnings);

/// <summary>
/// Chụp hóa đơn nhà cung cấp (1–4 ảnh) → Gemini đọc NCC, số / ngày hóa đơn, dòng hàng (SL, ĐVT, đơn giá, thành tiền,
/// chiết khấu, VAT), tổng → máy chủ đối chiếu hàng / NCC / ĐVT, kiểm tra cộng tổng → người dùng duyệt →
/// tạo phiếu nhập (tạm hoặc hoàn thành) bằng đúng logic của màn «Nhập hàng» (<see cref="PosPurchaseReceiptBuilder"/>).
/// </summary>
public sealed class PosAiInvoiceService(ZKTecoDbContext db, IGeminiAiService gemini)
{
    public const int MaxImages = 4;
    public const int MaxLines = 300;
    const int ScanMaxTokens = 16384;
    const int ScanThinkingBudget = 1024;
    const int ImageConcurrency = 4;

    /// <summary>Đổi được trong test.</summary>
    public TimeSpan TimeBudget { get; init; } = PosAiMenuService.AiTimeBudget;

    const string SystemPrompt = """
        Bạn đọc ảnh chụp HÓA ĐƠN / PHIẾU GIAO HÀNG / PHIẾU XUẤT KHO của NHÀ CUNG CẤP gửi cho một cửa hàng tại Việt Nam
        (hóa đơn GTGT, hóa đơn bán lẻ, phiếu viết tay) và trích xuất dữ liệu để nhập kho.
        Quy tắc:
        - "supplier": BÊN BÁN (Đơn vị bán hàng / Người bán / tên in ở đầu phiếu), KHÔNG phải bên mua (Người mua / Đơn vị mua hàng).
          Lấy tên, số điện thoại, mã số thuế (MST) và địa chỉ của bên bán; không thấy thì null.
        - "invoiceNo": số hóa đơn / số phiếu (vd "0001234"); "invoiceDate": ngày hóa đơn dạng "dd/MM/yyyy".
        - "lines": mỗi dòng hàng trong bảng, giữ thứ tự: "name" tên hàng đúng như in (giữ tiếng Việt có dấu), "code" mã hàng /
          mã vạch nếu có cột mã, "qty" số lượng, "unit" đơn vị tính (Thùng, Lon, Kg, Hộp...), "unitPrice" đơn giá,
          "discount" tiền chiết khấu của dòng (hoặc "discountPercent" nếu chỉ ghi %), "vatRate" thuế suất của dòng nếu bảng có
          cột thuế suất ("8%", "10%", "KCT"), "lineTotal" thành tiền của dòng.
        - Số ghi ĐÚNG như in trên hóa đơn, dạng số nguyên VND, không tự tính bù giá trị bị thiếu (thiếu → null).
          Hóa đơn Việt Nam dùng dấu chấm phân cách hàng nghìn: "1.234.567" = 1234567; "2,5" = 2.5.
        - Dòng bị mờ, che, rách, đọc không chắc chắn → vẫn ghi phần đọc được và đặt "unreadable": true.
        - Bỏ dòng tiêu đề bảng, dòng "Cộng", dòng trống, dòng ghi chú, chữ ký.
        - Phần tổng: "subtotal" Cộng tiền hàng (trước thuế), "discount" chiết khấu thương mại cả hóa đơn, "vatRate" thuế suất GTGT
          chung, "vat" tiền thuế GTGT, "total" Tổng cộng tiền thanh toán. Không có thì null.
        - "pricesIncludeVat": true nếu đơn giá / thành tiền ĐÃ gồm thuế (hóa đơn bán lẻ, ghi "giá đã bao gồm VAT", không có dòng
          tiền thuế riêng); false nếu là hóa đơn GTGT tách tiền thuế.
        - Ảnh chỉ là một phần (một trang) của hóa đơn → chỉ ghi những gì thấy trên ảnh.
        - TUYỆT ĐỐI không bịa dòng hàng, không thêm hàng không có trên ảnh.
        Chỉ trả JSON đúng schema:
        {"supplier":{"name":"","phone":null,"taxCode":null,"address":null},"invoiceNo":null,"invoiceDate":null,"pricesIncludeVat":false,"vatRate":null,"subtotal":null,"discount":null,"vat":null,"total":null,"lines":[{"name":"","code":null,"qty":1,"unit":"","unitPrice":0,"discount":null,"discountPercent":null,"vatRate":null,"lineTotal":0,"unreadable":false}]}
        """;

    sealed record PartOutcome(RawInvoice? Invoice, string? Warning, Exception? Error);

    // ─────────────────────────── Đọc ảnh ───────────────────────────

    /// <summary>Đọc ảnh hóa đơn — mỗi ảnh một lần gọi AI (song song), gộp các trang, đối chiếu hàng / NCC.</summary>
    public async Task<InvoiceScanResultDto> ScanAsync(Guid storeId, IReadOnlyList<AiFilePart> images, CancellationToken ct)
    {
        // Đọc hóa đơn: mọi cửa hàng được dùng khóa AI chung (ưu tiên khóa riêng) — như «AI thêm menu».
        var ai = gemini.AllowSharedKey();
        // Khởi tạo chọn khóa một lần trước khi gọi song song (lớp chọn khóa theo cửa hàng khởi tạo không an toàn đa luồng).
        _ = ai.IsConfigured;

        PartOutcome[] outcomes;
        using (var deadline = CancellationTokenSource.CreateLinkedTokenSource(ct))
        using (var gate = new SemaphoreSlim(ImageConcurrency))
        using (GeminiAiService.UseJsonThinkingBudget(ScanThinkingBudget))
        {
            deadline.CancelAfter(TimeBudget);
            var tasks = images.Select((img, i) => RunPartAsync(ai, img, images.Count == 1 ? "Ảnh" : $"Ảnh {i + 1}", gate, deadline.Token)).ToList();
            outcomes = await Task.WhenAll(tasks);
        }
        ct.ThrowIfCancellationRequested();

        var warnings = new List<string>();
        var failed = new List<int>();
        for (var i = 0; i < outcomes.Length; i++)
        {
            if (outcomes[i].Error is Exception err)
            {
                failed.Add(i);
                warnings.Add($"{(outcomes.Length == 1 ? "Ảnh" : $"Ảnh {i + 1}")}: chưa đọc được — {PartErrorText(err)}");
            }
            else if (outcomes[i].Warning is string w) warnings.Add(w);
        }
        if (failed.Count == outcomes.Length && outcomes.Length > 0)
            ExceptionDispatchInfo.Capture(outcomes[0].Error!).Throw();

        var pages = new List<RawInvoice>();
        for (var i = 0; i < outcomes.Length; i++)
        {
            if (outcomes[i].Invoice is not RawInvoice inv) continue;
            foreach (var l in inv.Lines) l.Page = i;
            pages.Add(inv);
        }
        var merged = Merge(pages, warnings);
        return await BuildResultAsync(storeId, merged, warnings, failed, ct);
    }

    static async Task<PartOutcome> RunPartAsync(
        IGeminiAiService ai, AiFilePart image, string label, SemaphoreSlim gate, CancellationToken ct)
    {
        try
        {
            await gate.WaitAsync(ct);
        }
        catch (OperationCanceledException ex)
        {
            return new(null, null, ex);
        }
        try
        {
            var json = await ai.GenerateJsonAsync(SystemPrompt, "Đọc ảnh hóa đơn nhà cung cấp đính kèm.", [image], ScanMaxTokens, ct);
            try
            {
                return new(PosAiInvoiceParsing.Parse(json), null, null);
            }
            catch (JsonException ex)
            {
                var salvaged = PosAiInvoiceParsing.Salvage(json);
                return salvaged.Lines.Count > 0
                    ? new(salvaged, $"{label}: kết quả AI lỗi một phần — mới lấy được {salvaged.Lines.Count} dòng, kiểm tra thiếu dòng.", null)
                    : new(null, null, ex);
            }
        }
        catch (AiOutputTruncatedException ex)
        {
            var salvaged = PosAiInvoiceParsing.Salvage(ex.PartialText);
            return salvaged.Lines.Count > 0
                ? new(salvaged, $"{label}: hóa đơn quá dài cho một lần đọc — mới lấy được {salvaged.Lines.Count} dòng đầu. Chụp phần còn lại thành ảnh riêng.", null)
                : new(null, null, ex);
        }
        catch (Exception ex) when (ex is AiApiException or InvalidOperationException or HttpRequestException
                                       or OperationCanceledException or JsonException)
        {
            return new(null, null, ex);
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
    /// Gộp các trang: thông tin NCC / số / ngày lấy ở trang đầu có ghi; tổng lấy ở trang CUỐI có ghi (trang chứa dòng
    /// «Tổng cộng»); dòng hàng nối theo thứ tự ảnh.
    /// </summary>
    internal static RawInvoice Merge(IReadOnlyList<RawInvoice> pages, List<string> warnings)
    {
        var m = new RawInvoice();
        foreach (var p in pages)
        {
            m.SupplierName ??= Blank(p.SupplierName);
            m.SupplierPhone ??= Blank(p.SupplierPhone);
            m.SupplierTaxCode ??= Blank(p.SupplierTaxCode);
            m.SupplierAddress ??= Blank(p.SupplierAddress);
            m.InvoiceNo ??= Blank(p.InvoiceNo);
            m.InvoiceDate ??= p.InvoiceDate;
            m.PricesIncludeVat ??= p.PricesIncludeVat;
            if (!m.Vat.HasValue && p.Vat.HasValue) m.Vat = p.Vat;
            m.Lines.AddRange(p.Lines);
            m.BadLines += p.BadLines;
        }
        foreach (var p in pages.Reverse())
        {
            if (p.Total.Value == null && p.Subtotal.Value == null) continue;
            m.Subtotal = p.Subtotal;
            m.Discount = p.Discount;
            m.VatAmount = p.VatAmount;
            m.Total = p.Total;
            break;
        }
        var numbers = pages.Select(p => Blank(p.InvoiceNo)).Where(n => n != null).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        if (numbers.Count > 1)
            warnings.Add($"Các ảnh ghi số hóa đơn khác nhau ({string.Join(", ", numbers)}) — mỗi lần chỉ nên chụp một hóa đơn.");
        return m;

        static string? Blank(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();
    }

    /// <summary>Chuẩn hóa dòng, kiểm tra SL × đơn giá / cộng tổng, đối chiếu NCC + hàng + ĐVT.</summary>
    internal async Task<InvoiceScanResultDto> BuildResultAsync(
        Guid storeId, RawInvoice inv, List<string> warnings, List<int> failed, CancellationToken ct)
    {
        var suppliers = await db.PosSuppliers.AsNoTracking()
            .Where(s => s.StoreId == storeId && s.Deleted == null)
            .Select(s => new InvoiceSupplierCandidate(s.Id, s.Name, s.CompanyName, s.Phone, s.TaxCode))
            .ToListAsync(ct);
        var (supplier, supplierBy) = PosAiInvoiceMatching.MatchSupplier(
            inv.SupplierName, inv.SupplierPhone, inv.SupplierTaxCode, suppliers);
        var products = await LoadProductsAsync(storeId, ct);
        var mappings = await LoadMappingsAsync(storeId, supplier?.Id, ct);

        if (inv.BadLines > 0)
            warnings.Add($"{inv.BadLines} dòng AI trả sai định dạng — đã bỏ qua, kiểm tra xem có thiếu dòng không.");
        var unreadable = inv.Lines.Count(l => l.Unreadable);
        if (unreadable > 0)
            warnings.Add($"{unreadable} dòng chữ mờ / đọc không chắc — kiểm tra kỹ các dòng có cảnh báo.");

        var includeVat = inv.PricesIncludeVat == true;
        var lines = new List<InvoiceLineDto>();
        var seen = new Dictionary<string, int>();
        foreach (var raw in inv.Lines)
        {
            var line = BuildLine(raw, inv.Vat, supplier?.Id, products, mappings);
            if (line == null) continue;
            // Ảnh chụp chồng lên nhau có thể lặp dòng: chỉ cảnh báo (hóa đơn thật có thể có hai dòng giống nhau).
            var key = $"{PosProductNameMatch.FoldKey(line.Name)}|{line.Qty}|{line.UnitPrice}|{line.LineTotal}";
            if (seen.TryGetValue(key, out var page) && page != line.Page)
                line.Warnings.Add("Dòng giống hệt một dòng ở ảnh khác — có thể chụp trùng, xóa nếu thừa.");
            seen.TryAdd(key, line.Page);
            lines.Add(line);
        }

        var totals = CheckTotals(inv, lines, includeVat, warnings);
        return new InvoiceScanResultDto(
            new InvoiceSupplierDto(inv.SupplierName, inv.SupplierPhone, inv.SupplierTaxCode, inv.SupplierAddress,
                supplier?.Id, supplier?.Name, supplierBy),
            inv.InvoiceNo, inv.InvoiceDate, includeVat, lines, totals,
            warnings.Count > 0 ? warnings : null, failed.Count > 0 ? failed : null);
    }

    /// <summary>Một dòng AI đọc → dòng xem trước; dòng không tên và không số → bỏ.</summary>
    internal static InvoiceLineDto? BuildLine(
        RawInvoiceLine raw, InvoiceVatValue invoiceVat, Guid? supplierId,
        IReadOnlyList<InvoiceProductCandidate> products, IReadOnlyList<InvoiceMappingCandidate> mappings)
    {
        var name = (raw.Name ?? "").Trim();
        var price = raw.UnitPrice.Value;
        var total = raw.LineTotal.Value;
        if (name.Length == 0 && (price ?? 0) <= 0 && (total ?? 0) <= 0) return null;
        var warnings = new List<string>();
        if (name.Length == 0)
        {
            name = "(không đọc được tên)";
            warnings.Add("Không đọc được tên hàng — chọn hàng hoặc xóa dòng.");
        }
        if (raw.Unreadable) warnings.Add("Dòng mờ / đọc không chắc — đối chiếu với hóa đơn giấy.");
        foreach (var (p, what) in new[] { (raw.UnitPrice, "Đơn giá"), (raw.LineTotal, "Thành tiền"), (raw.Discount, "Chiết khấu") })
            if (p.Flag is MenuPriceFlag.Unreadable or MenuPriceFlag.AskPrice)
                warnings.Add($"{what} «{p.Raw}» không đọc được — nhập lại.");

        var qty = raw.Qty is > 0 ? raw.Qty.Value : (decimal?)null;
        // Chiết khấu % → tiền (tính khi đã biết SL / đơn giá).
        decimal Disc(decimal q, decimal up) => raw.Discount.Value is > 0 ? raw.Discount.Value!.Value
            : raw.DiscountPercent is decimal pct ? Math.Round(q * up * pct / 100m, 0, MidpointRounding.AwayFromZero) : 0;

        if (qty == null)
        {
            if (price is > 0 && total is > 0)
            {
                qty = Math.Round(total.Value / price.Value, 3);
                warnings.Add($"Không đọc được số lượng — tính từ thành tiền ÷ đơn giá = {Num(qty.Value)}.");
            }
            else
            {
                qty = 1;
                warnings.Add("Không đọc được số lượng — tạm để 1, nhập lại.");
            }
        }
        if (price is not > 0)
        {
            if (total is > 0)
            {
                price = Math.Round((total.Value + (raw.Discount.Value ?? 0)) / qty.Value, 2);
                warnings.Add($"Không đọc được đơn giá — tính từ thành tiền ÷ SL = {Vnd(price.Value)}đ.");
            }
            else
            {
                price = 0;
                warnings.Add("Chưa có đơn giá — nhập giá nhập.");
            }
        }
        var discount = Disc(qty.Value, price.Value);
        var computed = Math.Max(0, qty.Value * price.Value - discount);
        if (total is > 0)
        {
            var vatFactor = 1 + ((raw.Vat.Rate ?? invoiceVat.Rate ?? 0) / 100m);
            // Thành tiền đã cộng thuế của dòng cũng coi là khớp.
            if (!Near(computed, total.Value) && !Near(Math.Round(computed * vatFactor, 0), total.Value))
                warnings.Add($"SL × đơn giá{(discount > 0 ? " − CK" : "")} = {Vnd(computed)}đ, khác thành tiền in trên hóa đơn {Vnd(total.Value)}đ — kiểm tra SL / đơn giá.");
        }
        var lineTotal = total is > 0 ? total.Value : computed;

        var vat = raw.Vat.HasValue ? raw.Vat : invoiceVat;
        var match = PosAiInvoiceMatching.MatchProduct(name, raw.Code, supplierId, products, mappings);
        var product = match.Product;
        InvoiceUnitResolution unit;
        if (product != null)
        {
            unit = PosAiInvoiceMatching.ResolveUnit(product, raw.Unit, match.Mapping);
            if (match.By == "fuzzy") warnings.Add($"Khớp gần đúng với «{product.Name}» — kiểm tra đúng hàng chưa.");
            if (unit.Status == "unknown")
                warnings.Add($"Hàng «{product.Name}» chưa có ĐVT «{unit.UnitName}» (ĐVT gốc «{product.BaseUnit}») — nhập số {product.BaseUnit} / 1 {unit.UnitName} hoặc sửa SL theo ĐVT gốc.");
            else if (unit.Status is "unit" or "remembered" && unit.Factor != 1)
                warnings.Add($"1 {unit.UnitName} = {Num(unit.Factor)} {product.BaseUnit} → nhập kho {Num(qty.Value * unit.Factor)} {product.BaseUnit}.");
        }
        else
        {
            unit = new(null, raw.Unit ?? "", 1, "none");
            warnings.Add(match.Possible.Count > 0
                ? "Chưa khớp hàng — chọn trong gợi ý / tìm hàng, hoặc tạo hàng mới."
                : "Chưa có hàng này — tìm hàng có sẵn hoặc tạo hàng mới.");
        }

        var confidence = match.Confidence;
        if (raw.Unreadable || warnings.Any(w => w.StartsWith("Không đọc được", StringComparison.Ordinal)))
            confidence = Math.Max(0, confidence - 0.3);
        else if (product != null && unit.Status == "unknown")
            confidence = Math.Max(0, confidence - 0.2);

        return new InvoiceLineDto(
            name, raw.Code, qty.Value, raw.Unit, price.Value, lineTotal, discount,
            vat.Exempt ? 0 : vat.Rate, vat.Exempt,
            product?.Id, product?.Name, match.By,
            unit.UnitId, product == null ? raw.Unit : unit.UnitName, unit.Factor, unit.Status,
            qty.Value * unit.Factor, product?.BaseUnit,
            Math.Round(confidence, 2), warnings,
            match.Possible.Select(p => new InvoiceProductRefDto(p.Id, p.Name, p.Code, p.BaseUnit)).ToList(),
            raw.Page);
    }

    /// <summary>Cộng tiền các dòng, so với tổng in trên hóa đơn; ghi cảnh báo khi lệch.</summary>
    internal static InvoiceTotalsDto CheckTotals(RawInvoice inv, List<InvoiceLineDto> lines, bool includeVat, List<string> warnings)
    {
        var linesSubtotal = lines.Sum(l => l.LineTotal);
        var linesVat = includeVat ? 0 : lines.Sum(l => l.VatExempt || l.VatRate is not > 0
            ? 0 : Math.Round(l.LineTotal * l.VatRate.Value / 100m, 0, MidpointRounding.AwayFromZero));
        var subtotal = inv.Subtotal.Value is > 0 ? inv.Subtotal.Value : null;
        var discount = inv.Discount.Value is > 0 ? inv.Discount.Value : null;
        var vat = inv.VatAmount.Value is > 0 ? inv.VatAmount.Value : null;
        var total = inv.Total.Value is > 0 ? inv.Total.Value : null;
        if (vat == null && !includeVat && subtotal != null && inv.Vat.Rate is > 0 && linesVat == 0)
            linesVat = Math.Round((subtotal.Value - (discount ?? 0)) * inv.Vat.Rate.Value / 100m, 0, MidpointRounding.AwayFromZero);
        var linesTotal = linesSubtotal - (discount ?? 0) + linesVat;

        if (subtotal != null && !Near(linesSubtotal, subtotal.Value))
            warnings.Add($"Cộng các dòng = {Vnd(linesSubtotal)}đ, khác «Cộng tiền hàng» in trên hóa đơn {Vnd(subtotal.Value)}đ — có thể thiếu / đọc sai dòng.");
        if (total != null)
        {
            // Tổng in trên hóa đơn so với tổng tính (thuế in sẵn ưu tiên hơn thuế tự tính).
            var expected = (subtotal ?? linesSubtotal) - (discount ?? 0) + (vat ?? linesVat);
            if (!Near(expected, total.Value) && !Near(linesTotal, total.Value))
                warnings.Add($"Tổng tính được {Vnd(expected)}đ, khác «Tổng cộng thanh toán» in trên hóa đơn {Vnd(total.Value)}đ — kiểm tra lại các dòng / thuế.");
        }
        if (lines.Count == 0) warnings.Add("Không đọc được dòng hàng nào.");
        return new InvoiceTotalsDto(subtotal, discount, vat, total, linesSubtotal, linesVat, linesTotal);
    }

    // ─────────────────────────── Tạo phiếu ───────────────────────────

    /// <summary>
    /// Tạo NCC mới (nếu chọn), hàng mới (dòng tick «tạo hàng mới»), nhớ ánh xạ tên hóa đơn → hàng, rồi tạo phiếu nhập
    /// tạm / hoàn thành bằng <see cref="PosPurchaseReceiptBuilder"/> — tất cả trong một transaction.
    /// </summary>
    public async Task<(InvoiceConfirmResultDto? Result, string? Error)> ConfirmAsync(
        Guid storeId, Guid? branchId, string? actor, Func<Guid> userId, InvoiceConfirmRequest req, CancellationToken ct)
    {
        if (req.Lines == null || req.Lines.Count == 0) return (null, "Chưa có dòng hàng nào.");
        if (req.Lines.Count > MaxLines) return (null, $"Tối đa {MaxLines} dòng mỗi phiếu.");
        for (var i = 0; i < req.Lines.Count; i++)
        {
            var l = req.Lines[i];
            var label = LineLabel(l, i);
            if (l.ProductId == null && !l.CreateProduct) return (null, $"{label}: chưa chọn hàng (hoặc tick «tạo hàng mới»).");
            if (l.ProductId == null && string.IsNullOrWhiteSpace(l.NewProductName ?? l.InvoiceName))
                return (null, $"{label}: nhập tên hàng mới.");
            if (l.Qty <= 0) return (null, $"{label}: số lượng phải > 0.");
            if (l.UnitPrice < 0 || l.Discount < 0) return (null, $"{label}: đơn giá / chiết khấu không được âm.");
        }

        for (var attempt = 0; ; attempt++)
        {
            var tx = db.Database.IsRelational() ? await db.Database.BeginTransactionAsync(ct) : null;
            try
            {
                var (result, error) = await ConfirmCoreAsync(storeId, branchId, actor, userId, req, ct);
                if (error != null)
                {
                    if (tx != null) await tx.RollbackAsync(ct);
                    db.ChangeTracker.Clear();
                    return (null, error);
                }
                if (tx != null) await tx.CommitAsync(ct);
                return (result, null);
            }
            catch (DbUpdateException ex) when (attempt < 2 &&
                (ex.InnerException?.Message?.Contains("IX_PosStockReceipts_StoreId_ReceiptNo") == true
                 || ex.InnerException?.Message?.Contains("duplicate key") == true))
            {
                // Hai máy cùng tạo phiếu → trùng mã phiếu / mã hàng: làm lại từ đầu với số mới.
                if (tx != null) await tx.RollbackAsync(ct);
                db.ChangeTracker.Clear();
            }
            catch
            {
                if (tx != null) await tx.RollbackAsync(CancellationToken.None);
                db.ChangeTracker.Clear();
                throw;
            }
            finally
            {
                if (tx != null) await tx.DisposeAsync();
            }
        }
    }

    async Task<(InvoiceConfirmResultDto? Result, string? Error)> ConfirmCoreAsync(
        Guid storeId, Guid? branchId, string? actor, Func<Guid> userId, InvoiceConfirmRequest req, CancellationToken ct)
    {
        var warnings = new List<string>();

        // 1. NCC: chọn sẵn / tạo mới (trùng MST / SĐT với NCC đã có → dùng NCC đó).
        Guid? supplierId = req.SupplierId;
        var supplierCreated = false;
        if (supplierId is Guid sid)
        {
            if (!await db.PosSuppliers.AnyAsync(s => s.Id == sid && s.StoreId == storeId && s.Deleted == null, ct))
                return (null, "Nhà cung cấp không hợp lệ.");
        }
        else if (req.CreateSupplier && !string.IsNullOrWhiteSpace(req.SupplierName))
        {
            var suppliers = await db.PosSuppliers.AsNoTracking()
                .Where(s => s.StoreId == storeId && s.Deleted == null)
                .Select(s => new InvoiceSupplierCandidate(s.Id, s.Name, s.CompanyName, s.Phone, s.TaxCode))
                .ToListAsync(ct);
            var (found, by) = PosAiInvoiceMatching.MatchSupplier(null, req.SupplierPhone, req.SupplierTaxCode, suppliers);
            if (found != null)
            {
                supplierId = found.Id;
                warnings.Add($"Đã có NCC «{found.Name}» cùng {(by == "taxCode" ? "mã số thuế" : "số điện thoại")} — dùng NCC này, không tạo mới.");
            }
            else
            {
                var s = new PosSupplier
                {
                    Id = Guid.NewGuid(),
                    StoreId = storeId,
                    SupplierCode = await PosPurchaseStockHelper.NextSupplierCodeAsync(db, storeId),
                    Name = Cap(req.SupplierName, 200)!,
                    Phone = Cap(req.SupplierPhone, 50),
                    TaxCode = Cap(req.SupplierTaxCode, 50),
                    Address = Cap(req.SupplierAddress, 500),
                    IsActive = true,
                    CreatedBy = actor,
                };
                db.PosSuppliers.Add(s);
                supplierId = s.Id;
                supplierCreated = true;
            }
        }

        // 2. Hàng: hàng đã chọn phải thuộc cửa hàng; dòng «tạo hàng mới» → hàng hóa (trùng tên hệt với hàng có sẵn → dùng hàng đó).
        var chosenIds = req.Lines.Where(l => l.ProductId != null).Select(l => l.ProductId!.Value).Distinct().ToList();
        var known = (await LoadProductsAsync(storeId, ct, chosenIds, onlyStock: false)).ToDictionary(p => p.Id);
        if (chosenIds.Any(id => !known.ContainsKey(id)))
            return (null, "Có dòng chọn hàng không còn tồn tại — tải lại rồi chọn hàng khác.");

        var newIds = new Dictionary<string, Guid>();
        var productsCreated = 0;
        var lineProducts = new List<InvoiceProductCandidate>();
        if (req.Lines.Any(l => l.ProductId == null))
        {
            var existingByName = (await db.PosProducts.AsNoTracking()
                    .Where(p => p.StoreId == storeId && p.Deleted == null)
                    .Select(p => new { p.Id, p.Name })
                    .ToListAsync(ct))
                .GroupBy(p => PosProductNameMatch.ExactKey(p.Name))
                .ToDictionary(g => g.Key, g => g.First().Id);
            var usedCodes = (await db.PosProducts.IgnoreQueryFilters().AsNoTracking()
                    .Where(p => p.StoreId == storeId)
                    .Select(p => p.ProductCode).ToListAsync(ct))
                .ToHashSet(StringComparer.OrdinalIgnoreCase);
            var prefix = PosProductTypeRules.CodePrefix(PosProductType.Goods);
            var nextNo = 1;
            foreach (var l in req.Lines.Where(l => l.ProductId == null))
            {
                var name = Cap(l.NewProductName ?? l.InvoiceName, 500)!;
                var key = PosProductNameMatch.ExactKey(name);
                if (newIds.ContainsKey(key)) continue;
                if (existingByName.TryGetValue(key, out var existingId))
                {
                    newIds[key] = existingId;
                    warnings.Add($"«{name}»: đã có hàng cùng tên — nhập vào hàng đó, không tạo mới.");
                    continue;
                }
                string code;
                do code = $"{prefix}{nextNo++:D5}"; while (usedCodes.Contains(code));
                usedCodes.Add(code);
                var unit = Cap(l.UnitName ?? l.InvoiceUnit, 100) ?? "Cái";
                var vatRate = l.VatExempt ? 0 : Math.Max(0, l.VatRate);
                var cost = l.VatIncluded && vatRate > 0 ? l.UnitPrice / (1 + vatRate / 100m) : l.UnitPrice;
                var product = new PosProduct
                {
                    Id = Guid.NewGuid(),
                    StoreId = storeId,
                    ProductCode = code,
                    Name = name,
                    ProductType = PosProductType.Goods,
                    CostPrice = Math.Round(Math.Max(0, cost), 2),
                    BasePrice = 0,
                    VatRate = l.VatExempt ? 0 : vatRate,
                    VatExempt = l.VatExempt,
                    BaseUnitName = unit,
                    SupplierId = supplierId,
                    IsDirectSale = true,
                    IsActive = true,
                    CreatedBy = actor,
                };
                db.PosProducts.Add(product);
                db.PosProductUnits.Add(new PosProductUnit
                {
                    Id = Guid.NewGuid(), StoreId = storeId, ProductId = product.Id,
                    UnitName = unit, ConversionRate = 1, BasePrice = 0,
                    IsDirectSale = true, IsBaseUnit = true, IsActive = true, CreatedBy = actor,
                });
                newIds[key] = product.Id;
                lineProducts.Add(new InvoiceProductCandidate(product.Id, product.Name, code, null, unit,
                    [new InvoiceUnitCandidate(Guid.Empty, unit, 1, true, null)]));
                productsCreated++;
            }
            if (productsCreated > 0)
                warnings.Add($"Đã tạo {productsCreated} hàng mới với giá bán 0đ — vào Hàng hóa đặt giá bán trước khi bán.");
        }
        // NCC / hàng mới phải có trong CSDL trước khi dựng phiếu (bộ dựng phiếu đọc lại từ CSDL).
        await db.SaveChangesAsync(ct);
        foreach (var p in lineProducts) known[p.Id] = p;
        var missingIds = newIds.Values.Where(id => !known.ContainsKey(id)).ToList();
        if (missingIds.Count > 0)
            foreach (var p in await LoadProductsAsync(storeId, ct, missingIds, onlyStock: false))
                known[p.Id] = p;

        // 3. Dòng phiếu: ĐVT hóa đơn → ĐVT của hàng; ĐVT chưa khai báo + có hệ số → quy về ĐVT gốc.
        var receiptLines = new List<PosPurchaseReceiptsController.ReceiptLineInput>();
        var resolved = new List<(InvoiceConfirmLineDto Line, Guid ProductId, string? UnitName, decimal Factor)>();
        for (var i = 0; i < req.Lines.Count; i++)
        {
            var l = req.Lines[i];
            var pid = l.ProductId ?? newIds[PosProductNameMatch.ExactKey(Cap(l.NewProductName ?? l.InvoiceName, 500))];
            var p = known[pid];
            var qty = l.Qty;
            var price = l.UnitPrice;
            var discount = Math.Max(0, l.Discount); // AI đọc nhầm dấu «-» → không để giảm giá âm đội giá vốn
            string? note = null;
            var u = PosAiInvoiceMatching.ResolveUnit(p, l.UnitName);
            string unitName;
            decimal factor = 1;
            if (u.Status is "base" or "unit")
            {
                unitName = u.UnitName; // phiếu tự quy đổi tồn theo ĐVT đã khai báo
            }
            else if (l.UnitFactor > 0 && l.UnitFactor != 1)
            {
                factor = l.UnitFactor;
                var lineAmount = qty * price;
                qty = Math.Round(qty * factor, 4);
                price = Math.Round(price / factor, 2);
                // Làm tròn đơn giá ĐVT gốc có thể làm thành tiền nhỉnh hơn hóa đơn → bù vào chiết khấu dòng.
                var diff = qty * price - lineAmount;
                if (diff > 0) discount += diff;
                note = $"HĐ: {Num(l.Qty)} {l.UnitName} × {Num(factor)} {p.BaseUnit}";
                unitName = p.BaseUnit;
            }
            else
            {
                unitName = p.BaseUnit;
                if (!string.IsNullOrWhiteSpace(l.UnitName))
                    warnings.Add($"«{p.Name}»: ĐVT hóa đơn «{l.UnitName!.Trim()}» chưa khai báo — nhập theo ĐVT gốc «{p.BaseUnit}» (SL {Num(qty)}).");
            }
            receiptLines.Add(new PosPurchaseReceiptsController.ReceiptLineInput(
                pid, null, qty, price, discount, l.VatExempt ? 0 : l.VatRate, l.VatIncluded, l.VatExempt, unitName, note));
            // Chỉ nhớ ĐVT khi chắc chắn: ĐVT quy đổi đã khai báo, hệ số người dùng nhập, hoặc hóa đơn ghi đúng ĐVT gốc.
            // (Người dùng tự đổi «Thùng» → «Lon» và sửa SL thì không nhớ — lần sau vẫn hỏi lại.)
            var invoiceUnit = l.InvoiceUnit ?? l.UnitName;
            var rememberUnit = u.Status == "unit" ? u.UnitName
                : factor != 1 ? p.BaseUnit
                : PosAiInvoiceMatching.UnitKey(invoiceUnit) == PosAiInvoiceMatching.UnitKey(p.BaseUnit) ? p.BaseUnit
                : null;
            resolved.Add((l, pid, rememberUnit, factor));
        }

        var noteParts = new List<string>();
        if (!string.IsNullOrWhiteSpace(req.Note)) noteParts.Add(req.Note.Trim());
        var invoiceText = "Nhập từ ảnh hóa đơn NCC"
                          + (string.IsNullOrWhiteSpace(req.InvoiceNo) ? "" : $" số {req.InvoiceNo.Trim()}")
                          + (req.InvoiceDate is DateTime d ? " ngày " + d.ToString("dd'/'MM'/'yyyy", CultureInfo.InvariantCulture) : "");
        noteParts.Add(invoiceText);
        var dto = new PosPurchaseReceiptsController.SaveReceiptDto(
            supplierId, Cap(string.Join(" — ", noteParts), 1000), Cap(req.InvoiceNo, 50), null,
            Math.Max(0, req.DiscountAmount), false, Math.Max(0, req.DiscountAmount),
            req.Complete ? Math.Max(0, req.PaidAmount) : 0, null, null,
            req.Complete, null, req.PaymentMethod, receiptLines,
            InputInvoiceDate: req.InvoiceDate);
        var (receipt, lines, err) = await PosPurchaseReceiptBuilder.BuildAsync(db, storeId, branchId, actor, null, dto, draft: !req.Complete);
        if (err != null) return (null, err);
        await PosPurchaseReceiptBuilder.StageNewAsync(db, storeId, receipt!, lines!, dto, actor, userId);

        // 4. Nhớ ánh xạ «tên trên hóa đơn (NCC) → hàng, ĐVT, hệ số».
        var saved = await SaveMappingsAsync(storeId, supplierId, resolved.Where(r => r.Line.Remember).ToList(), actor, ct);

        await db.SaveChangesAsync(ct);
        return (new InvoiceConfirmResultDto(receipt!.Id, receipt.ReceiptNo, receipt.Status.ToString(), receipt.GrandTotal,
            receipt.PaidAmount, supplierId, supplierCreated, productsCreated, saved,
            warnings.Count > 0 ? warnings : null), null);
    }

    async Task<int> SaveMappingsAsync(
        Guid storeId, Guid? supplierId,
        List<(InvoiceConfirmLineDto Line, Guid ProductId, string? UnitName, decimal Factor)> rows,
        string? actor, CancellationToken ct)
    {
        var byKey = new Dictionary<string, (InvoiceConfirmLineDto Line, Guid ProductId, string? UnitName, decimal Factor)>();
        foreach (var r in rows)
        {
            var key = PosProductNameMatch.FoldKey(r.Line.InvoiceName);
            if (key.Length == 0 || key.Length > 300) continue;
            byKey[key] = r;
        }
        if (byKey.Count == 0) return 0;
        var keys = byKey.Keys.ToList();
        // .AsTracking(): sửa ánh xạ cũ rồi SaveChanges (DbContext mặc định NoTracking).
        var existing = await db.PosAiInvoiceMappings.AsTracking()
            .Where(m => m.StoreId == storeId && m.SupplierId == supplierId && keys.Contains(m.NameKey))
            .ToListAsync(ct);
        var now = DateTime.UtcNow;
        foreach (var (key, r) in byKey)
        {
            var invoiceUnit = Cap(r.Line.InvoiceUnit ?? r.Line.UnitName, 100);
            var m = existing.FirstOrDefault(x => x.NameKey == key);
            if (m == null)
            {
                db.PosAiInvoiceMappings.Add(new PosAiInvoiceMapping
                {
                    Id = Guid.NewGuid(), StoreId = storeId, SupplierId = supplierId, NameKey = key,
                    InvoiceName = Cap(r.Line.InvoiceName, 500)!, ProductId = r.ProductId,
                    InvoiceUnit = invoiceUnit, UnitName = Cap(r.UnitName, 100), UnitFactor = r.Factor,
                    UseCount = 1, LastUsedAt = now, CreatedBy = actor,
                });
                continue;
            }
            m.InvoiceName = Cap(r.Line.InvoiceName, 500)!;
            m.ProductId = r.ProductId;
            m.InvoiceUnit = invoiceUnit;
            m.UnitName = Cap(r.UnitName, 100);
            m.UnitFactor = r.Factor;
            m.UseCount++;
            m.LastUsedAt = now;
            m.UpdatedAt = now;
            m.UpdatedBy = actor;
        }
        return byKey.Count;
    }

    // ─────────────────────────── Dữ liệu ───────────────────────────

    /// <summary>Hàng của cửa hàng (+ ĐVT) để đối chiếu; mặc định chỉ hàng quản lý tồn (hàng hóa / NVL / topping).</summary>
    async Task<List<InvoiceProductCandidate>> LoadProductsAsync(
        Guid storeId, CancellationToken ct, IReadOnlyCollection<Guid>? ids = null, bool onlyStock = true)
    {
        var q = db.PosProducts.AsNoTracking().Where(p => p.StoreId == storeId && p.Deleted == null);
        if (ids != null) q = q.Where(p => ids.Contains(p.Id));
        else q = q.Where(p => p.IsActive);
        if (onlyStock)
            q = q.Where(p => p.ProductType == PosProductType.Goods || p.ProductType == PosProductType.Material
                             || p.ProductType == PosProductType.Topping);
        var rows = await q
            .Select(p => new { p.Id, p.Name, p.ProductCode, p.Barcode, p.BaseUnitName, p.CostPrice, p.VatRate, p.VatExempt })
            .ToListAsync(ct);
        var pids = rows.Select(r => r.Id).ToList();
        var units = (await db.PosProductUnits.AsNoTracking()
                .Where(u => u.StoreId == storeId && u.Deleted == null && pids.Contains(u.ProductId))
                .Select(u => new { u.Id, u.ProductId, u.UnitName, u.ConversionRate, u.IsBaseUnit, u.Barcode })
                .ToListAsync(ct))
            .GroupBy(u => u.ProductId)
            .ToDictionary(g => g.Key, g => g.Select(u => new InvoiceUnitCandidate(u.Id, u.UnitName, u.ConversionRate, u.IsBaseUnit, u.Barcode)).ToList());
        return rows.Select(r => new InvoiceProductCandidate(
                r.Id, r.Name, r.ProductCode, r.Barcode, string.IsNullOrWhiteSpace(r.BaseUnitName) ? "Cái" : r.BaseUnitName,
                units.GetValueOrDefault(r.Id) ?? [], r.CostPrice, r.VatRate, r.VatExempt))
            .ToList();
    }

    async Task<List<InvoiceMappingCandidate>> LoadMappingsAsync(Guid storeId, Guid? supplierId, CancellationToken ct) =>
        await db.PosAiInvoiceMappings.AsNoTracking()
            .Where(m => m.StoreId == storeId && (m.SupplierId == null || m.SupplierId == supplierId))
            .OrderByDescending(m => m.LastUsedAt)
            .Select(m => new InvoiceMappingCandidate(m.SupplierId, m.NameKey, m.ProductId, m.InvoiceUnit, m.UnitName, m.UnitFactor))
            .ToListAsync(ct);

    static string LineLabel(InvoiceConfirmLineDto l, int i) =>
        string.IsNullOrWhiteSpace(l.InvoiceName ?? l.NewProductName) ? $"Dòng {i + 1}" : $"Dòng {i + 1} «{(l.InvoiceName ?? l.NewProductName)!.Trim()}»";

    /// <summary>Lệch trong ngưỡng làm tròn: 5đ hoặc 0,2%.</summary>
    static bool Near(decimal a, decimal b) => Math.Abs(a - b) <= Math.Max(5m, Math.Abs(b) * 0.002m);

    static string Vnd(decimal v) => Math.Round(v, 0).ToString("#,##0", CultureInfo.InvariantCulture).Replace(',', '.');

    static string Num(decimal v) => v.ToString("0.###", CultureInfo.InvariantCulture).Replace('.', ',');

    static string? Cap(string? s, int max)
    {
        if (string.IsNullOrWhiteSpace(s)) return null;
        var t = s.Trim();
        return t.Length > max ? t[..max] : t;
    }
}
