using ZKTecoADMS.Application.Interfaces.Auth;
using ZKTecoADMS.Application.Settings;
using ZKTecoADMS.Domain.Entities;
using System.Security.Claims;
using Microsoft.AspNetCore.Identity;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Infrastructure.Services.Auth;

public class AccessTokenService(
    ITokenGeneratorService tokenGenerator, 
    JwtSettings jwtSettings, 
    UserManager<ApplicationUser> userManager) : IAccessTokenService
{
    public async Task<string> GetTokenAsync(ApplicationUser user)
    {
        var roles = await userManager.GetRolesAsync(user);
        var rolesClaims = roles.Select(role => new Claim(ClaimTypes.Role, role));
        
        List<Claim> claims =
            [
                new Claim(ClaimTypes.NameIdentifier, user.Id.ToString()),
                new Claim(ClaimTypes.Email, user.Email ?? ""),
                new Claim(ClaimTypes.Name, user.LastName + " " + user.FirstName),
                new Claim(ClaimTypeNames.UserName, user.UserName!),
                new Claim(ClaimTypeNames.EmployeeId, user.Employee?.Id.ToString() ?? ""),
                new Claim(ClaimTypeNames.ManagerId, user.ManagerId?.ToString() ?? ""),
                new Claim(ClaimTypeNames.EmployeeType, user.Employee?.EmploymentType.ToString() ?? ""),
                new Claim(ClaimTypeNames.StoreId, user.StoreId?.ToString() ?? ""),
                new Claim(ClaimTypeNames.StoreName, user.Store?.Name ?? ""),
                ..rolesClaims
            ];

        return tokenGenerator.Generate(jwtSettings.AccessTokenSecret, jwtSettings.AccessTokenExpirationMinutes, claims);
    }
}
