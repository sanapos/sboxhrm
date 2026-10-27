using System.Globalization;
using System.Text;

namespace ZKTecoADMS.Api.Services;

/// <summary>ĐVT của một hàng (dòng PosProductUnits; ĐVT gốc có <see cref="IsBase"/>).</summary>
public sealed record InvoiceUnitCandidate(Guid Id, string Name, decimal Rate, bool IsBase, string? Barcode);

/// <summary>Hàng của cửa hàng dùng để đối chiếu dòng hóa đơn.</summary>
public sealed record InvoiceProductCandidate(
    Guid Id, string Name, string Code, string? Barcode, string BaseUnit, IReadOnlyList<InvoiceUnitCandidate> Units,
    decimal CostPrice = 0, decimal VatRate = 0, bool VatExempt = false);

/// <summary>Ánh xạ đã nhớ: tên trên hóa đơn (của NCC) → hàng của cửa hàng.</summary>
public sealed record InvoiceMappingCandidate(
    Guid? SupplierId, string NameKey, Guid ProductId, string? InvoiceUnit, string? UnitName, decimal UnitFactor);

public sealed record InvoiceSupplierCandidate(Guid Id, string Name, string? CompanyName, string? Phone, string? TaxCode);

/// <summary>Cách chọn ĐVT cho dòng: base = ĐVT gốc; unit = ĐVT quy đổi đã khai báo; remembered = hệ số đã nhớ;
/// unknown = hóa đơn ghi ĐVT hàng chưa có (cần nhập hệ số / sửa SL).</summary>
public sealed record InvoiceUnitResolution(Guid? UnitId, string UnitName, decimal Factor, string Status);

public sealed record InvoiceProductMatch(
    InvoiceProductCandidate? Product, string? By, double Confidence, InvoiceMappingCandidate? Mapping,
    List<InvoiceProductCandidate> Possible);

/// <summary>
/// Đối chiếu dòng hóa đơn NCC với hàng của cửa hàng và đối chiếu NCC. Thứ tự hàng: ánh xạ đã nhớ (NCC này → cả cửa hàng)
/// → trùng tên hệt → mã vạch / mã hàng in trên hóa đơn → trùng tên bỏ dấu → gần đúng (<see cref="PosProductNameMatch.SameDish"/>,
/// chỉ khi một ứng viên rõ ràng). Không khớp → tối đa 3 gợi ý.
/// </summary>
public static class PosAiInvoiceMatching
{
    public const double ConfidenceMapping = 0.98;
    public const double ConfidenceExact = 0.95;
    public const double ConfidenceBarcode = 0.95;
    public const double ConfidenceCode = 0.85;
    public const double ConfidenceFold = 0.8;
    public const double ConfidenceFuzzy = 0.6;

    public static InvoiceProductMatch MatchProduct(
        string? name, string? code, Guid? supplierId,
        IReadOnlyList<InvoiceProductCandidate> products,
        IReadOnlyList<InvoiceMappingCandidate> mappings)
    {
        var byId = products.ToDictionary(p => p.Id);
        var key = PosProductNameMatch.FoldKey(name);
        if (key.Length > 0)
        {
            // NCC này trước, rồi ánh xạ không gắn NCC; hàng đã xóa thì bỏ qua.
            var mapped = mappings.FirstOrDefault(m => m.NameKey == key && supplierId != null && m.SupplierId == supplierId && byId.ContainsKey(m.ProductId))
                         ?? mappings.FirstOrDefault(m => m.NameKey == key && m.SupplierId == null && byId.ContainsKey(m.ProductId));
            if (mapped != null)
                return new(byId[mapped.ProductId], "remembered", ConfidenceMapping, mapped, []);
        }

        var exact = PosProductNameMatch.ExactKey(name);
        if (exact.Length > 0 && products.FirstOrDefault(p => PosProductNameMatch.ExactKey(p.Name) == exact) is { } ex)
            return new(ex, "name", ConfidenceExact, null, []);

        var c = (code ?? "").Trim();
        if (c.Length >= 3)
        {
            var bc = products.FirstOrDefault(p => Same(p.Barcode, c) || p.Units.Any(u => Same(u.Barcode, c)));
            if (bc != null) return new(bc, "barcode", ConfidenceBarcode, null, []);
            var pc = products.FirstOrDefault(p => Same(p.Code, c));
            if (pc != null) return new(pc, "code", ConfidenceCode, null, []);
        }

        if (key.Length > 0)
        {
            var fold = products.Where(p => PosProductNameMatch.FoldKey(p.Name) == key).ToList();
            if (fold.Count == 1) return new(fold[0], "fold", ConfidenceFold, null, []);
        }

        var ranked = Rank(name, products);
        var same = ranked.Where(r => PosProductNameMatch.SameDish(name, r.Product.Name)).ToList();
        // Gần đúng chỉ tự chọn khi một ứng viên rõ ràng (ứng viên thứ hai kém hẳn).
        if (same.Count == 1 || (same.Count > 1 && same[0].Score - same[1].Score >= 0.2))
            return new(same[0].Product, "fuzzy", ConfidenceFuzzy, null,
                ranked.Where(r => r.Product.Id != same[0].Product.Id).Take(3).Select(r => r.Product).ToList());
        return new(null, null, 0, null, ranked.Take(3).Select(r => r.Product).ToList());
    }

    /// <summary>Ứng viên theo độ giống tên (bỏ dấu, theo từ), giảm dần; chỉ ứng viên có điểm &gt; 0.</summary>
    public static List<(InvoiceProductCandidate Product, double Score)> Rank(
        string? name, IReadOnlyList<InvoiceProductCandidate> products)
    {
        var a = Tokens(name);
        if (a.Count == 0) return [];
        return products
            .Select(p => (Product: p, Score: Similarity(a, Tokens(p.Name))))
            .Where(x => x.Score >= 0.25)
            .OrderByDescending(x => x.Score)
            .ThenBy(x => x.Product.Name.Length)
            .ToList();
    }

    /// <summary>Độ giống 0–1: trung bình của tỉ lệ từ chung trên tên ngắn và trên hợp hai tên.</summary>
    public static double Similarity(string? a, string? b) => Similarity(Tokens(a), Tokens(b));

    static double Similarity(HashSet<string> a, HashSet<string> b)
    {
        if (a.Count == 0 || b.Count == 0) return 0;
        var common = a.Count(b.Contains);
        if (common == 0) return 0;
        var small = Math.Min(a.Count, b.Count);
        var union = a.Count + b.Count - common;
        return (common / (double)small + common / (double)union) / 2;
    }

    /// <summary>
    /// ĐVT hóa đơn → ĐVT trên phiếu nhập: rỗng / trùng ĐVT gốc → gốc; trùng ĐVT quy đổi đã khai báo → ĐVT đó (phiếu tự
    /// quy đổi tồn); ánh xạ đã nhớ có hệ số cho cùng ĐVT → dùng hệ số; còn lại → «unknown» (hệ số 1, cần người dùng xem).
    /// </summary>
    public static InvoiceUnitResolution ResolveUnit(
        InvoiceProductCandidate product, string? invoiceUnit, InvoiceMappingCandidate? mapping = null)
    {
        var baseUnit = product.Units.FirstOrDefault(u => u.IsBase);
        var u = UnitKey(invoiceUnit);
        if (u.Length == 0 || u == UnitKey(product.BaseUnit))
            return new(baseUnit?.Id, product.BaseUnit, 1, "base");
        var unit = product.Units.FirstOrDefault(x => !x.IsBase && x.Rate > 0 && UnitKey(x.Name) == u);
        if (unit != null) return new(unit.Id, unit.Name, unit.Rate, "unit");
        if (mapping != null && UnitKey(mapping.InvoiceUnit) == u)
        {
            // Lần trước người dùng chọn ĐVT quy đổi của hàng cho ĐVT hóa đơn này.
            var chosen = product.Units.FirstOrDefault(x => x.Rate > 0 && UnitKey(x.Name) == UnitKey(mapping.UnitName));
            if (chosen is { IsBase: false }) return new(chosen.Id, chosen.Name, chosen.Rate, "unit");
            if (mapping.UnitFactor > 0 && mapping.UnitFactor != 1)
                return new(baseUnit?.Id, invoiceUnit!.Trim(), mapping.UnitFactor, "remembered");
        }
        return new(null, invoiceUnit!.Trim(), 1, "unknown");
    }

    /// <summary>Khóa ĐVT: bỏ dấu + gộp cách viết thường gặp («kg» = «kí» = «kilogram», «th» = «thùng»…).</summary>
    public static string UnitKey(string? unit)
    {
        var k = PosProductNameMatch.FoldKey(unit);
        return k switch
        {
            "ki" or "ky" or "kilogram" or "kilo" or "kgs" => "kg",
            "gr" or "gram" or "gam" => "g",
            "lit" or "litre" or "liter" or "ltr" => "l",
            "chiec" => "cai",
            "th" or "thg" or "carton" or "ctn" or "thung" => "thung",
            "hp" or "box" => "hop",
            "bich" => "tui",
            "btl" or "bottle" => "chai",
            "pack" or "pck" => "goi",
            _ => k,
        };
    }

    /// <summary>NCC in trên hóa đơn → NCC đã có: mã số thuế → số điện thoại → tên (hoặc tên công ty) → gần đúng.</summary>
    public static (InvoiceSupplierCandidate? Supplier, string? By) MatchSupplier(
        string? name, string? phone, string? taxCode, IReadOnlyList<InvoiceSupplierCandidate> suppliers)
    {
        var tax = PosAiInvoiceParsing.Digits(taxCode);
        if (tax.Length >= 10 && suppliers.FirstOrDefault(s => PosAiInvoiceParsing.Digits(s.TaxCode) == tax) is { } byTax)
            return (byTax, "taxCode");
        var ph = PhoneKey(phone);
        if (ph.Length >= 9 && suppliers.FirstOrDefault(s => PhoneKey(s.Phone) == ph) is { } byPhone)
            return (byPhone, "phone");
        var key = PosProductNameMatch.FoldKey(StripCompanyWords(name));
        if (key.Length > 0)
        {
            var byName = suppliers.FirstOrDefault(s => PosProductNameMatch.FoldKey(StripCompanyWords(s.Name)) == key
                                                       || PosProductNameMatch.FoldKey(StripCompanyWords(s.CompanyName)) == key);
            if (byName != null) return (byName, "name");
            var near = suppliers.Where(s => PosProductNameMatch.SameDish(StripCompanyWords(name), StripCompanyWords(s.Name))
                                            || PosProductNameMatch.SameDish(StripCompanyWords(name), StripCompanyWords(s.CompanyName)))
                .ToList();
            if (near.Count == 1) return (near[0], "fuzzy");
        }
        return (null, null);
    }

    /// <summary>9 số cuối của điện thoại (bỏ +84 / 0 đầu); ít hơn 9 số → rỗng.</summary>
    public static string PhoneKey(string? phone)
    {
        var d = PosAiInvoiceParsing.Digits(phone);
        return d.Length >= 9 ? d[^9..] : "";
    }

    /// <summary>Bỏ «Công ty TNHH», «Cổ phần»… để so tên NCC («Cty TNHH Bia Sài Gòn» = «Bia Sài Gòn»).</summary>
    static string? StripCompanyWords(string? s)
    {
        if (string.IsNullOrWhiteSpace(s)) return s;
        var words = TokenList(s);
        // Chỉ bỏ cụm loại hình doanh nghiệp ở ĐẦU / CUỐI tên — giữ nguyên phần tên riêng («Thành Công» không bị cắt).
        string[][] lead =
        [
            ["cong", "ty"], ["cty"], ["tnhh"], ["co", "phan"], ["cp"], ["mot", "thanh", "vien"], ["1", "thanh", "vien"],
            ["mtv"], ["thuong", "mai"], ["dich", "vu"], ["tm"], ["dv"], ["tmdv"], ["san", "xuat"], ["sx"], ["xnk"],
            ["xuat", "nhap", "khau"], ["doanh", "nghiep", "tu", "nhan"], ["dntn"], ["ho", "kinh", "doanh"], ["hkd"], ["va"],
        ];
        string[][] tail = [["jsc"], ["co", "ltd"], ["ltd"], ["company"], ["corp"]];
        bool changed;
        do
        {
            changed = false;
            foreach (var p in lead)
            {
                if (words.Count > p.Length && words.Take(p.Length).SequenceEqual(p))
                {
                    words.RemoveRange(0, p.Length);
                    changed = true;
                }
            }
            foreach (var p in tail)
            {
                if (words.Count > p.Length && words.Skip(words.Count - p.Length).SequenceEqual(p))
                {
                    words.RemoveRange(words.Count - p.Length, p.Length);
                    changed = true;
                }
            }
        } while (changed);
        return string.Join(' ', words);
    }

    static bool Same(string? a, string? b) =>
        !string.IsNullOrWhiteSpace(a) && !string.IsNullOrWhiteSpace(b)
        && string.Equals(a.Trim(), b.Trim(), StringComparison.OrdinalIgnoreCase);

    /// <summary>Từ của tên (bỏ dấu, chữ thường, chỉ chữ / số).</summary>
    static HashSet<string> Tokens(string? s) => TokenList(s).ToHashSet();

    static List<string> TokenList(string? s)
    {
        var set = new List<string>();
        if (string.IsNullOrWhiteSpace(s)) return set;
        var sb = new StringBuilder();
        foreach (var ch in s.ToLowerInvariant().Normalize(NormalizationForm.FormD))
        {
            if (CharUnicodeInfo.GetUnicodeCategory(ch) == UnicodeCategory.NonSpacingMark) continue;
            var c = ch == 'đ' ? 'd' : ch;
            if (char.IsLetterOrDigit(c))
            {
                sb.Append(c);
                continue;
            }
            if (sb.Length > 0) set.Add(sb.ToString());
            sb.Clear();
        }
        if (sb.Length > 0) set.Add(sb.ToString());
        return set;
    }
}
