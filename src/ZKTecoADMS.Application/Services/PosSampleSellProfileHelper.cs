using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Services;

/// <summary>CSV hồ sơ ngành trên catalog mẫu (Restaurant,Retail). Rỗng = mọi ngành.</summary>
public static class PosSampleSellProfileHelper
{
    public static string? Normalize(string? raw)
    {
        var set = Parse(raw);
        if (set.Count == 0) return null;
        return string.Join(',', set.OrderBy(x => (int)x).Select(x => x.ToString()));
    }

    public static HashSet<PosSellProfile> Parse(string? raw)
    {
        var set = new HashSet<PosSellProfile>();
        if (string.IsNullOrWhiteSpace(raw)) return set;
        foreach (var part in raw.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            if (PosSellProfileDefaults.TryParse(part, out var p))
                set.Add(p);
        }
        return set;
    }

    public static bool Matches(string? csv, PosSellProfile profile)
    {
        var set = Parse(csv);
        return set.Count == 0 || set.Contains(profile);
    }

    public static IQueryable<PosProductSampleCatalog> WhereMatches(
        this IQueryable<PosProductSampleCatalog> q, PosSellProfile profile)
    {
        var name = profile.ToString();
        return q.Where(x =>
            x.SellProfiles == null ||
            x.SellProfiles == "" ||
            x.SellProfiles == name ||
            x.SellProfiles.StartsWith(name + ",") ||
            x.SellProfiles.EndsWith("," + name) ||
            x.SellProfiles.Contains("," + name + ","));
    }

    /// <summary>Gán ngành cho mẫu F&amp;B cũ chưa có SellProfiles.</summary>
    public static string Infer(PosProductSampleKind kind, PosProductType type, string? name)
    {
        var n = (name ?? "").Trim();
        if (n.Contains("cắt tóc", StringComparison.OrdinalIgnoreCase) ||
            n.Contains("gội", StringComparison.OrdinalIgnoreCase) ||
            n.Contains("nail", StringComparison.OrdinalIgnoreCase) ||
            n.Contains("nhuộm", StringComparison.OrdinalIgnoreCase) ||
            n.Contains("massage", StringComparison.OrdinalIgnoreCase))
            return nameof(PosSellProfile.Salon);
        if (n.Contains("PT", StringComparison.Ordinal) ||
            n.Contains("gói", StringComparison.OrdinalIgnoreCase) && n.Contains("buổi", StringComparison.OrdinalIgnoreCase) ||
            n.Contains("whey", StringComparison.OrdinalIgnoreCase))
            return nameof(PosSellProfile.Gym);
        if (n.Contains("karaoke", StringComparison.OrdinalIgnoreCase) ||
            n.Contains("bi-a", StringComparison.OrdinalIgnoreCase) ||
            n.Contains("billiard", StringComparison.OrdinalIgnoreCase))
            return nameof(PosSellProfile.RoomHourly);
        if (n.Contains("phòng", StringComparison.OrdinalIgnoreCase) &&
            (n.Contains("đêm", StringComparison.OrdinalIgnoreCase) || n.Contains("standard", StringComparison.OrdinalIgnoreCase) ||
             n.Contains("deluxe", StringComparison.OrdinalIgnoreCase)))
            return nameof(PosSellProfile.Hotel);

        if (kind is PosProductSampleKind.Food or PosProductSampleKind.Drink)
            return nameof(PosSellProfile.Restaurant);
        if (type == PosProductType.Service)
            return nameof(PosSellProfile.Retail);
        return "Retail,Restaurant,Hotel,RoomHourly,Gym";
    }
}
