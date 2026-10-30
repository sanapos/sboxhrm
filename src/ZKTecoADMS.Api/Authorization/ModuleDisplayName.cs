using ZKTecoADMS.Application.Authorization;

namespace ZKTecoADMS.Api.Authorization;

/// <summary>Tên module tiếng Việt cho thông báo thiếu quyền («Leave» → «Nghỉ phép»).</summary>
public static class ModuleDisplayName
{
    private static readonly Dictionary<string, string> Names = FeatureModuleCatalog.All
        .GroupBy(m => m.Code, StringComparer.OrdinalIgnoreCase)
        .ToDictionary(g => g.Key, g => g.First().DisplayName, StringComparer.OrdinalIgnoreCase);

    public static string Of(string? code) =>
        string.IsNullOrWhiteSpace(code) ? string.Empty : Names.TryGetValue(code, out var n) ? n : code;

    public static string OfList(string? codes) =>
        string.Join(", ", (codes ?? string.Empty).Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).Select(Of));
}
