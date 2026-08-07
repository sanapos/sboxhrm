using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Caching.Distributed;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Interfaces;

namespace ZKTecoADMS.Infrastructure.Services;

public class PasswordOtpStore(
    IDistributedCache distributedCache,
    IMemoryCache memoryCache,
    ILogger<PasswordOtpStore> logger
) : IPasswordOtpStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    private static string OtpKey(string storeCode, string email) =>
        $"pwd_otp:{storeCode.Trim().ToLowerInvariant()}:{email.Trim().ToLowerInvariant()}";

    private static string CooldownKey(string storeCode, string email) =>
        $"pwd_otp_cd:{storeCode.Trim().ToLowerInvariant()}:{email.Trim().ToLowerInvariant()}";

    public async Task SetAsync(string storeCode, string email, PasswordOtpEntry entry, TimeSpan ttl, CancellationToken cancellationToken = default)
    {
        var key = OtpKey(storeCode, email);
        var bytes = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(entry, JsonOptions));
        await SetBytesAsync(key, bytes, ttl, cancellationToken);
    }

    public async Task UpdateAsync(string storeCode, string email, PasswordOtpEntry entry, TimeSpan ttl, CancellationToken cancellationToken = default)
    {
        await SetAsync(storeCode, email, entry, ttl, cancellationToken);
    }

    public async Task<PasswordOtpEntry?> GetAsync(string storeCode, string email, CancellationToken cancellationToken = default)
    {
        var key = OtpKey(storeCode, email);
        var bytes = await GetBytesAsync(key, cancellationToken);
        if (bytes == null || bytes.Length == 0) return null;
        try
        {
            return JsonSerializer.Deserialize<PasswordOtpEntry>(bytes, JsonOptions);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "PasswordOtpStore: invalid OTP payload for {Key}", key);
            return null;
        }
    }

    public async Task RemoveAsync(string storeCode, string email, CancellationToken cancellationToken = default)
    {
        var key = OtpKey(storeCode, email);
        try
        {
            await distributedCache.RemoveAsync(key, cancellationToken);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "PasswordOtpStore: distributed remove failed, falling back to memory");
        }
        memoryCache.Remove(key);
    }

    public async Task<bool> IsSendCooldownActiveAsync(string storeCode, string email, CancellationToken cancellationToken = default)
    {
        var key = CooldownKey(storeCode, email);
        var bytes = await GetBytesAsync(key, cancellationToken);
        return bytes != null && bytes.Length > 0;
    }

    public async Task MarkSendCooldownAsync(string storeCode, string email, TimeSpan cooldown, CancellationToken cancellationToken = default)
    {
        var key = CooldownKey(storeCode, email);
        await SetBytesAsync(key, "1"u8.ToArray(), cooldown, cancellationToken);
    }

    private async Task SetBytesAsync(string key, byte[] bytes, TimeSpan ttl, CancellationToken cancellationToken)
    {
        try
        {
            await distributedCache.SetAsync(
                key,
                bytes,
                new DistributedCacheEntryOptions { AbsoluteExpirationRelativeToNow = ttl },
                cancellationToken);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "PasswordOtpStore: distributed set failed, using memory for {Key}", key);
            SetMemory(key, bytes, ttl);
            return;
        }

        // Mirror to memory for local fast-path / Redis blip
        try
        {
            SetMemory(key, bytes, ttl);
        }
        catch (Exception ex)
        {
            logger.LogDebug(ex, "PasswordOtpStore: memory mirror skipped for {Key}", key);
        }
    }

    private void SetMemory(string key, byte[] bytes, TimeSpan ttl)
    {
        // Api MemoryCache has SizeLimit — Size bắt buộc.
        memoryCache.Set(key, bytes, new MemoryCacheEntryOptions
        {
            AbsoluteExpirationRelativeToNow = ttl,
            Size = Math.Max(1, bytes.Length)
        });
    }

    private async Task<byte[]?> GetBytesAsync(string key, CancellationToken cancellationToken)
    {
        try
        {
            var bytes = await distributedCache.GetAsync(key, cancellationToken);
            if (bytes != null && bytes.Length > 0) return bytes;
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "PasswordOtpStore: distributed get failed for {Key}", key);
        }

        if (memoryCache.TryGetValue(key, out byte[]? local) && local is { Length: > 0 })
            return local;
        return null;
    }
}
