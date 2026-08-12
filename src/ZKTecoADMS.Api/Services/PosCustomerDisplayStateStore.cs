using System.Collections.Concurrent;
using System.Text.Json;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Cache trạng thái màn hình phụ theo cửa hàng / mã xem công khai (máy khác mở link).
/// Giữ memory + file để sống qua recycle API (single instance).
/// </summary>
public static class PosCustomerDisplayStateStore
{
    private static readonly ConcurrentDictionary<Guid, Entry> ByStore = new();
    private static readonly ConcurrentDictionary<string, Entry> ByViewerCode =
        new(StringComparer.OrdinalIgnoreCase);
    private static readonly object FileLock = new();
    private static bool _loaded;

    private sealed record Entry(string Json, DateTime UpdatedUtc, Guid StoreId, string ViewerCode);

    private static string PersistPath
    {
        get
        {
            var dir = Path.Combine(AppContext.BaseDirectory, "App_Data");
            Directory.CreateDirectory(dir);
            return Path.Combine(dir, "customer-display-state.json");
        }
    }

    private static void EnsureLoaded()
    {
        if (_loaded) return;
        lock (FileLock)
        {
            if (_loaded) return;
            try
            {
                var path = PersistPath;
                if (File.Exists(path))
                {
                    var raw = File.ReadAllText(path);
                    using var doc = JsonDocument.Parse(raw);
                    if (doc.RootElement.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var el in doc.RootElement.EnumerateArray())
                        {
                            var storeId = el.TryGetProperty("storeId", out var s)
                                && Guid.TryParse(s.GetString(), out var g)
                                ? g
                                : Guid.Empty;
                            var code = el.TryGetProperty("viewerCode", out var c)
                                ? (c.GetString() ?? "").Trim()
                                : "";
                            var json = el.TryGetProperty("json", out var j) ? j.GetString() : null;
                            var updated = el.TryGetProperty("updatedUtc", out var u)
                                && DateTime.TryParse(u.GetString(), out var dt)
                                ? dt.ToUniversalTime()
                                : DateTime.UtcNow;
                            if (storeId == Guid.Empty || string.IsNullOrWhiteSpace(json) || code.Length < 4)
                                continue;
                            var entry = new Entry(json!, updated, storeId, code);
                            ByStore[storeId] = entry;
                            ByViewerCode[code] = entry;
                        }
                    }
                }
            }
            catch
            {
                // ignore corrupt file
            }
            _loaded = true;
        }
    }

    private static void PersistAll()
    {
        try
        {
            lock (FileLock)
            {
                var list = ByStore.Values
                    .GroupBy(e => e.StoreId)
                    .Select(g => g.OrderByDescending(x => x.UpdatedUtc).First())
                    .Select(e => new
                    {
                        storeId = e.StoreId,
                        viewerCode = e.ViewerCode,
                        json = e.Json,
                        updatedUtc = e.UpdatedUtc,
                    })
                    .ToList();
                var path = PersistPath;
                File.WriteAllText(path, JsonSerializer.Serialize(list));
            }
        }
        catch
        {
            // best-effort
        }
    }

    public static void Publish(Guid storeId, string viewerCode, string json)
    {
        EnsureLoaded();
        if (storeId == Guid.Empty || string.IsNullOrWhiteSpace(json)) return;
        var code = (viewerCode ?? "").Trim();
        if (code.Length < 4) return;

        var entry = new Entry(json, DateTime.UtcNow, storeId, code);
        ByStore[storeId] = entry;
        ByViewerCode[code] = entry;
        PersistAll();
    }

    public static string? GetByStore(Guid storeId)
    {
        EnsureLoaded();
        return ByStore.TryGetValue(storeId, out var e) ? e.Json : null;
    }

    public static string? GetByViewerCode(string? code)
    {
        EnsureLoaded();
        if (string.IsNullOrWhiteSpace(code)) return null;
        return ByViewerCode.TryGetValue(code.Trim(), out var e) ? e.Json : null;
    }
}
