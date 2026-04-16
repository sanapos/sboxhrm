using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Auth;
using ZKTecoADMS.Application.Interfaces.Auth;

namespace ZKTecoADMS.Application.Commands.Auth.Refresh;

public class RefreshCommandHandler(
    IRefreshTokenValidatorService tokenValidatorService,
    IAuthenticateService authenticateService,
    IRepository<UserRefreshToken> refreshTokenRepository,
    UserManager<ApplicationUser> userManager
    ) : ICommandHandler<RefreshCommand, AppResponse<AuthenticateResponse>>
{
    public async Task<AppResponse<AuthenticateResponse>> Handle(RefreshCommand command, CancellationToken cancellationToken)
    {
        if (!tokenValidatorService.Validate(command.RefreshToken))
        {
            return AppResponse<AuthenticateResponse>.Error("Invalid refresh token.");
        }

        var userRefreshToken = await refreshTokenRepository.GetSingleAsync(
            urt => urt.RefreshToken == command.RefreshToken,
            includeProperties: [nameof(UserRefreshToken.ApplicationUser)],
            cancellationToken: cancellationToken
        );

        if (userRefreshToken == null)
        {
            return AppResponse<AuthenticateResponse>.Error("Invalid refresh token.");
        }

        var user = await userManager.Users
            .Include(u => u.Employee)
            .Include(u => u.Manager)
            .Include(u => u.Store)
            .FirstOrDefaultAsync(u => u.Email == userRefreshToken.ApplicationUser.Email, cancellationToken);

        if (user == null)
        {
            return AppResponse<AuthenticateResponse>.Error("User not found.");
        }

        return await authenticateService.Authenticate(user, cancellationToken);
    }
}
