using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Interfaces;

public interface IDeviceCmdService
{
    Task<IEnumerable<DeviceCommand>> GetCreatedCommandsAsync(Guid deviceId);
    
    /// <summary>
    /// Get commands with status Created or Sent (not yet completed)
    /// </summary>
    Task<IEnumerable<DeviceCommand>> GetPendingCommandsAsync(Guid deviceId);
    
    Task<bool> UpdateCommandStatusAsync(Guid commandId, CommandStatus status);
    
    Task<bool> UpdateCommandAfterExecutedAsync(ClockCommandResponse commandResponse);

    /// <summary>Device ACK (Return=0) for sync commands — keep Sent until cdata upload completes.</summary>
    Task<bool> UpdateCommandAcknowledgedAsync(ClockCommandResponse commandResponse);
    
    Task<(DeviceCommandTypes, Guid)> GetCommandTypesAndIdAsync(long commandId);
}