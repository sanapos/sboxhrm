using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>Đăng ký token FCM: mỗi token thuộc đúng người đang đăng nhập trên máy đó.</summary>
public static class DeviceTokenRegistry
{
    /// <summary>
    /// Gắn token cho <paramref name="userId"/>. Token đã có (cùng máy, đổi người đăng nhập) thì chuyển chủ và bật lại.
    /// Có mã thiết bị thì xóa token cũ của cùng máy. Trả về chủ cũ của token (null nếu token mới).
    /// </summary>
    public static async Task<Guid?> RegisterAsync(ZKTecoDbContext db, Guid userId, string token, string platform,
        string? deviceName, string? appVersion, string? deviceKey, CancellationToken ct = default)
    {
        var key = string.IsNullOrWhiteSpace(deviceKey) ? null : deviceKey.Trim();
        if (key is { Length: > 80 }) key = key[..80];

        // AsTracking: DbContext mặc định NoTracking — thiếu dòng này thì đổi chủ token không được lưu,
        // token vẫn thuộc người đăng nhập trước và thông báo của họ đổ về máy người sau.
        var existing = await db.UserDeviceTokens.AsTracking().FirstOrDefaultAsync(t => t.Token == token, ct);
        Guid? previousOwner = existing?.UserId;
        if (existing != null)
        {
            existing.UserId = userId;
            existing.Platform = platform;
            existing.DeviceName = deviceName;
            existing.AppVersion = appVersion;
            existing.DeviceKey = key ?? existing.DeviceKey;
            existing.IsDisabled = false;
            existing.LastUsedAt = null;
            existing.UpdatedAt = DateTime.UtcNow;
        }
        else
        {
            db.UserDeviceTokens.Add(new UserDeviceToken
            {
                Id = Guid.NewGuid(),
                UserId = userId,
                Token = token,
                Platform = platform,
                DeviceName = deviceName,
                AppVersion = appVersion,
                DeviceKey = key,
                IsDisabled = false,
            });
        }

        // Cùng một máy chỉ giữ token mới nhất — token cũ của máy này (bản cài trước / người trước) bỏ đi.
        if (key != null)
        {
            var stale = await db.UserDeviceTokens.AsTracking()
                .Where(t => t.DeviceKey == key && t.Token != token)
                .ToListAsync(ct);
            if (stale.Count > 0) db.UserDeviceTokens.RemoveRange(stale);
        }

        await db.SaveChangesAsync(ct);
        return previousOwner;
    }
}
