using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Commands.IClock.DeviceCmdCommand.Strategies;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Extensions;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.IClock.DeviceCmdCommand;

public class DeviceCmdHandler(
    IDeviceCmdService deviceCmdService,
    IDeviceCommandStrategyFactory strategyFactory,
    IDeviceService deviceService,
    ILogger<DeviceCmdHandler> logger
    ) : ICommandHandler<DeviceCmdCommand, string>
{
    public async Task<string> Handle(DeviceCmdCommand request, CancellationToken cancellationToken)
    {
        var device = await deviceService.GetDeviceBySerialNumberAsync(request.SN);
        if (device == null)
        {
            logger.LogWarning("Received DeviceCmd for unknown device SN: {SN}", request.SN);
            return ClockResponses.Fail;
        }
        
        var response = request.Body.ParseClockResponse();
        
        logger.LogWarning("[DeviceCmd] SN={SN} CommandId={CommandId} Return={Return} CMD={CMD}", 
            request.SN, response.CommandId, response.Return, response.CMD);
        
        try
        {
            var (commandType, objectRefId) = await deviceCmdService.GetCommandTypesAndIdAsync(response.CommandId);

            if (commandType == DeviceCommandTypes.SyncFingerprints)
            {
                logger.LogInformation("[DeviceCmd] SyncFingerprints acknowledged by device {SN}, keeping as Sent until data arrives", request.SN);
            }
            else
            {
                await deviceCmdService.UpdateCommandAfterExecutedAsync(response);
            }

            var strategy = strategyFactory.GetStrategy(commandType);
            if (strategy != null)
            {
                logger.LogWarning("[DeviceCmd] Executing {Strategy} for CommandType={Type}", strategy.GetType().Name, commandType);
                try
                {
                    await strategy.ExecuteAsync(device, objectRefId, response, cancellationToken);
                }
                catch (Exception strategyEx)
                {
                    logger.LogError(strategyEx, "[DeviceCmd] Strategy {Strategy} FAILED", strategy.GetType().Name);
                }
            }
        }
        catch (KeyNotFoundException ex)
        {
            logger.LogError(ex, "[DeviceCmd] Command not found for CommandId={CommandId}", response.CommandId);
            return ClockResponses.Fail;
        }
        
        return ClockResponses.Ok;
    }
}