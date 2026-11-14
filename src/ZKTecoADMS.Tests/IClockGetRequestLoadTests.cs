using System.Reflection;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Queries.IClock.GetRequest;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Tests;

/// <summary>
/// Máy chấm công hỏi lệnh 5 giây một lần. Lần hỏi không có lệnh chờ phải rẻ: không đếm log chấm công, không đọc
/// bảng lệnh nhiều lần (trước đây mỗi lần hỏi là một COUNT trên toàn bộ log của máy).
/// </summary>
public class IClockGetRequestLoadTests
{
    public class Stub<T> : DispatchProxy where T : class
    {
        public Func<MethodInfo, object?[]?, object?> Handle = (_, _) => null;
        public List<string> Calls = [];

        protected override object? Invoke(MethodInfo? m, object?[]? args)
        {
            Calls.Add(m!.Name);
            return Handle(m, args);
        }

        public static (T Service, Stub<T> Stub) Make()
        {
            var proxy = Create<T, Stub<T>>();
            return (proxy, (Stub<T>)(object)proxy);
        }
    }

    static GetRequestHandler Build(List<DeviceCommand> pending,
        out Stub<IDeviceCmdService> cmds, out Stub<IRepository<Attendance>> attendance)
    {
        var device = new Device { Id = Guid.NewGuid(), SerialNumber = "SN-LOAD-1", StoreId = Guid.NewGuid() };
        var (deviceSvc, deviceStub) = Stub<IDeviceService>.Make();
        deviceStub.Handle = (m, _) => m.Name == nameof(IDeviceService.GetDeviceBySerialNumberAsync)
            ? Task.FromResult<Device?>(device)
            : throw new InvalidOperationException("Không mong gọi " + m.Name);

        var (cmdSvc, cmdStub) = Stub<IDeviceCmdService>.Make();
        cmdStub.Handle = (m, _) => m.Name switch
        {
            nameof(IDeviceCmdService.GetPendingCommandsAsync) => Task.FromResult<IEnumerable<DeviceCommand>>(pending),
            nameof(IDeviceCmdService.GetCreatedCommandsAsync) => Task.FromResult<IEnumerable<DeviceCommand>>(
                pending.Where(c => c.Status == CommandStatus.Created).ToList()),
            nameof(IDeviceCmdService.UpdateCommandStatusAsync) => Task.FromResult(true),
            _ => throw new InvalidOperationException("Không mong gọi " + m.Name),
        };

        var (attRepo, attStub) = Stub<IRepository<Attendance>>.Make();
        attStub.Handle = (m, _) => throw new InvalidOperationException("Không được đụng log chấm công: " + m.Name);
        var (infoRepo, infoStub) = Stub<IRepository<DeviceInfo>>.Make();
        infoStub.Handle = (m, _) => m.ReturnType == typeof(Task<DeviceInfo?>)
            ? Task.FromResult<DeviceInfo?>(null)
            : throw new InvalidOperationException("Không mong gọi " + m.Name);

        cmds = cmdStub;
        attendance = attStub;
        return new GetRequestHandler(deviceSvc, cmdSvc, attRepo, infoRepo, NullLogger<GetRequestHandler>.Instance);
    }

    [Fact]
    public async Task Khong_co_lenh_cho_thi_tra_OK_sau_mot_lan_doc_bang_lenh()
    {
        var handler = Build([], out var cmds, out var attendance);

        var response = await handler.Handle(new GetRequestQuery("SN-LOAD-1", ""), CancellationToken.None);

        Assert.Equal(ClockResponses.Ok, response);
        Assert.Equal([nameof(IDeviceCmdService.GetPendingCommandsAsync)], cmds.Calls);
        Assert.Empty(attendance.Calls);
    }

    [Fact]
    public async Task Co_lenh_thuong_dang_cho_thi_van_gui_cho_may_va_khong_dem_log()
    {
        var command = new DeviceCommand
        {
            Id = Guid.NewGuid(), CommandId = 42, Command = "REBOOT", Status = CommandStatus.Created,
            CommandType = DeviceCommandTypes.RestartDevice, CreatedAt = DateTime.UtcNow,
        };
        var handler = Build([command], out var cmds, out var attendance);

        var response = await handler.Handle(new GetRequestQuery("SN-LOAD-1", ""), CancellationToken.None);

        Assert.Contains("REBOOT", response);
        Assert.Contains(nameof(IDeviceCmdService.UpdateCommandStatusAsync), cmds.Calls);
        // Không có lệnh đồng bộ chấm công đang chờ hoàn tất → không đếm log.
        Assert.Empty(attendance.Calls);
    }
}
