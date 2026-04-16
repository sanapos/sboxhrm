using Microsoft.Extensions.Caching.Memory;
using System.Collections.Concurrent;
using ZKTecoADMS.Application.Interfaces;

namespace ZKTecoADMS.Api.Services;

public class MemoryCacheService(IMemoryCache cache) : ICacheService
{
    private readonly ConcurrentDictionary<string, byte> _keys = new();

    public async Task<T?> GetOrCreateAsync<T>(string key, Func<Task<T>> factory, TimeSpan? expiration = null)
    {
        if (cache.TryGetValue(key, out T? value))
            return value;

        value = await factory();
        var options = new MemoryCacheEntryOptions
        {
            AbsoluteExpirationRelativeToNow = expiration ?? TimeSpan.FromMinutes(5),
            Size = 1, // Each entry counts as 1 unit toward SizeLimit
            Priority = CacheItemPriority.Normal
        };
        options.RegisterPostEvictionCallback((evictedKey, _, _, _) =>
        {
            _keys.TryRemove(evictedKey.ToString()!, out _);
        });
        cache.Set(key, value, options);
        _keys.TryAdd(key, 0);

        return value;
    }

    public void Remove(string key)
    {
        cache.Remove(key);
        _keys.TryRemove(key, out _);
    }

    public void RemoveByPrefix(string prefix)
    {
        var keysToRemove = _keys.Keys
            .Where(k => k.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            .ToList();
        foreach (var key in keysToRemove)
        {
            cache.Remove(key);
            _keys.TryRemove(key, out _);
        }
    }
}
