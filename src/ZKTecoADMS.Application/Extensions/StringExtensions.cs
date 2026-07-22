using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Application.Extensions;

public static class StringExtensions
{
    public static ClockCommandResponse ParseClockResponse(this string body)
    {
        // Some OEM firmwares repeat keys (e.g. Return=...&Return=...); last value wins.
        var dict = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (!string.IsNullOrWhiteSpace(body))
        {
            foreach (var part in body.Split('&', StringSplitOptions.RemoveEmptyEntries))
            {
                var eq = part.IndexOf('=');
                if (eq <= 0) continue;
                var key = part[..eq].Trim();
                var value = part[(eq + 1)..].Trim();
                try { value = Uri.UnescapeDataString(value.Replace('+', ' ')); } catch { /* keep raw */ }
                dict[key] = value;
            }
        }

        return new ClockCommandResponse
        {
            CommandId = dict.TryGetValue("ID", out var idStr) ? ParseWireCommandId(idStr) : 0,
            Return = dict.TryGetValue("Return", out var retStr) && int.TryParse(retStr, out var ret) ? ret : 0,
            CMD = dict.TryGetValue("CMD", out var cmd) ? cmd : string.Empty
        };
    }

    /// <summary>
    /// Numeric IDs, or agap-style <c>OPENDOOR0</c> / <c>OPENDOOR123</c>.
    /// </summary>
    public static long ParseWireCommandId(string? idStr)
    {
        if (string.IsNullOrWhiteSpace(idStr))
            return 0;
        idStr = idStr.Trim();
        if (long.TryParse(idStr, out var id))
            return id;
        const string openDoorPrefix = "OPENDOOR";
        if (idStr.StartsWith(openDoorPrefix, StringComparison.OrdinalIgnoreCase)
            && long.TryParse(idStr[openDoorPrefix.Length..], out var doorId))
            return doorId;
        return 0;
    }
}
