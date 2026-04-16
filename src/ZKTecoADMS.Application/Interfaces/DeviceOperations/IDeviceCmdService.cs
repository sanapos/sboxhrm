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
    
    Task<(DeviceCommandTypes, Guid)> GetCommandTypesAndIdAsync(long commandId);
}