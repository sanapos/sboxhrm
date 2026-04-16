using ZKTecoADMS.Application.DTOs.Auth;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Interfaces.Auth;

public interface IAuthenticateService
{
    Task<AppResponse<AuthenticateResponse>> Authenticate(ApplicationUser user, CancellationToken cancellationToken);
}