using ZKTecoADMS.Application.Interfaces.Auth;
using ZKTecoADMS.Application.Settings;
using Microsoft.Extensions.Logging;
using Microsoft.IdentityModel.Tokens;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;

namespace ZKTecoADMS.Infrastructure.Services.Auth;

public class TokenGeneratorService(JwtSettings jwtSettings, ILogger<TokenGeneratorService> logger) : ITokenGeneratorService
{
    public string Generate(string secretKey, double expires, IEnumerable<Claim> claims = null)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(secretKey));
        var signInCredentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

        var tokenOptions = new JwtSecurityToken(
            issuer: jwtSettings.Issuer,
            audience: jwtSettings.Audience,
            claims: claims ?? [],
            expires: DateTime.UtcNow.AddMinutes(expires),
            signingCredentials: signInCredentials
        );

        return new JwtSecurityTokenHandler().WriteToken(tokenOptions);
    }
}
