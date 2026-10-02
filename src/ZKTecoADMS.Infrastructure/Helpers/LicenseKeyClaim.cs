using Microsoft.EntityFrameworkCore;

namespace ZKTecoADMS.Infrastructure.Helpers;

/// <summary>
/// Giữ key một cách nguyên tử: chỉ một yêu cầu đổi được IsUsed false → true.
/// Chống hai người kích hoạt cùng một key cùng lúc.
/// </summary>
public static class LicenseKeyClaim
{
    public const string AlreadyUsedMessage = "Key vừa được sử dụng ở nơi khác. Vui lòng dùng key khác.";

    public static async Task<bool> TryClaimAsync(ZKTecoDbContext db, Guid licenseId, Guid storeId, CancellationToken ct = default)
    {
        if (!db.Database.IsRelational()) return true;
        var now = DateTime.UtcNow;
        var n = await db.LicenseKeys
            .Where(l => l.Id == licenseId && !l.IsUsed)
            .ExecuteUpdateAsync(u => u
                .SetProperty(l => l.IsUsed, true)
                .SetProperty(l => l.StoreId, storeId)
                .SetProperty(l => l.ActivatedAt, now), ct);
        return n == 1;
    }
}
