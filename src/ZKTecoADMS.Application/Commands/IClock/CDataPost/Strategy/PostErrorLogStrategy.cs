using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Commands.IClock.CDataPost.Strategy;

/// <summary>
/// POST /iclock/cdata?table=ERRORLOG — cảnh báo từ ESP32 gateway
/// (mất máy chấm công LAN, lỗi giao tiếp, đồng bộ quá lâu).
/// </summary>
public class PostErrorLogStrategy(IServiceProvider serviceProvider) : IPostStrategy
{
    private readonly IDeviceStatusNotificationService _notifications =
        serviceProvider.GetRequiredService<IDeviceStatusNotificationService>();
    private readonly ILogger<PostErrorLogStrategy> _logger =
        serviceProvider.GetRequiredService<ILogger<PostErrorLogStrategy>>();

    public async Task<string> ProcessDataAsync(Device device, string body)
    {
        var fields = ParseFields(body);
        var code = Get(fields, "CODE", "Code") ?? "GW_ALERT";
        var msg = Get(fields, "MSG", "Message", "msg") ?? body?.Trim() ?? "";
        _ = int.TryParse(Get(fields, "RECORDS", "Records"), out var records);
        _ = long.TryParse(Get(fields, "DURATION_MS", "DurationMs"), out var durationMs);

        _logger.LogWarning(
            "[ErrorLog] SN={SN} code={Code} records={Records} durationMs={Duration} msg={Msg}",
            device.SerialNumber, code, records, durationMs, msg);

        await _notifications.NotifyDeviceAlertAsync(device, code, msg, records, durationMs);
        return ClockResponses.Ok;
    }

    private static Dictionary<string, string> ParseFields(string? body)
    {
        var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (string.IsNullOrWhiteSpace(body)) return map;

        var normalized = body.Replace("\r\n", "\n").Replace('\r', '\n');
        foreach (var line in normalized.Split('\n', StringSplitOptions.RemoveEmptyEntries))
        {
            var trimmed = line.Trim();
            var eq = trimmed.IndexOf('=');
            if (eq <= 0) continue;
            map[trimmed[..eq].Trim()] = trimmed[(eq + 1)..].Trim();
        }
        return map;
    }

    private static string? Get(Dictionary<string, string> map, params string[] keys)
    {
        foreach (var key in keys)
        {
            if (map.TryGetValue(key, out var value) && !string.IsNullOrWhiteSpace(value))
                return value;
        }
        return null;
    }
}
