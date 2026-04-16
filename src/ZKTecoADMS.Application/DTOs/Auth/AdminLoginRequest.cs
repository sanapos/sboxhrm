namespace ZKTecoADMS.Application.DTOs.Auth;

/// <summary>
/// Admin login request - no store code required
/// </summary>
public record AdminLoginRequest(string UserName, string Password);
