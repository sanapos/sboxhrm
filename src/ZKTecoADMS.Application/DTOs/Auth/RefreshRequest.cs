namespace ZKTecoADMS.Application.DTOs.Auth;

public class RefreshRequest
{
    public string RefreshToken { get; set; }

    /// <summary>Mã thiết bị truy cập — thiết bị đã bị gỡ trong «Thiết bị truy cập» phải đăng nhập lại.</summary>
    public string? DeviceKey { get; set; }

}
