using System.Security.Claims;

namespace ZKTecoADMS.Application.Interfaces.Auth;

public interface ITokenGeneratorService
{
    string Generate(string secretKey, double expires, IEnumerable<Claim> claims = null);
}
