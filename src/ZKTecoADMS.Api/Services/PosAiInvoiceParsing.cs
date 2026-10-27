using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace ZKTecoADMS.Api.Services;

/// <summary>Thuế suất GTGT đọc từ hóa đơn: số % (null = không ghi) hoặc «KCT» (không chịu thuế).</summary>
public readonly record struct InvoiceVatValue(decimal? Rate, bool Exempt)
{
    public static readonly InvoiceVatValue None = new(null, false);
    public bool HasValue => Rate != null || Exempt;
}

/// <summary>Một dòng hàng AI đọc từ ảnh hóa đơn (chưa chuẩn hóa / chưa đối chiếu).</summary>
internal sealed class RawInvoiceLine
{
    public string? Name { get; set; }
    public string? Code { get; set; }
    public decimal? Qty { get; set; }
    public string? Unit { get; set; }
    public LenientPrice UnitPrice { get; set; } = new(null, MenuPriceFlag.None, null);
    public LenientPrice LineTotal { get; set; } = new(null, MenuPriceFlag.None, null);
    public LenientPrice Discount { get; set; } = new(null, MenuPriceFlag.None, null);
    public decimal? DiscountPercent { get; set; }
    public InvoiceVatValue Vat { get; set; } = InvoiceVatValue.None;
    /// <summary>AI báo dòng mờ / bị che, đọc không chắc.</summary>
    public bool Unreadable { get; set; }
    /// <summary>Ảnh thứ mấy (từ 0) — lớp gọi gán khi gộp nhiều ảnh.</summary>
    public int Page { get; set; }
}

/// <summary>Kết quả AI đọc một ảnh hóa đơn.</summary>
internal sealed class RawInvoice
{
    public string? SupplierName { get; set; }
    public string? SupplierPhone { get; set; }
    public string? SupplierTaxCode { get; set; }
    public string? SupplierAddress { get; set; }
    public string? InvoiceNo { get; set; }
    public DateTime? InvoiceDate { get; set; }
    public bool? PricesIncludeVat { get; set; }
    public InvoiceVatValue Vat { get; set; } = InvoiceVatValue.None;
    public LenientPrice Subtotal { get; set; } = new(null, MenuPriceFlag.None, null);
    public LenientPrice Discount { get; set; } = new(null, MenuPriceFlag.None, null);
    public LenientPrice VatAmount { get; set; } = new(null, MenuPriceFlag.None, null);
    public LenientPrice Total { get; set; } = new(null, MenuPriceFlag.None, null);
    public List<RawInvoiceLine> Lines { get; set; } = [];
    /// <summary>Số dòng AI trả sai định dạng (đã bỏ).</summary>
    public int BadLines { get; set; }
}

/// <summary>
/// Đọc JSON hóa đơn NCC AI trả về một cách «dễ tính»: số dạng chuỗi kiểu Việt Nam («1.234.567», «2,5», «35k»),
/// thuế suất «8%» / «0,08» / «KCT», ngày «Ngày 12 tháng 03 năm 2026», dòng hỏng thì bỏ dòng đó.
/// Tiền dùng chung bộ đọc giá của «AI thêm menu» (<see cref="MenuPriceParser"/>).
/// </summary>
internal static class PosAiInvoiceParsing
{
    static readonly Regex NumberRx = new(@"\d+(?:[.,]\d+)*", RegexOptions.CultureInvariant);

    /// <summary>Hóa đơn từ JSON (object; mảng trần = chỉ danh sách dòng). JSON hỏng → JsonException.</summary>
    public static RawInvoice Parse(string json)
    {
        using var doc = JsonDocument.Parse(json, new JsonDocumentOptions { AllowTrailingCommas = true });
        var root = doc.RootElement;
        var inv = new RawInvoice();
        if (root.ValueKind == JsonValueKind.Array)
        {
            ReadLines(root, inv);
            return inv;
        }
        if (root.ValueKind != JsonValueKind.Object) return inv;
        ReadHeader(root, inv);
        var lines = Prop(root, "lines") ?? Prop(root, "items");
        if (lines is { ValueKind: JsonValueKind.Array } arr) ReadLines(arr, inv);
        return inv;
    }

    /// <summary>
    /// JSON bị cắt giữa chừng (hết độ dài trả lời / hỏng cuối): giữ phần đầu hóa đơn (NCC, số, ngày — đứng trước
    /// «lines») và các dòng đã trả đủ. Không lấy được gì → hóa đơn rỗng.
    /// </summary>
    public static RawInvoice Salvage(string partial)
    {
        var inv = new RawInvoice();
        if (string.IsNullOrEmpty(partial)) return inv;
        var idx = partial.IndexOf("\"lines\"", StringComparison.OrdinalIgnoreCase);
        if (idx < 0) idx = partial.IndexOf("\"items\"", StringComparison.OrdinalIgnoreCase);
        if (idx < 0) return inv;
        var head = partial[..idx].TrimEnd().TrimEnd(',') + "}";
        try
        {
            using var doc = JsonDocument.Parse(head, new JsonDocumentOptions { AllowTrailingCommas = true });
            if (doc.RootElement.ValueKind == JsonValueKind.Object) ReadHeader(doc.RootElement, inv);
        }
        catch (JsonException)
        {
            // phần đầu cũng hỏng — chỉ lấy dòng hàng
        }
        try
        {
            using var lines = JsonDocument.Parse(PosAiMenuJson.SalvageTruncated(partial[idx..]));
            ReadLines(lines.RootElement, inv);
        }
        catch (JsonException)
        {
            // không lấy được dòng nào
        }
        return inv;
    }

    static void ReadHeader(JsonElement root, RawInvoice inv)
    {
        var sup = Prop(root, "supplier") ?? Prop(root, "seller");
        if (sup is { ValueKind: JsonValueKind.Object } s)
        {
            inv.SupplierName = Str(Prop(s, "name"));
            inv.SupplierPhone = Str(Prop(s, "phone"));
            inv.SupplierTaxCode = Str(Prop(s, "taxCode"));
            inv.SupplierAddress = Str(Prop(s, "address"));
        }
        else if (sup is { ValueKind: JsonValueKind.String } sn)
        {
            inv.SupplierName = sn.GetString();
        }
        inv.SupplierName ??= Str(Prop(root, "supplierName"));
        inv.SupplierPhone ??= Str(Prop(root, "supplierPhone"));
        inv.SupplierTaxCode ??= Str(Prop(root, "supplierTaxCode")) ?? Str(Prop(root, "taxCode"));
        inv.InvoiceNo = Clean(Str(Prop(root, "invoiceNo")));
        inv.InvoiceDate = ParseDate(Str(Prop(root, "invoiceDate")));
        inv.PricesIncludeVat = Bool(Prop(root, "pricesIncludeVat"));
        inv.Vat = ParseVat(Prop(root, "vatRate"));
        inv.Subtotal = Money(Prop(root, "subtotal"));
        inv.Discount = Money(Prop(root, "discount"));
        inv.VatAmount = Money(Prop(root, "vat"));
        inv.Total = Money(Prop(root, "total"));
    }

    static void ReadLines(JsonElement arr, RawInvoice inv)
    {
        if (arr.ValueKind != JsonValueKind.Array) return;
        foreach (var e in arr.EnumerateArray())
        {
            try
            {
                if (e.ValueKind != JsonValueKind.Object)
                {
                    inv.BadLines++;
                    continue;
                }
                inv.Lines.Add(new RawInvoiceLine
                {
                    Name = Clean(Str(Prop(e, "name"))),
                    Code = Clean(Str(Prop(e, "code"))),
                    Qty = ParseQty(Prop(e, "qty")),
                    Unit = Clean(Str(Prop(e, "unit"))),
                    UnitPrice = Money(Prop(e, "unitPrice")),
                    LineTotal = Money(Prop(e, "lineTotal")),
                    Discount = Money(Prop(e, "discount")),
                    DiscountPercent = ParsePercent(Prop(e, "discountPercent")),
                    Vat = ParseVat(Prop(e, "vatRate")),
                    Unreadable = Bool(Prop(e, "unreadable")) == true,
                });
            }
            catch (Exception ex) when (ex is InvalidOperationException or FormatException or OverflowException or ArgumentException)
            {
                inv.BadLines++;
            }
        }
    }

    /// <summary>Tiền: số / chuỗi «1.234.567đ» / «(50.000)» (chiết khấu ghi trong ngoặc) — luôn không âm.</summary>
    public static LenientPrice Money(JsonElement? e)
    {
        if (e is { ValueKind: JsonValueKind.String } s)
        {
            var t = (s.GetString() ?? "").Trim().Trim('(', ')').Trim();
            if (t.StartsWith('-')) t = t[1..];
            var p = MenuPriceParser.Parse(t);
            return p.Value is decimal v ? p with { Value = Math.Abs(v) } : p;
        }
        var r = MenuPriceParser.FromJson(e);
        return r.Value is decimal n ? r with { Value = Math.Abs(n) } : r;
    }

    /// <summary>Số lượng: 2 / "2" / "2,5" / "1.000" / "12 thùng" → số; không đọc được → null.</summary>
    public static decimal? ParseQty(JsonElement? e)
    {
        switch (e?.ValueKind)
        {
            case JsonValueKind.Number:
                return e.Value.TryGetDecimal(out var d) ? Math.Abs(d) : null;
            case JsonValueKind.String:
                return ParseQtyText(e.Value.GetString());
            default:
                return null;
        }
    }

    public static decimal? ParseQtyText(string? text)
    {
        var m = NumberRx.Match(text ?? "");
        return m.Success ? MenuPriceParser.ParseNumber(m.Value) : null;
    }

    /// <summary>«8%» / 8 / 0.08 / «8,0» → 8; «KCT» / «không chịu thuế» → miễn thuế; «x» / «-» / rỗng → không ghi.</summary>
    public static InvoiceVatValue ParseVat(JsonElement? e)
    {
        switch (e?.ValueKind)
        {
            case JsonValueKind.Number:
                return e.Value.TryGetDecimal(out var d) ? new(NormalizeRate(d), false) : InvoiceVatValue.None;
            case JsonValueKind.String:
                return ParseVatText(e.Value.GetString());
            default:
                return InvoiceVatValue.None;
        }
    }

    public static InvoiceVatValue ParseVatText(string? text)
    {
        var t = (text ?? "").Trim().ToLowerInvariant();
        if (t.Length == 0) return InvoiceVatValue.None;
        var fold = PosProductNameMatch.FoldKey(t);
        if (fold is "kct" or "kkknt" or "khongchiuthue" or "khongkekhainopthue" || fold.StartsWith("khongchiu", StringComparison.Ordinal))
            return new(0, true);
        var m = NumberRx.Match(t);
        if (!m.Success) return InvoiceVatValue.None;
        var n = MenuPriceParser.ParseNumber(m.Value);
        return n == null ? InvoiceVatValue.None : new(NormalizeRate(n.Value), false);
    }

    /// <summary>Thuế suất dạng tỉ lệ (0,08) → % (8); làm tròn 2 chữ số; ngoài 0–100 → bỏ.</summary>
    static decimal? NormalizeRate(decimal v)
    {
        v = Math.Abs(v);
        if (v > 0 && v < 1) v *= 100;
        if (v > 100) return null;
        return Math.Round(v, 2);
    }

    static decimal? ParsePercent(JsonElement? e)
    {
        var v = e?.ValueKind switch
        {
            JsonValueKind.Number => e.Value.TryGetDecimal(out var d) ? d : (decimal?)null,
            JsonValueKind.String => ParseQtyText(e.Value.GetString()),
            _ => null,
        };
        return v is > 0 and <= 100 ? v : null;
    }

    /// <summary>«12/03/2026», «12-3-26», «2026-03-12», «Ngày 12 tháng 03 năm 2026» → ngày (không giờ); sai → null.</summary>
    public static DateTime? ParseDate(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        var t = text.Trim();
        var iso = Regex.Match(t, @"(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})");
        if (iso.Success) return Make(iso.Groups[1].Value, iso.Groups[2].Value, iso.Groups[3].Value);
        var vn = Regex.Match(t, @"(\d{1,2})\D{1,12}?(\d{1,2})\D{1,12}?(\d{4}|\d{2})(?!\d)");
        return vn.Success ? Make(vn.Groups[3].Value, vn.Groups[2].Value, vn.Groups[1].Value) : null;

        static DateTime? Make(string y, string m, string d)
        {
            var year = int.Parse(y, CultureInfo.InvariantCulture);
            if (year < 100) year += 2000;
            var month = int.Parse(m, CultureInfo.InvariantCulture);
            var day = int.Parse(d, CultureInfo.InvariantCulture);
            if (year < 2000 || year > 2100 || month is < 1 or > 12 || day < 1 || day > DateTime.DaysInMonth(year, month))
                return null;
            return new DateTime(year, month, day, 0, 0, 0, DateTimeKind.Unspecified);
        }
    }

    /// <summary>Chỉ giữ chữ số (mã số thuế / số điện thoại).</summary>
    public static string Digits(string? s) => new((s ?? "").Where(char.IsDigit).ToArray());

    static string? Clean(string? s)
    {
        if (string.IsNullOrWhiteSpace(s)) return null;
        var t = Regex.Replace(s.Trim(), @"\s+", " ");
        return t is "null" or "-" or "—" ? null : t;
    }

    static JsonElement? Prop(JsonElement e, string name)
    {
        if (e.ValueKind != JsonValueKind.Object) return null;
        foreach (var p in e.EnumerateObject())
            if (string.Equals(p.Name, name, StringComparison.OrdinalIgnoreCase))
                return p.Value;
        return null;
    }

    static string? Str(JsonElement? e) => e?.ValueKind switch
    {
        JsonValueKind.String => e.Value.GetString(),
        JsonValueKind.Number => e.Value.GetRawText(),
        _ => null,
    };

    static bool? Bool(JsonElement? e) => e?.ValueKind switch
    {
        JsonValueKind.True => true,
        JsonValueKind.False => false,
        JsonValueKind.String => (e.Value.GetString() ?? "").Trim().ToLowerInvariant() switch
        {
            "true" or "yes" or "có" or "co" or "1" => true,
            "false" or "no" or "không" or "khong" or "0" => false,
            _ => null,
        },
        JsonValueKind.Number => e.Value.TryGetInt32(out var i) ? i != 0 : null,
        _ => null,
    };
}
