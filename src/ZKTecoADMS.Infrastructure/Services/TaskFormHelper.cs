using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>
/// Một trường biểu mẫu riêng của loại việc (số máy, nhiệt độ tủ, chữ ký khách…).
/// type: text / textarea / number / money / select / date / phone / checkbox / photo / signature / rating.
/// </summary>
public class TaskFormField
{
    [JsonPropertyName("key")] public string Key { get; set; } = string.Empty;
    [JsonPropertyName("label")] public string Label { get; set; } = string.Empty;
    [JsonPropertyName("type")] public string Type { get; set; } = "text";
    [JsonPropertyName("required")] public bool Required { get; set; }
    [JsonPropertyName("options")] public List<string>? Options { get; set; }
    [JsonPropertyName("unit")] public string? Unit { get; set; }
    [JsonPropertyName("hint")] public string? Hint { get; set; }
}

public static class TaskFormHelper
{
    public static readonly HashSet<string> Types =
    [
        "text", "textarea", "number", "money", "select", "date", "phone", "checkbox", "photo", "signature", "rating",
    ];

    static readonly JsonSerializerOptions Json = new()
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    public static List<TaskFormField> ParseSchema(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return [];
        try
        {
            return JsonSerializer.Deserialize<List<TaskFormField>>(raw) ?? [];
        }
        catch (JsonException)
        {
            return [];
        }
    }

    static string Slug(string s)
    {
        var normalized = s.Normalize(NormalizationForm.FormD);
        var sb = new System.Text.StringBuilder();
        foreach (var c in normalized)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(c) == UnicodeCategory.NonSpacingMark) continue;
            sb.Append(c == 'đ' || c == 'Đ' ? 'd' : char.ToLowerInvariant(c));
        }
        var k = Regex.Replace(sb.ToString(), "[^a-z0-9]+", "_").Trim('_');
        return k.Length == 0 ? "truong" : (k.Length > 40 ? k[..40] : k);
    }

    /// <summary>Chuẩn hoá biểu mẫu: bỏ trường rỗng / kiểu lạ, khoá duy nhất, select phải có lựa chọn. Rỗng → null.</summary>
    public static string? NormalizeSchema(string? raw) => SerializeSchema(Normalize(ParseSchema(raw)));

    public static List<TaskFormField> Normalize(IEnumerable<TaskFormField> fields)
    {
        var used = new HashSet<string>();
        var list = new List<TaskFormField>();
        foreach (var f in fields.Take(40))
        {
            var label = (f.Label ?? "").Trim();
            if (label.Length == 0) continue;
            var type = (f.Type ?? "text").Trim().ToLowerInvariant();
            if (!Types.Contains(type)) type = "text";
            var key = string.IsNullOrWhiteSpace(f.Key) ? Slug(label) : Slug(f.Key);
            var baseKey = key;
            for (var i = 2; !used.Add(key); i++) key = $"{baseKey}_{i}";
            var options = f.Options?.Select(o => o.Trim()).Where(o => o.Length > 0).Distinct().Take(30).ToList();
            if (type == "select" && (options == null || options.Count == 0)) type = "text";
            list.Add(new TaskFormField
            {
                Key = key,
                Label = label.Length > 120 ? label[..120] : label,
                Type = type,
                Required = f.Required,
                Options = type == "select" ? options : null,
                Unit = string.IsNullOrWhiteSpace(f.Unit) ? null : f.Unit.Trim(),
                Hint = string.IsNullOrWhiteSpace(f.Hint) ? null : f.Hint.Trim(),
            });
        }
        return list;
    }

    public static string? SerializeSchema(IReadOnlyCollection<TaskFormField>? fields) =>
        fields == null || fields.Count == 0 ? null : JsonSerializer.Serialize(fields, Json);

    public static Dictionary<string, string> ParseValues(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return new();
        try
        {
            using var doc = JsonDocument.Parse(raw);
            if (doc.RootElement.ValueKind != JsonValueKind.Object) return new();
            var d = new Dictionary<string, string>();
            foreach (var p in doc.RootElement.EnumerateObject())
                d[p.Name] = p.Value.ValueKind == JsonValueKind.String ? p.Value.GetString() ?? "" : p.Value.GetRawText();
            return d;
        }
        catch (JsonException)
        {
            return new();
        }
    }

    static bool HasValue(string? v) => !string.IsNullOrWhiteSpace(v) && v != "false" && v != "null";

    /// <summary>
    /// Gộp giá trị mới vào giá trị cũ (chỉ khoá có trong biểu mẫu), kiểm tra kiểu.
    /// Trả (JSON mới, lỗi) — lỗi ≠ null thì không lưu.
    /// </summary>
    public static (string? Json, string? Error) Merge(string? schemaRaw, string? oldRaw, IReadOnlyDictionary<string, string?> incoming)
    {
        var schema = ParseSchema(schemaRaw).ToDictionary(f => f.Key);
        var values = ParseValues(oldRaw);
        foreach (var (k, raw) in incoming)
        {
            if (!schema.TryGetValue(k, out var f)) continue;
            var v = (raw ?? "").Trim();
            if (v.Length == 0)
            {
                values.Remove(k);
                continue;
            }
            switch (f.Type)
            {
                case "number":
                case "money":
                    if (!decimal.TryParse(v.Replace(" ", ""), NumberStyles.Number, CultureInfo.InvariantCulture, out var n))
                        return (null, $"«{f.Label}» phải là số");
                    v = n.ToString(CultureInfo.InvariantCulture);
                    break;
                case "rating":
                    if (!int.TryParse(v, out var r) || r < 1 || r > 5) return (null, $"«{f.Label}» chấm từ 1 đến 5");
                    v = r.ToString(CultureInfo.InvariantCulture);
                    break;
                case "date":
                    if (!DateTime.TryParse(v, CultureInfo.InvariantCulture, DateTimeStyles.None, out var d))
                        return (null, $"«{f.Label}» không phải ngày hợp lệ");
                    v = d.ToString(d.TimeOfDay == TimeSpan.Zero ? "yyyy-MM-dd" : "yyyy-MM-ddTHH:mm", CultureInfo.InvariantCulture);
                    break;
                case "select":
                    if (f.Options != null && !f.Options.Contains(v)) return (null, $"«{f.Label}»: lựa chọn không hợp lệ");
                    break;
                case "checkbox":
                    v = v is "true" or "1" or "có" ? "true" : "false";
                    break;
                case "phone":
                    v = Regex.Replace(v, @"[^\d+]", "");
                    break;
                default:
                    if (v.Length > 4000) v = v[..4000];
                    break;
            }
            values[k] = v;
        }
        return (values.Count == 0 ? null : JsonSerializer.Serialize(values, Json), null);
    }

    /// <summary>Nhãn các trường bắt buộc còn trống.</summary>
    public static List<string> MissingRequired(string? schemaRaw, string? valuesRaw)
    {
        var values = ParseValues(valuesRaw);
        return ParseSchema(schemaRaw)
            .Where(f => f.Required && !HasValue(values.GetValueOrDefault(f.Key)))
            .Select(f => f.Label)
            .ToList();
    }
}
