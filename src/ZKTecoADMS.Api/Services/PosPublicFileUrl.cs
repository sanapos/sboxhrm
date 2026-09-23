using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace ZKTecoADMS.Api.Services;

/// <summary>Link công khai xem file upload (ảnh hàng hóa / catalog mẫu).</summary>
internal static class PosPublicFileUrl
{
    public static string ForPath(HttpRequest request, string? path)
    {
        var p = (path ?? "").Trim();
        if (p.Length == 0) return "";
        if (p.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
            || p.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
            return p;

        p = p.TrimStart('/');
        var cfg = request.HttpContext.RequestServices.GetService<IConfiguration>();
        var configured = (cfg?["PublicWebBaseUrl"] ?? "").Trim().TrimEnd('/');
        string root;
        if (!string.IsNullOrWhiteSpace(configured))
        {
            root = configured;
        }
        else
        {
            var proto = request.Headers["X-Forwarded-Proto"].FirstOrDefault() ?? request.Scheme;
            var host = request.Headers["X-Forwarded-Host"].FirstOrDefault() ?? request.Host.Value;
            root = $"{proto}://{host}".TrimEnd('/');
        }

        return $"{root}/api/upload/public-serve?path={Uri.EscapeDataString(p)}";
    }
}
