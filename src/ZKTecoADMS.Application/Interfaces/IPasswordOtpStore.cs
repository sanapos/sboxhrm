namespace ZKTecoADMS.Application.Interfaces;

/// <summary>
/// Lưu OTP quên mật khẩu (distributed — dùng chung nhiều instance API).
/// </summary>
public interface IPasswordOtpStore
{
    Task SetAsync(string storeCode, string email, PasswordOtpEntry entry, TimeSpan ttl, CancellationToken cancellationToken = default);

    Task<PasswordOtpEntry?> GetAsync(string storeCode, string email, CancellationToken cancellationToken = default);

    Task RemoveAsync(string storeCode, string email, CancellationToken cancellationToken = default);

    /// <summary>Cập nhật số lần nhập sai OTP (giữ TTL còn lại nếu có thể).</summary>
    Task UpdateAsync(string storeCode, string email, PasswordOtpEntry entry, TimeSpan ttl, CancellationToken cancellationToken = default);

    /// <summary>
    /// True nếu còn trong cooldown gửi lại OTP.
    /// </summary>
    Task<bool> IsSendCooldownActiveAsync(string storeCode, string email, CancellationToken cancellationToken = default);

    Task MarkSendCooldownAsync(string storeCode, string email, TimeSpan cooldown, CancellationToken cancellationToken = default);
}

public sealed class PasswordOtpEntry
{
    public string Otp { get; set; } = string.Empty;
    public string ResetToken { get; set; } = string.Empty;
    public string UserId { get; set; } = string.Empty;
    public int FailedAttempts { get; set; }
}
