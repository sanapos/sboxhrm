using System.IdentityModel.Tokens.Jwt;
using System.Text;
using ZKTecoADMS.Application.Interfaces.Auth;
using ZKTecoADMS.Application.Settings;
using ZKTecoADMS.Domain.Entities;
using Microsoft.IdentityModel.Tokens;
using Microsoft.Extensions.Logging;

namespace ZKTecoADMS.Infrastructure.Services.Auth;

public class RefreshTokenService(ITokenGeneratorService tokenGenerator, JwtSettings jwtSettings, ILogger<RefreshTokenService> logger) : IRefreshTokenService, IRefreshTokenValidatorService
{
    /// <summary>Hạn tối thiểu của mã làm mới khi cấu hình đặt nó không dài hơn mã truy cập: 30 ngày.</summary>
    public const double FallbackRefreshMinutes = 30 * 24 * 60;

    /// <summary>
    /// Hạn thực dùng của mã làm mới. Mã làm mới phải sống LÂU HƠN mã truy cập, nếu không thì lúc mã truy cập hết
    /// hạn (là lúc duy nhất app cần làm mới) mã làm mới đã chết từ trước → máy bị văng ra màn đăng nhập. Cấu hình
    /// đang chạy (truy cập 1.500 phút, làm mới 120 phút) đúng là trường hợp đó: mọi máy bị đăng xuất sau ~25 giờ.
    /// Cấu hình sai kiểu đó → dùng 30 ngày (hoặc gấp đôi hạn mã truy cập nếu dài hơn). Thu hồi phiên vẫn có hiệu
    /// lực ngay vì làm mới còn phải khớp dòng UserRefreshTokens (bị xóa khi thu hồi / gỡ thiết bị).
    /// </summary>
    public static double EffectiveRefreshMinutes(double accessMinutes, double refreshMinutes) =>
        refreshMinutes > accessMinutes
            ? refreshMinutes
            : Math.Max(FallbackRefreshMinutes, accessMinutes * 2);

    public Task<string> GetTokenAsync(ApplicationUser user)
    {
        return Task.FromResult(tokenGenerator.Generate(
            jwtSettings.RefreshTokenSecret,
            EffectiveRefreshMinutes(jwtSettings.AccessTokenExpirationMinutes, jwtSettings.RefreshTokenExpirationMinutes)));
    }

    public bool Validate(string refreshToken)
    {
        var validationParameters = new TokenValidationParameters
            {
                ValidateIssuerSigningKey = true,
                ValidateIssuer = true,
                ValidateAudience = true,
                ValidateLifetime = true,
                IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSettings.RefreshTokenSecret)),
                ValidIssuer = jwtSettings.Issuer,
                ValidAudience = jwtSettings.Audience,
                ClockSkew = TimeSpan.Zero

            };

            JwtSecurityTokenHandler jwtSecurityTokenHandler = new();

            try
            {
                jwtSecurityTokenHandler.ValidateToken(refreshToken, validationParameters, out SecurityToken _);
                return true;
            }
            catch(Exception ex)
            {
                logger.LogError(ex, "Error validating refresh token");
                return false;
            }
    }
}
