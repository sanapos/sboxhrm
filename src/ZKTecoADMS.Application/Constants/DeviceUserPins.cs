using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Constants;

/// <summary>
/// PIN trên máy ZK thường là số (001 == 1). Copy/enroll phải khớp cả hai dạng.
/// </summary>
public static class DeviceUserPins
{
    public const string EnrolledViaAdmsPlaceholder = "enrolled-via-adms";

    public static bool EqualsPin(string? a, string? b)
    {
        if (string.IsNullOrWhiteSpace(a) || string.IsNullOrWhiteSpace(b)) return false;
        var x = a.Trim();
        var y = b.Trim();
        if (x.Equals(y, StringComparison.OrdinalIgnoreCase)) return true;
        if (long.TryParse(x, out var nx) && long.TryParse(y, out var ny))
            return nx == ny;
        return false;
    }

    public static string Key(string? pin)
    {
        var p = (pin ?? "").Trim();
        if (p.Length == 0) return "";
        return long.TryParse(p, out var n) ? n.ToString() : p;
    }

    public static bool IsCopyableTemplate(string? template)
    {
        if (string.IsNullOrWhiteSpace(template)) return false;
        var t = template.Trim();
        if (t.Equals(EnrolledViaAdmsPlaceholder, StringComparison.OrdinalIgnoreCase))
            return false;
        return t.Length >= 80;
    }

    public static async Task<DeviceUser?> FindOnDeviceAsync(
        IRepository<DeviceUser> repo,
        Guid deviceId,
        string pin,
        CancellationToken cancellationToken = default)
    {
        var exact = await repo.GetSingleAsync(
            u => u.DeviceId == deviceId && u.Pin == pin,
            cancellationToken: cancellationToken);
        if (exact != null) return exact;

        var users = await repo.GetAllAsync(
            u => u.DeviceId == deviceId,
            cancellationToken: cancellationToken);
        return users.FirstOrDefault(u => EqualsPin(u.Pin, pin));
    }
}
