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
        string? Address,
        string? Representative = null);

    /// <summary>
    /// Tên / địa chỉ từ VietQR (dữ liệu Cục Thuế); người đại diện pháp luật lấy thêm từ esgoo.net (VietQR không có).
    /// Nguồn phụ lỗi / chậm → vẫn trả kết quả VietQR. VietQR lỗi → dùng tên / địa chỉ của nguồn phụ.
    /// </summary>
    public static async Task<Result> LookupAsync(string? taxCode, CancellationToken ct = default)
    {
        var code = NormalizeTaxCode(taxCode);
        if (code == null)
            return new Result(false, "Mã số thuế không hợp lệ (10 số, hoặc 10-3 chi nhánh)",
                null, null, null, null, null);
        var main = LookupVietQrAsync(code, ct);
        var extra = LookupEsgooAsync(code, ct);
        await Task.WhenAll(main, extra);
        var r = main.Result;
        var e = extra.Result;
        if (r.Ok) return r with { Representative = e?.Representative };
        if (e is { Name: { Length: > 0 } })
            return new Result(true, null, code, e.Name, null, null, e.Address, e.Representative);
        return r;
    }

    sealed record Extra(string? Name, string? Address, string? Representative);

    static async Task<Extra?> LookupEsgooAsync(string code, CancellationToken ct)
    {
        try
        {
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(6) };
            http.DefaultRequestHeaders.TryAddWithoutValidation("User-Agent", "Mozilla/5.0 SBOX");
            var raw = await http.GetStringAsync($"https://esgoo.net/api-mst/{code}.htm", ct);
            using var doc = JsonDocument.Parse(raw);
            var root = doc.RootElement;
            if (!root.TryGetProperty("error", out var err) || err.ValueKind != JsonValueKind.Number || err.GetInt32() != 0 ||
                !root.TryGetProperty("data", out var d) || d.ValueKind != JsonValueKind.Object)
                return null;
            static string? S(JsonElement o, string k)
            {
                if (!o.TryGetProperty(k, out var p) || p.ValueKind != JsonValueKind.String) return null;
                var v = p.GetString()?.Trim();
                return string.IsNullOrEmpty(v) || v == "null" ? null : v;
            }
            return new Extra(S(d, "ten"), S(d, "dc"), S(d, "daidien"));
        }
        catch
        {
            return null;
        }
    }

    static async Task<Result> LookupVietQrAsync(string code, CancellationToken ct)
    {
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
        representative = r.Representative,
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
