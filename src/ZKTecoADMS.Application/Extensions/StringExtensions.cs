using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Application.Extensions;

public static class StringExtensions
{
    public static ClockCommandResponse ParseClockResponse(this string body)
    {
        var dict = body.Split('&')
            .Select(part => part.Split('='))
            .Where(parts => parts.Length == 2)
            .ToDictionary(parts => parts[0], parts => parts[1]);

        return new ClockCommandResponse
        {
            CommandId = dict.TryGetValue("ID", out var idStr) && long.TryParse(idStr, out var id) ? id : 0,
            Return = dict.TryGetValue("Return", out var retStr) && int.TryParse(retStr, out var ret) ? ret : 0,
            CMD = dict.TryGetValue("CMD", out var cmd) ? cmd : string.Empty
        };
    }
}
