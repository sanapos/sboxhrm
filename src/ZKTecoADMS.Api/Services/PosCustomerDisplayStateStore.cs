using System.Collections.Concurrent;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Cache trạng thái màn hình phụ theo cửa hàng / mã xem công khai (máy khác mở link).
/// </summary>
public static class PosCustomerDisplayStateStore
{
    private static readonly ConcurrentDictionary<Guid, Entry> ByStore = new();
    private static readonly ConcurrentDictionary<string, Entry> ByViewerCode =
        new(StringComparer.OrdinalIgnoreCase);

    private sealed record Entry(string Json, DateTime UpdatedUtc, Guid StoreId, string ViewerCode);

    public static void Publish(Guid storeId, string viewerCode, string json)
    {
        if (storeId == Guid.Empty || string.IsNullOrWhiteSpace(json)) return;
        var code = (viewerCode ?? "").Trim();
        if (code.Length < 4) return;

        var entry = new Entry(json, DateTime.UtcNow, storeId, code);
        ByStore[storeId] = entry;
        ByViewerCode[code] = entry;
    }

    public static string? GetByStore(Guid storeId)
        => ByStore.TryGetValue(storeId, out var e) ? e.Json : null;

    public static string? GetByViewerCode(string? code)
    {
        if (string.IsNullOrWhiteSpace(code)) return null;
        return ByViewerCode.TryGetValue(code.Trim(), out var e) ? e.Json : null;
    }
}
