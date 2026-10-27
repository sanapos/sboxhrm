using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace ZKTecoADMS.Api.Services;

/// <summary>Tình trạng giá AI đọc được (để báo trên màn xem trước).</summary>
public enum MenuPriceFlag
{
    None = 0,
    /// <summary>Khoảng giá «25-30k» — lấy giá thấp.</summary>
    Range = 1,
    /// <summary>«Thời giá» / «liên hệ» — giá 0, người dùng tự nhập.</summary>
    AskPrice = 2,
    /// <summary>Chuỗi không đọc được thành giá.</summary>
    Unreadable = 3,
}

/// <summary>Giá đọc từ JSON của AI: số, null hoặc chuỗi tự do («35k», «1tr2», «25.000đ», «25-30k», «thời giá»).</summary>
public sealed record LenientPrice(decimal? Value, MenuPriceFlag Flag, string? Raw);

/// <summary>
/// Đọc giá kiểu Việt Nam: «35k» / «35 nghìn» = 35.000; «1tr2» = 1.200.000; «1,5tr»; «25.000» / «25,000đ» = 25.000;
/// «25.5» = 25,5 (số thập phân — lớp gọi tự nhân nghìn nếu &lt; 1.000); khoảng «25-30k» → giá thấp 25.000.
/// </summary>
public static class MenuPriceParser
{
    static readonly string[] AskWords =
    [
        "thời giá", "thoi gia", "liên hệ", "lien he", "giá thị trường", "gia thi truong", "theo giá", "theo gia",
        "tùy", "tuỳ", "tuy size", "market", "call", "hỏi giá", "hoi gia",
    ];

    static readonly Regex Single = new(
        @"^(\d+(?:[.,]\d+)*)(k|nghìn|nghin|ngàn|ngan|tr|triệu|trieu|m)?(\d{1,3})?$",
        RegexOptions.CultureInvariant);

    public static LenientPrice Parse(string? text)
    {
        var raw = text?.Trim();
        if (string.IsNullOrEmpty(raw)) return new(null, MenuPriceFlag.None, null);
        var s = raw.Normalize(NormalizationForm.FormC).ToLowerInvariant();
        if (AskWords.Any(w => s.Contains(w, StringComparison.Ordinal)) || s is "tg" or "lh" or "?")
            return new(0, MenuPriceFlag.AskPrice, raw);

        // «35k/ly», «200k / giờ» → bỏ đơn vị sau dấu «/».
        var slash = s.IndexOf('/');
        if (slash > 0) s = s[..slash];
        foreach (var w in new[] { "vnđ", "vnd", "đồng", "dong", "₫", "+" })
            s = s.Replace(w, "", StringComparison.Ordinal);
        s = Regex.Replace(s, @"\s*(đến|den|tới|toi|~|–|—)\s*", "-");
        s = Regex.Replace(s, @"\s+", "");
        // «25.000đ» / «25000d»: chữ đ / d ở cuối số.
        s = Regex.Replace(s, @"(?<=\d)[đd](?=$|-)", "");
        if (s.Length == 0) return new(null, MenuPriceFlag.Unreadable, raw);

        var parts = s.Split('-', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 0) return new(null, MenuPriceFlag.Unreadable, raw);
        if (parts.Length == 1)
        {
            var v = ParseSingle(parts[0], null);
            return v == null ? new(null, MenuPriceFlag.Unreadable, raw) : new(v, MenuPriceFlag.None, raw);
        }

        // Khoảng giá: hậu tố của đầu cuối áp cho đầu thấp khi đầu thấp không ghi («25-30k»).
        var lastSuffix = Single.Match(parts[^1]) is { Success: true } lm && lm.Groups[2].Success ? lm.Groups[2].Value : null;
        var low = ParseSingle(parts[0], lastSuffix);
        return low == null ? new(null, MenuPriceFlag.Unreadable, raw) : new(low, MenuPriceFlag.Range, raw);
    }

    static decimal? ParseSingle(string s, string? fallbackSuffix)
    {
        var m = Single.Match(s);
        if (!m.Success) return null;
        var number = ParseNumber(m.Groups[1].Value);
        if (number == null) return null;
        var suffix = m.Groups[2].Success ? m.Groups[2].Value : null;
        var tail = m.Groups[3].Success ? m.Groups[3].Value : null;
        if (suffix == null && tail != null) return null;
        // Chỉ mượn hậu tố của đầu kia khi đầu này là số nhỏ («25-30k»), không mượn cho «25.000-30k».
        if (suffix == null && fallbackSuffix != null && number < 1000) suffix = fallbackSuffix;
        var mult = suffix switch
        {
            null => 1m,
            "tr" or "triệu" or "trieu" or "m" => 1_000_000m,
            _ => 1000m,
        };
        if (tail != null)
        {
            // «1tr2» = 1,2 triệu; «2k5» = 2,5 nghìn; «1tr250» = 1,25 triệu.
            number = decimal.Parse(((long)number).ToString(CultureInfo.InvariantCulture) + "." + tail, CultureInfo.InvariantCulture);
        }
        return number * mult;
    }

    /// <summary>«25.000» / «25,000» / «1.234.567» = phân cách nghìn; «25.5» / «1,5» = thập phân; «1.234,5» kiểu VN.</summary>
    public static decimal? ParseNumber(string s)
    {
        if (string.IsNullOrEmpty(s)) return null;
        if (Regex.IsMatch(s, @"^\d{1,3}([.,]\d{3})+$") && !(s.Contains('.') && s.Contains(',')))
            return decimal.Parse(s.Replace(".", "").Replace(",", ""), CultureInfo.InvariantCulture);
        var lastDot = s.LastIndexOf('.');
        var lastComma = s.LastIndexOf(',');
        var dec = Math.Max(lastDot, lastComma);
        if (dec < 0) return decimal.TryParse(s, NumberStyles.None, CultureInfo.InvariantCulture, out var n) ? n : null;
        var intPart = s[..dec].Replace(".", "").Replace(",", "");
        var frac = s[(dec + 1)..];
        if (intPart.Length == 0 || frac.Length == 0) return null;
        return decimal.TryParse(intPart + "." + frac, NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out var d) ? d : null;
    }

    /// <summary>Giá từ phần tử JSON bất kỳ (số / chuỗi / null / kiểu lạ) — không bao giờ ném lỗi.</summary>
    public static LenientPrice FromJson(JsonElement? e)
    {
        if (e is not JsonElement el) return new(null, MenuPriceFlag.None, null);
        switch (el.ValueKind)
        {
            case JsonValueKind.Number:
                if (el.TryGetDecimal(out var d)) return new(d, MenuPriceFlag.None, null);
                return el.TryGetDouble(out var db) && !double.IsNaN(db) && !double.IsInfinity(db) && Math.Abs(db) < 1e15
                    ? new((decimal)db, MenuPriceFlag.None, null)
                    : new(null, MenuPriceFlag.Unreadable, el.GetRawText());
            case JsonValueKind.String:
                return Parse(el.GetString());
            case JsonValueKind.Null:
            case JsonValueKind.Undefined:
                return new(null, MenuPriceFlag.None, null);
            default:
                return new(null, MenuPriceFlag.Unreadable, el.GetRawText());
        }
    }

    /// <summary>Menu ghi đơn vị nghìn («35» = 35.000): giá 0 &lt; p &lt; 1.000 → ×1.000.</summary>
    public static decimal FixMissingThousand(decimal price, out bool scaled)
    {
        scaled = price > 0 && price < 1000;
        return Math.Round(scaled ? price * 1000 : price, 0, MidpointRounding.AwayFromZero);
    }
}

/// <summary>Đọc JSON món AI trả về một cách «dễ tính»: món nào hỏng thì bỏ món đó, không làm hỏng cả lần quét.</summary>
internal static class PosAiMenuJson
{
    internal sealed class RawSize
    {
        public string? Name { get; set; }
        public LenientPrice Price { get; set; } = new(null, MenuPriceFlag.None, null);
    }

    internal sealed class RawComboItem
    {
        public string? Name { get; set; }
        public decimal? Qty { get; set; }
    }

    internal sealed class RawItem
    {
        public string? Name { get; set; }
        public string? Category { get; set; }
        public LenientPrice Price { get; set; } = new(null, MenuPriceFlag.None, null);
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

    /// <summary>Danh sách món từ {"items":[...]}, mảng trần, hoặc object có mảng khác tên. JSON hỏng → JsonException.</summary>
    internal static List<RawItem> ParseItems(string json, out int badItems)
    {
        badItems = 0;
        using var doc = JsonDocument.Parse(json, new JsonDocumentOptions { AllowTrailingCommas = true });
        var root = doc.RootElement;
        JsonElement? arr = null;
        if (root.ValueKind == JsonValueKind.Array) arr = root;
        else if (root.ValueKind == JsonValueKind.Object)
        {
            arr = Prop(root, "items") is { ValueKind: JsonValueKind.Array } items
                ? items
                : root.EnumerateObject().Select(p => (JsonElement?)p.Value).FirstOrDefault(v => v?.ValueKind == JsonValueKind.Array);
            if (arr == null && Prop(root, "name") != null)
            {
                var one = ReadItem(root);
                return one == null ? [] : [one];
            }
        }
        var list = new List<RawItem>();
        if (arr is not JsonElement a) return list;
        foreach (var e in a.EnumerateArray())
        {
            try
            {
                var item = ReadItem(e);
                if (item != null) list.Add(item);
                else badItems++;
            }
            catch (Exception ex) when (ex is InvalidOperationException or FormatException or OverflowException or ArgumentException)
            {
                badItems++;
            }
        }
        return list;
    }

    /// <summary>
    /// JSON bị cắt giữa chừng (hết độ dài trả lời): giữ các món đã trả đủ trong mảng «items».
    /// Trả mảng JSON các món hoàn chỉnh (có thể rỗng).
    /// </summary>
    internal static string SalvageTruncated(string partial)
    {
        if (string.IsNullOrEmpty(partial)) return "[]";
        var start = -1;
        var itemsIdx = partial.IndexOf("\"items\"", StringComparison.OrdinalIgnoreCase);
        if (itemsIdx >= 0) start = partial.IndexOf('[', itemsIdx);
        if (start < 0) start = partial.IndexOf('[');
        if (start < 0) return "[]";
        var complete = new List<string>();
        int depth = 0, objStart = -1;
        bool inString = false, escape = false;
        for (var i = start + 1; i < partial.Length; i++)
        {
            var ch = partial[i];
            if (inString)
            {
                if (escape) escape = false;
                else if (ch == '\\') escape = true;
                else if (ch == '"') inString = false;
                continue;
            }
            if (ch == '"') { inString = true; continue; }
            if (ch == '{' || ch == '[')
            {
                if (depth == 0 && ch == '{') objStart = i;
                depth++;
            }
            else if (ch == '}' || ch == ']')
            {
                if (depth == 0) break; // hết mảng items
                depth--;
                if (depth == 0 && ch == '}' && objStart >= 0)
                {
                    complete.Add(partial[objStart..(i + 1)]);
                    objStart = -1;
                }
            }
        }
        return "[" + string.Join(",", complete) + "]";
    }

    static RawItem? ReadItem(JsonElement e)
    {
        if (e.ValueKind != JsonValueKind.Object) return null;
        return new RawItem
        {
            Name = Str(Prop(e, "name")),
            Category = Str(Prop(e, "category")),
            Price = MenuPriceParser.FromJson(Prop(e, "price")),
            Sizes = Arr(Prop(e, "sizes"))?.Select(s => s.ValueKind == JsonValueKind.Object
                    ? new RawSize { Name = Str(Prop(s, "name")), Price = MenuPriceParser.FromJson(Prop(s, "price")) }
                    : null)
                .Where(s => s != null).Cast<RawSize>().ToList(),
            Unit = Str(Prop(e, "unit")),
            Description = Str(Prop(e, "description")),
            CatalogIndex = Int(Prop(e, "catalogIndex")),
            Type = Str(Prop(e, "type")),
            Billing = Str(Prop(e, "billing")),
            Sessions = Int(Prop(e, "sessions")),
            ToppingFor = StrList(Prop(e, "toppingFor")),
            ComboItems = Arr(Prop(e, "comboItems"))?.Select(c => c.ValueKind switch
                {
                    JsonValueKind.Object => new RawComboItem { Name = Str(Prop(c, "name")), Qty = Dec(Prop(c, "qty")) },
                    JsonValueKind.String => new RawComboItem { Name = c.GetString(), Qty = 1 },
                    _ => null,
                })
                .Where(c => c != null).Cast<RawComboItem>().ToList(),
        };
    }

    static JsonElement? Prop(JsonElement e, string name)
    {
        if (e.ValueKind != JsonValueKind.Object) return null;
        foreach (var p in e.EnumerateObject())
            if (string.Equals(p.Name, name, StringComparison.OrdinalIgnoreCase))
                return p.Value;
        return null;
    }

    static IEnumerable<JsonElement>? Arr(JsonElement? e) =>
        e is { ValueKind: JsonValueKind.Array } a ? a.EnumerateArray().ToList() : null;

    static string? Str(JsonElement? e) => e?.ValueKind switch
    {
        JsonValueKind.String => e.Value.GetString(),
        JsonValueKind.Number => e.Value.GetRawText(),
        JsonValueKind.True => "true",
        JsonValueKind.False => "false",
        _ => null,
    };

    /// <summary>«toppingFor»: mảng tên hoặc một chuỗi «Trà sữa, Trà trái cây».</summary>
    static List<string?>? StrList(JsonElement? e) => e?.ValueKind switch
    {
        JsonValueKind.Array => e.Value.EnumerateArray().Select(x => Str(x)).ToList(),
        JsonValueKind.String => (e.Value.GetString() ?? "").Split([',', ';'], StringSplitOptions.RemoveEmptyEntries)
            .Select(x => (string?)x.Trim()).ToList(),
        _ => null,
    };

    static int? Int(JsonElement? e)
    {
        switch (e?.ValueKind)
        {
            case JsonValueKind.Number:
                if (e.Value.TryGetInt32(out var i)) return i;
                return e.Value.TryGetDouble(out var d) && d is > int.MinValue and < int.MaxValue ? (int)Math.Round(d) : null;
            case JsonValueKind.String:
                var m = Regex.Match(e.Value.GetString() ?? "", @"-?\d+");
                return m.Success && int.TryParse(m.Value, out var n) ? n : null;
            default:
                return null;
        }
    }

    static decimal? Dec(JsonElement? e) => e?.ValueKind switch
    {
        JsonValueKind.Number => e.Value.TryGetDecimal(out var d) ? d : null,
        JsonValueKind.String => MenuPriceParser.ParseNumber(Regex.Match(e.Value.GetString() ?? "", @"\d+(?:[.,]\d+)?").Value),
        _ => null,
    };
}
