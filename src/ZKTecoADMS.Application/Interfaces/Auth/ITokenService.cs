using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Interfaces.Auth;

public interface ITokenService
{
    Task<string> GetTokenAsync(ApplicationUser user);
}
