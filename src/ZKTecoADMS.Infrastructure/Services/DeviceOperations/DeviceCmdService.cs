using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Infrastructure.Services.DeviceOperations;

public class DeviceCmdService(IRepository<DeviceCommand> deviceCmdRepository, ILogger<DeviceCmdService> logger) : IDeviceCmdService
{
    public async Task<IEnumerable<DeviceCommand>> GetCreatedCommandsAsync(Guid deviceId)
    {
        logger.LogWarning("[DeviceCmdService] GetCreatedCommandsAsync for DeviceId: {DeviceId}", deviceId);
        
        var commands = await deviceCmdRepository.GetAllAsync(cmd => cmd.DeviceId == deviceId && cmd.Status == CommandStatus.Created);
        var commandList = commands.ToList();
        
        logger.LogWarning("[DeviceCmdService] Found {Count} commands with Status=Created for DeviceId: {DeviceId}", commandList.Count, deviceId);
        
        foreach (var cmd in commandList)
        {
            logger.LogWarning("[DeviceCmdService] Command: Id={Id}, Command={Cmd}, Status={Status}, CommandType={Type}", 
                cmd.Id, cmd.Command, cmd.Status, cmd.CommandType);
        }
        
        return commandList;
    }

    /// <summary>
    /// Get commands with status Created or Sent (not yet completed)
    /// </summary>
    public async Task<IEnumerable<DeviceCommand>> GetPendingCommandsAsync(Guid deviceId)
    {
        return await deviceCmdRepository.GetAllAsync(cmd => 
            cmd.DeviceId == deviceId && 
            (cmd.Status == CommandStatus.Created || cmd.Status == CommandStatus.Sent));
    }

    public async Task<bool> UpdateCommandStatusAsync(Guid commandId, CommandStatus status)
    {
        var command = await deviceCmdRepository.GetByIdAsync(commandId);
        if (command == null)
        {
            return false;
        }
        
        command.Status = status;
        if (status == CommandStatus.Sent)
        {
            command.SentAt = DateTime.Now;
        }
        
        return await deviceCmdRepository.UpdateAsync(command);
    }

    public async Task<bool> UpdateCommandAfterExecutedAsync(ClockCommandResponse response)
    {
        var command = await deviceCmdRepository.GetSingleAsync(c => c.CommandId == response.CommandId);
        if (command == null)
        {
            return false;
        }
        
        command.Status = response.IsSuccess ? CommandStatus.Success : CommandStatus.Failed;
        command.ResponseData = response.CMD;
        command.ErrorMessage = response.Message;
        command.Return = response.Return;
        command.CompletedAt = DateTime.Now;
        
        return await deviceCmdRepository.UpdateAsync(command);
    }

    public async Task<(DeviceCommandTypes, Guid)> GetCommandTypesAndIdAsync(long commandId)
    {
        var command = await deviceCmdRepository.GetSingleAsync(c => c.CommandId == commandId);
        if (command == null)
        {
            throw new KeyNotFoundException($"Device command with ID {commandId} not found.");
        }
        
        return (command.CommandType, command.ObjectReferenceId);
    }
}