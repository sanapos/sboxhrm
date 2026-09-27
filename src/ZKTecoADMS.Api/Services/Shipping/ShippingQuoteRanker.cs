namespace ZKTecoADMS.Api.Services.Shipping;

/// <summary>Gắn nhãn Rẻ nhất / Nhanh nhất / Đề xuất cho bảng so sánh cước.</summary>
public static class ShippingQuoteRanker
{
    public const string Cheapest = "cheapest";
    public const string Fastest = "fastest";
    public const string Recommended = "recommended";

    /// <summary>
    /// Đề xuất = gói rẻ nhất nếu nó không chậm hơn gói nhanh nhất quá 1 ngày (hoặc không rõ thời gian);
    /// ngược lại đề xuất gói nhanh nhất.
    /// </summary>
    public static IReadOnlyList<ShippingCompareQuoteItem> Rank(IReadOnlyList<ShippingCompareQuoteItem> quotes)
    {
        var ok = quotes.Where(q => q.Success && q.Fee > 0).ToList();
        if (ok.Count == 0) return quotes;

        var cheapest = ok.OrderBy(q => q.Fee).ThenBy(q => q.EtaMinutes ?? int.MaxValue).First();
        var withEta = ok.Where(q => q.EtaMinutes is > 0).ToList();
        var fastest = withEta.Count == 0
            ? null
            : withEta.OrderBy(q => q.EtaMinutes).ThenBy(q => q.Fee).First();

        ShippingCompareQuoteItem recommended = cheapest;
        if (fastest != null && cheapest.EtaMinutes is > 0
            && cheapest.EtaMinutes.Value - fastest.EtaMinutes!.Value > 24 * 60)
            recommended = fastest;

        return quotes.Select(q =>
        {
            var badges = new List<string>();
            if (ReferenceEquals(q, cheapest)) badges.Add(Cheapest);
            if (fastest != null && ReferenceEquals(q, fastest)) badges.Add(Fastest);
            if (ReferenceEquals(q, recommended)) badges.Add(Recommended);
            return badges.Count == 0 ? q : q with { Badges = badges };
        }).ToList();
    }
}
