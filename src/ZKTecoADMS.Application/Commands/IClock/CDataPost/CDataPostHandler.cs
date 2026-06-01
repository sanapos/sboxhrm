using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Commands.IClock.CDataPost.Strategy;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.IClock.CDataPost;

public class CDataPostHandler(
    IDeviceService deviceService,
    IDeviceCmdService deviceCmdService,
    ILogger<CDataPostHandler> logger,
    IServiceProvider serviceProvider
    ) : ICommandHandler<CDataPostCommand, string>
{
    public async Task<string> Handle(CDataPostCommand request, CancellationToken cancellationToken)
    {
        var sn = request.SN;
        var bodyLen = request.Body?.Length ?? 0;
        logger.LogWarning("[CDataPost] Device {SN}, Table={Table}, BodyLength={Length}",
            sn, request.Table, bodyLen);
        if (bodyLen > 0 && bodyLen <= 2000)
        {
            logger.LogDebug("[CDataPost] Body sample: {Body}", request.Body);
        }
        else if (bodyLen > 2000)
        {
            logger.LogInformation(
                "[CDataPost] Large body from {SN} table={Table} ({Length} chars) — body not logged",
                sn, request.Table, bodyLen);
        }
        
        var tableUpper = request.Table?.ToUpperInvariant() ?? "";
        if (string.IsNullOrWhiteSpace(request.Body))
        {
            if (tableUpper is "OPERLOG" or "USERINFO" or "ATTLOG")
            {
                logger.LogWarning(
                    "[CDataPost] Empty {Table} body from {SN} — kết thúc phiên sync",
                    tableUpper, sn);
            }
            else
            {
                logger.LogWarning("Empty body received from device {SerialNumber}, table={Table}", sn, request.Table);
                return ClockResponses.Fail;
            }
        }

        var device = await deviceService.GetDeviceBySerialNumberAsync(sn);
        if (device == null)
        {
            logger.LogError("Device not found: {SerialNumber}", sn);
            return ClockResponses.Fail;
        }

        // Cập nhật heartbeat khi thiết bị gửi dữ liệu (POST cdata)
        await deviceService.UpdateDeviceHeartbeatAsync(sn);

        // Thiết bị chưa liên kết cửa hàng → không lưu dữ liệu nhưng vẫn trả OK
        if (!device.StoreId.HasValue)
        {
            logger.LogWarning("[CDataPost] Device {SN} not linked to any store. Data ignored.", sn);
            return ClockResponses.Ok;
        }

        if (!string.IsNullOrWhiteSpace(request.Body))
        {
            var strategyContext = new PostStrategyContext(serviceProvider, tableUpper);
            await strategyContext.ExecuteAsync(device, request.Body);
        }
        else if (tableUpper is "OPERLOG" or "USERINFO" or "ATTLOG")
        {
            var strategyContext = new PostStrategyContext(serviceProvider, tableUpper);
            await strategyContext.ExecuteAsync(device, string.Empty);
        }

        return ClockResponses.Ok;
    }

    /// <summary>
    /// Máy PUSH thường không gọi CDataGet — đóng lệnh SyncAttendances kẹt Sent để ATTLOGStamp không còn 0.
    /// </summary>
    private async Task AutoCompleteStaleSyncAttendancesAsync(Guid deviceId)
    {
        var cutoff = DateTime.Now.AddMinutes(-10);
        var pending = await deviceCmdService.GetPendingCommandsAsync(deviceId);
        foreach (var cmd in pending.Where(c =>
                     c.CommandType == DeviceCommandTypes.SyncAttendances
                     && c.Status == CommandStatus.Sent
                     && c.SentAt.HasValue
                     && c.SentAt.Value < cutoff))
        {
            await deviceCmdService.UpdateCommandStatusAsync(cmd.Id, CommandStatus.Success);
            logger.LogInformation(
                "[CDataPost] Auto-completed stale SyncAttendances {CommandId} for device {DeviceId} (sent {SentAt})",
                cmd.Id, deviceId, cmd.SentAt);
        }
    }
}