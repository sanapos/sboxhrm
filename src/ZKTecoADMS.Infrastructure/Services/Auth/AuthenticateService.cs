using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Auth;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Interfaces.Auth;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Exceptions;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Infrastructure.Services.Auth;

public class AuthenticateService(
    IAccessTokenService accessTokenService,
    IRefreshTokenService refreshTokenService,
    ZKTecoDbContext db) : IAuthenticateService
{
    /// <summary>Số phiên (máy) tối đa giữ cho một tài khoản — phiên cũ nhất bị bỏ khi vượt.</summary>
    internal const int MaxSessionsPerUser = 10;

    public async Task<AppResponse<AuthenticateResponse>> Authenticate(ApplicationUser user, CancellationToken cancellationToken,
        string? replacingRefreshToken = null)
    {
        var accessToken = await accessTokenService.GetTokenAsync(user);
        var refreshToken = await refreshTokenService.GetTokenAsync(user);

        // Mỗi máy một refresh token. Trước đây mỗi tài khoản chỉ có 1 dòng: máy A đăng nhập / làm mới token
        // là token của máy B mất hiệu lực → máy B bị đăng xuất khi access token hết hạn (≈1 giờ).
        UserRefreshToken? row = null;
        if (!string.IsNullOrEmpty(replacingRefreshToken))
        {
            row = await db.UserRefreshTokens.AsTracking()
                .FirstOrDefaultAsync(t => t.ApplicationUserId == user.Id && t.RefreshToken == replacingRefreshToken,
                    cancellationToken);
        }
        if (row == null)
        {
            row = new UserRefreshToken { Id = Guid.NewGuid(), ApplicationUserId = user.Id };
            db.UserRefreshTokens.Add(row);
        }
        row.RefreshToken = refreshToken;
        row.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(cancellationToken);

        // Cột này chưa từng được ghi: mọi tài khoản đều hiện «Chưa đăng nhập» và bộ lọc «lâu chưa đăng nhập»
        // của thông báo chọn nhầm. Tính cả lần làm mới phiên vì app giữ đăng nhập nhiều tuần liền.
        try
        {
            var now = DateTime.UtcNow;
            await db.Users.IgnoreQueryFilters().Where(u => u.Id == user.Id)
                .ExecuteUpdateAsync(s => s.SetProperty(u => u.LastLoginAt, now), cancellationToken);
        }
        catch (InvalidOperationException)
        {
            // Nhà cung cấp InMemory (test) không hỗ trợ ExecuteUpdate. Không làm hỏng đăng nhập.
        }

        var stale =await db.UserRefreshTokens.AsNoTracking()
            .Where(t => t.ApplicationUserId == user.Id)
            .OrderByDescending(t => t.UpdatedAt ?? t.CreatedAt)
            .Skip(MaxSessionsPerUser)
            .Select(t => t.Id)
            .ToListAsync(cancellationToken);
        if (stale.Count > 0)
            await db.UserRefreshTokens.Where(t => stale.Contains(t.Id)).ExecuteDeleteAsync(cancellationToken);

        return AppResponse<AuthenticateResponse>.Success(new AuthenticateResponse(accessToken, refreshToken));
    }
}
