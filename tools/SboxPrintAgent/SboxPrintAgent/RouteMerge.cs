namespace SboxPrintAgent;

/// <summary>
/// Server cho phép nhiều route cùng DocumentType (máy in khác nhau).
/// Không dùng ToDictionary(DocumentType) — sẽ vỡ với Key trùng (vd SaleOrder).
/// </summary>
public static class RouteMerge
{
    /// <summary>
    /// Gán các loại chứng từ trong <paramref name="documentTypes"/> cho <paramref name="printerId"/>,
    /// giữ nguyên các route thuộc loại khác.
    /// </summary>
    public static List<RouteItem> AssignTypes(
        IEnumerable<RouteItem> existing,
        IEnumerable<string> documentTypes,
        Guid printerId,
        int copies = 1)
    {
        var roles = documentTypes
            .Where(x => !string.IsNullOrWhiteSpace(x))
            .Select(x => x.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        var result = new List<RouteItem>();
        foreach (var r in existing)
        {
            if (roles.Contains(r.DocumentType)) continue;
            result.Add(r);
        }

        foreach (var doc in roles.OrderBy(x => x, StringComparer.OrdinalIgnoreCase))
            result.Add(new RouteItem(doc, printerId, Math.Clamp(copies, 1, 10)));

        return result;
    }
}
