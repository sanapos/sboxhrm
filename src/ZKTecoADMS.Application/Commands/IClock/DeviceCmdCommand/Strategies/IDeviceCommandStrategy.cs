using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Interfaces;

/// <summary>
/// Strategy interface for handling different device command responses
/// </summary>
public interface IDeviceCommandStrategy
{
    /// <summary>
    /// Executes the strategy for a specific command type
    /// </summary>
    /// <param name="device">The device that sent the command response</param>
    /// <param name="objectRefId">The ID of the object being operated on (e.g., User ID)</param>
    /// <param name="response">The parsed command response from the device</param>
    /// <param name="cancellationToken">Cancellation token</param>
    Task ExecuteAsync(Device device, Guid objectRefId, ClockCommandResponse response, CancellationToken cancellationToken);
}
