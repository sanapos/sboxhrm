using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Commands.IClock.CDataPost.Strategy;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;

namespace ZKTecoADMS.Application.Commands.IClock.CDataPost;

public class CDataPostHandler(
    IDeviceService deviceService,
    ILogger<CDataPostHandler> logger,
    IServiceProvider serviceProvider
    ) : ICommandHandler<CDataPostCommand, string>
{
    public async Task<string> Handle(CDataPostCommand request, CancellationToken cancellationToken)
    {
        var sn = request.SN;
        logger.LogWarning("[CDataPost] Device {SN}, Table={Table}, BodyLength={Length}", 
            sn, request.Table, request.Body?.Length ?? 0);
        logger.LogWarning("[CDataPost] Body content: {Body}", request.Body);
        
        if (string.IsNullOrWhiteSpace(request.Body))
        {
            logger.LogWarning("Empty body received from device {SerialNumber}", sn);
            
            return ClockResponses.Fail;
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

        var strategyContext = new PostStrategyContext(serviceProvider, request.Table.ToUpper());
        await strategyContext.ExecuteAsync(device, request.Body);

        return ClockResponses.Ok;
    }
}