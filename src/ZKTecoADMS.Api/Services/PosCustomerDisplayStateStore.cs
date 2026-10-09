using System.Collections.Concurrent;
using System.Text.Json;
using Microsoft.Extensions.Caching.Distributed;

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
    private static Timer? _persistTimer;

    /// <summary>Bật khi Redis kết nối được lúc khởi động — chia sẻ trạng thái giữa nhiều API.</summary>
    public static bool UseDistributed { get; set; }

    private static DateTime _distributedDownUntil = DateTime.MinValue;
    private const string DistPrefix = "pos_cd_v1_";

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
        // Giỏ đổi liên tục: ghi file tối đa 1 lần / 3 giây (trước đây ghi mỗi lần đẩy).
        _persistTimer ??= new Timer(_ => PersistAll(), null, Timeout.Infinite, Timeout.Infinite);
        _persistTimer.Change(TimeSpan.FromSeconds(3), Timeout.InfiniteTimeSpan);
    }

    /// <summary>Đẩy + chia sẻ qua Redis (nhiều instance API). Lỗi Redis → tạm tắt 60s, vẫn dùng memory.</summary>
    public static void Publish(Guid storeId, string viewerCode, string json, IDistributedCache? dist)
    {
        Publish(storeId, viewerCode, json);
        if (!DistributedAvailable(dist)) return;
        var code = (viewerCode ?? "").Trim();
        if (code.Length < 4) return;
        _ = Task.Run(async () =>
        {
            try
            {
                using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(2));
                // «ticks|json» — đọc lại so với bản memory, lấy bản mới hơn.
                await dist!.SetStringAsync(DistPrefix + code.ToLowerInvariant(),
                    $"{DateTime.UtcNow.Ticks}|{json}",
                    new DistributedCacheEntryOptions { AbsoluteExpirationRelativeToNow = TimeSpan.FromDays(2) },
                    cts.Token);
            }
            catch { MarkDistributedDown(); }
        });
    }

    /// <summary>Đọc theo mã xem: Redis (bản mới nhất từ mọi instance) → memory.</summary>
    public static async Task<string?> GetByViewerCodeAsync(string? code, IDistributedCache? dist)
    {
        if (string.IsNullOrWhiteSpace(code)) return null;
        if (DistributedAvailable(dist))
        {
            try
            {
                var task = dist!.GetStringAsync(DistPrefix + code.Trim().ToLowerInvariant());
                if (await Task.WhenAny(task, Task.Delay(400)) == task)
                {
                    var raw = await task;
                    var bar = raw?.IndexOf('|') ?? -1;
                    if (bar > 0 && long.TryParse(raw![..bar], out var ticks))
                    {
                        EnsureLoaded();
                        var local = ByViewerCode.TryGetValue(code.Trim(), out var e) ? e : null;
                        // Redis từng lỗi lúc ghi → bản memory có thể mới hơn.
                        if (local == null || local.UpdatedUtc.Ticks <= ticks) return raw[(bar + 1)..];
                        return local.Json;
                    }
                }
                else MarkDistributedDown();
            }
            catch { MarkDistributedDown(); }
        }
        return GetByViewerCode(code);
    }

    static bool DistributedAvailable(IDistributedCache? dist) =>
        UseDistributed && dist != null && DateTime.UtcNow >= _distributedDownUntil;

    static void MarkDistributedDown() => _distributedDownUntil = DateTime.UtcNow.AddSeconds(60);

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
