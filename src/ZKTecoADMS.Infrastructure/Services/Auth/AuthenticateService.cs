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
    IRepository<UserRefreshToken> refreshTokenRepository) : IAuthenticateService
{
    public async Task<AppResponse<AuthenticateResponse>> Authenticate(ApplicationUser user, CancellationToken cancellationToken)
    {
        var accessToken = await accessTokenService.GetTokenAsync(user);
        var refreshToken = await refreshTokenService.GetTokenAsync(user);
        var currentUserRefreshToken = await refreshTokenRepository.GetSingleAsync(rf => rf.ApplicationUserId == user.Id, cancellationToken: cancellationToken);

        var refreshTokenEntity = currentUserRefreshToken ?? new UserRefreshToken
        {
            Id = Guid.NewGuid(),
            ApplicationUserId = user.Id,
        };

        refreshTokenEntity.RefreshToken = refreshToken;

        await refreshTokenRepository.AddOrUpdateAsync(refreshTokenEntity, cancellationToken);

        return AppResponse<AuthenticateResponse>.Success(new AuthenticateResponse(accessToken, refreshToken));
    }
}