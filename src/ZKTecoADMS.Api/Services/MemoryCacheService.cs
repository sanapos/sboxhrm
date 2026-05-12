using Microsoft.Extensions.Caching.Memory;
using System.Collections.Concurrent;
using ZKTecoADMS.Application.Interfaces;

namespace ZKTecoADMS.Api.Services;

public class MemoryCacheService(IMemoryCache cache) : ICacheService
{
    private readonly ConcurrentDictionary<string, byte> _keys = new();
    // Per-key semaphores prevent thundering herd: only one factory call per key at a time
    private readonly ConcurrentDictionary<string, SemaphoreSlim> _locks = new();

    public async Task<T?> GetOrCreateAsync<T>(string key, Func<Task<T>> factory, TimeSpan? expiration = null)
    {
        if (cache.TryGetValue(key, out T? value))
            return value;

        var sem = _locks.GetOrAdd(key, _ => new SemaphoreSlim(1, 1));
        await sem.WaitAsync();
        try
        {
            // Double-check after acquiring lock
            if (cache.TryGetValue(key, out value))
                return value;

            value = await factory();
            var options = new MemoryCacheEntryOptions
            {
                AbsoluteExpirationRelativeToNow = expiration ?? TimeSpan.FromMinutes(5),
                Size = 1,
                Priority = CacheItemPriority.Normal
            };
            options.RegisterPostEvictionCallback((evictedKey, _, _, _) =>
            {
                var k = evictedKey.ToString()!;
                _keys.TryRemove(k, out _);
                _locks.TryRemove(k, out _);
            });
            cache.Set(key, value, options);
            _keys.TryAdd(key, 0);
        }
        finally
        {
            sem.Release();
        }

        return value;
    }

    public void Remove(string key)
    {
        cache.Remove(key);
        _keys.TryRemove(key, out _);
        _locks.TryRemove(key, out _);
    }

    public void RemoveByPrefix(string prefix)
    {
        var keysToRemove = _keys.Keys
            .Where(k => k.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            .ToList();
        foreach (var k in keysToRemove)
        {
            cache.Remove(k);
            _keys.TryRemove(k, out _);
            _locks.TryRemove(k, out _);
        }
    }
}
