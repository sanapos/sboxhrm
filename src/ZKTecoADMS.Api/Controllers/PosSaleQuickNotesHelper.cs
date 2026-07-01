using System.Text.Json;

namespace ZKTecoADMS.Api.Controllers;

internal static class PosSaleQuickNotesHelper
{
    public static List<string> Parse(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return [];
        try
        {
            return JsonSerializer.Deserialize<List<string>>(json)?
                       .Where(s => !string.IsNullOrWhiteSpace(s))
                       .Select(s => s.Trim())
                       .Distinct(StringComparer.OrdinalIgnoreCase)
                       .Take(30)
                       .ToList()
                   ?? [];
        }
        catch
        {
            return [];
        }
    }

    public static string? Serialize(IReadOnlyList<string>? notes)
    {
        if (notes == null || notes.Count == 0) return null;
        var cleaned = notes
            .Where(s => !string.IsNullOrWhiteSpace(s))
            .Select(s => s.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Take(30)
            .ToList();
        return cleaned.Count == 0 ? null : JsonSerializer.Serialize(cleaned);
    }
}
