using ZKTecoADMS.Application.Commands.IClock.CDataPost.Strategy;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.IClock.DeviceCmdCommand.Strategies;

/// <summary>
/// Lệnh INFO: máy trả <c>CMD=INFO\n~DeviceName=…\nFWVersion=…\n~Platform=…\nPushVersion=…</c>.
/// Ghi vào DeviceInfo như khối options — máy push «lite» (LX35) không tự gửi options,
/// nên đây là nguồn duy nhất cho Platform / PushVersion → nhận đúng nhóm máy (PushLite).
/// </summary>
[DeviceCommandStrategy(DeviceCommandTypes.GetDeviceInfo)]
public class GetDeviceInfoStrategy(IServiceProvider serviceProvider) : IDeviceCommandStrategy
{
    public async Task ExecuteAsync(Device device, Guid objectRefId, ClockCommandResponse response, CancellationToken cancellationToken)
    {
        if (!response.IsSuccess) return;
        var body = InfoBody(response.CMD);
        if (body.Length == 0) return;
        await new PostOptionsStrategy(serviceProvider).ProcessDataAsync(device, body);
    }

    /// <summary>Bỏ dòng đầu «INFO», giữ các dòng key=value.</summary>
    public static string InfoBody(string? cmd)
    {
        if (string.IsNullOrWhiteSpace(cmd)) return string.Empty;
        var lines = cmd.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n');
        var first = lines[0].Trim();
        var rest = first.Equals("INFO", StringComparison.OrdinalIgnoreCase) || !first.Contains('=')
            ? lines.Skip(1)
            : lines;
        return string.Join("\n", rest.Select(l => l.Trim()).Where(l => l.Contains('=')));
    }
}
