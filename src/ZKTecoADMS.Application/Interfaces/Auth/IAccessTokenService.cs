using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Interfaces.Auth;

public interface IAccessTokenService : ITokenService
{
    /// <summary>Access token «Đăng nhập thay»: như token của <paramref name="user"/> nhưng mang claim
    /// impersonatedBy — server nhận ra phiên hỗ trợ (vd. không gắn token thông báo của máy Super Admin).</summary>
    Task<string> GetImpersonationTokenAsync(ApplicationUser user, Guid impersonatorId);
}
