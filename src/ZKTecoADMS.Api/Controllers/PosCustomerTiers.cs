using System.Text.Json;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Hạng thành viên khách theo tổng mua (PosCustomer.TotalPurchase): khách đạt mức «từ» của hạng cao nhất nào thì thuộc hạng đó.
/// Cấu hình lưu ở PosStoreSellSettings.LoyaltyTiersJson.
/// </summary>
public static class PosCustomerTiers
{
    public sealed record Tier(string Name, decimal MinSpend, string? Color = null, string? Benefit = null);

    public const int MaxTiers = 10;

    static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, PropertyNameCaseInsensitive = true };

    /// <summary>Danh sách hạng hợp lệ, tăng dần theo mức tổng mua (JSON hỏng → rỗng).</summary>
    public static List<Tier> Parse(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return [];
        try
        {
            return Normalize(JsonSerializer.Deserialize<List<Tier>>(json, Json) ?? []);
        }
        catch (JsonException)
        {
            return [];
        }
    }

    public static string Serialize(IEnumerable<Tier> tiers) => JsonSerializer.Serialize(tiers, Json);

    public static List<Tier> Normalize(IEnumerable<Tier?> tiers) => tiers
        .Where(t => t != null && !string.IsNullOrWhiteSpace(t.Name))
        .Select(t => t! with
        {
            Name = t.Name.Trim(),
            MinSpend = Math.Max(0, Math.Round(t.MinSpend)),
            Color = string.IsNullOrWhiteSpace(t.Color) ? null : t.Color.Trim(),
            Benefit = string.IsNullOrWhiteSpace(t.Benefit) ? null : t.Benefit.Trim(),
        })
        .OrderBy(t => t.MinSpend)
        .ToList();

    /// <summary>Lỗi cấu hình (null = hợp lệ).</summary>
    public static string? Validate(IReadOnlyList<Tier> tiers)
    {
        if (tiers.Count > MaxTiers) return $"Tối đa {MaxTiers} hạng";
        if (tiers.Any(t => t.Name.Length > 40)) return "Tên hạng tối đa 40 ký tự";
        if (tiers.Any(t => (t.Benefit?.Length ?? 0) > 200)) return "Ưu đãi tối đa 200 ký tự";
        var dupName = tiers.GroupBy(t => t.Name.ToLowerInvariant()).FirstOrDefault(g => g.Count() > 1);
        if (dupName != null) return $"Trùng tên hạng «{dupName.First().Name}»";
        var dupMin = tiers.GroupBy(t => t.MinSpend).FirstOrDefault(g => g.Count() > 1);
        if (dupMin != null) return $"Hai hạng cùng mức tổng mua {dupMin.Key:N0}đ";
        return null;
    }

    /// <summary>Vị trí hạng của khách (-1 = chưa đạt hạng nào).</summary>
    public static int IndexOf(IReadOnlyList<Tier> tiers, decimal totalPurchase)
    {
        var idx = -1;
        for (var i = 0; i < tiers.Count; i++)
            if (totalPurchase >= tiers[i].MinSpend) idx = i;
        return idx;
    }

    public static Tier? Resolve(IReadOnlyList<Tier> tiers, decimal totalPurchase)
    {
        var i = IndexOf(tiers, totalPurchase);
        return i < 0 ? null : tiers[i];
    }

    /// <summary>Khoảng tổng mua [from, to) của hạng (to = null: không giới hạn trên).</summary>
    public static (decimal From, decimal? To) Range(IReadOnlyList<Tier> tiers, int index) =>
        (tiers[index].MinSpend, index + 1 < tiers.Count ? tiers[index + 1].MinSpend : null);
}
