using System.Security.Cryptography;

namespace ZKTecoADMS.Application.Helpers;

public static class CommunicationShareTokenHelper
{
    public static string Generate()
    {
        var bytes = RandomNumberGenerator.GetBytes(24);
        return Convert.ToBase64String(bytes)
            .TrimEnd('=')
            .Replace('+', '-')
            .Replace('/', '_');
    }
}
