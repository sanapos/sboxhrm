using System.Linq;
using System.Text.Json;

namespace ZKTecoADMS.Api.Services;

/// <summary>Tra cứu MST doanh nghiệp qua VietQR (CQT).</summary>
public static class VietQrBusinessLookup
{
    public sealed record Result(
        bool Ok,
        string? Message,
        string? TaxCode,
        string? Name,
        string? InternationalName,
        string? ShortName,
        string? Address);

    public static async Task<Result> LookupAsync(string? taxCode, CancellationToken ct = default)
    {
        var code = NormalizeTaxCode(taxCode);
        if (code == null)
            return new Result(false, "Mã số thuế không hợp lệ (10 số, hoặc 10-3 chi nhánh)",
                null, null, null, null, null);
        try
        {
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(8) };
            http.DefaultRequestHeaders.TryAddWithoutValidation("Accept", "application/json");
            using var resp = await http.GetAsync($"https://api.vietqr.io/v2/business/{code}", ct);
            var raw = await resp.Content.ReadAsStringAsync(ct);
            if (string.IsNullOrWhiteSpace(raw))
                return new Result(false, "Không tra cứu được mã số thuế", null, null, null, null, null);
            using var doc = JsonDocument.Parse(raw);
            var root = doc.RootElement;
            var apiCode = root.TryGetProperty("code", out var cEl) ? cEl.GetString() : null;
            if (apiCode != "00" ||
                !root.TryGetProperty("data", out var data) ||
                data.ValueKind != JsonValueKind.Object)
            {
                return new Result(false, "Không tìm thấy mã số thuế", null, null, null, null, null);
            }

            static string? Read(JsonElement obj, string key) =>
                obj.TryGetProperty(key, out var p) && p.ValueKind == JsonValueKind.String
                    ? p.GetString()
                    : null;

            return new Result(
                true,
                null,
                Read(data, "id") ?? code,
                Read(data, "name"),
                Read(data, "internationalName"),
                Read(data, "shortName"),
                Read(data, "address"));
        }
        catch
        {
            return new Result(false, "Không tra cứu được MST — kiểm tra mạng rồi thử lại",
                null, null, null, null, null);
        }
    }

    public static object ToDto(Result r) => new
    {
        taxCode = r.TaxCode,
        name = r.Name,
        internationalName = r.InternationalName,
        shortName = r.ShortName,
        address = r.Address,
    };

    public static string? NormalizeTaxCode(string? raw)
    {
        var s = (raw ?? "").Trim().Replace(" ", "").Replace(".", "");
        if (s.Length == 10 && s.All(char.IsDigit)) return s;
        if (s.Length == 14 && s[10] == '-' &&
            s[..10].All(char.IsDigit) && s[11..].All(char.IsDigit))
            return s;
        if (s.Length == 13 && s.All(char.IsDigit))
            return $"{s[..10]}-{s[10..]}";
        return null;
    }
}
