namespace ZKTecoADMS.Api.Services;

public static class ClientIp
{
    /// <summary>
    /// IP thật của client. <c>UseForwardedHeaders</c> (chỉ tin proxy nội bộ) đã đổi RemoteIpAddress
    /// thành IP nginx nhận được — không tự đọc X-Forwarded-For vì phần tử đầu do client tự đặt được.
    /// </summary>
    public static string Of(HttpContext ctx)
    {
        var ip = ctx.Connection.RemoteIpAddress;
        if (ip == null) return "";
        return (ip.IsIPv4MappedToIPv6 ? ip.MapToIPv4() : ip).ToString();
    }
}
