using ZKTecoADMS.Application.DTOs.Auth;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Interfaces.Auth;

public interface IAuthenticateService
{
    /// <param name="replacingRefreshToken">Làm mới: token máy gửi lên — chỉ thay đúng phiên đó, giữ phiên các máy khác.</param>
    Task<AppResponse<AuthenticateResponse>> Authenticate(ApplicationUser user, CancellationToken cancellationToken,
        string? replacingRefreshToken = null);
}