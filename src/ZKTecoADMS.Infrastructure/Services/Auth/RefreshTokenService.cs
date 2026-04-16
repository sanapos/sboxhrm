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
    public Task<string> GetTokenAsync(ApplicationUser user)
    {
        return Task.FromResult(tokenGenerator.Generate(jwtSettings.RefreshTokenSecret, jwtSettings.RefreshTokenExpirationMinutes));
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
