using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;
using Microsoft.Extensions.DependencyInjection;

namespace ZKTecoADMS.Application.Commands.IClock.DeviceCmdCommand.Strategies;

/// <summary>
/// Factory for resolving the appropriate device command strategy based on command type
/// </summary>
public interface IDeviceCommandStrategyFactory
{
    /// <summary>
    /// Gets the appropriate strategy for the given command type
    /// </summary>
    /// <param name="commandType">The type of device command</param>
    /// <returns>The strategy instance, or null if no strategy is registered for the command type</returns>
    IDeviceCommandStrategy? GetStrategy(DeviceCommandTypes commandType);
}

/// <summary>
/// Implementation of the device command strategy factory
/// </summary>
public class DeviceCommandStrategyFactory : IDeviceCommandStrategyFactory
{
    private readonly IServiceProvider _serviceProvider;
    private readonly Dictionary<DeviceCommandTypes, Type> _strategyTypes;

    public DeviceCommandStrategyFactory(IServiceProvider serviceProvider)
    {
        _serviceProvider = serviceProvider;
        _strategyTypes = new Dictionary<DeviceCommandTypes, Type>();
        
        // Scan assembly for all strategy implementations
        var strategyType = typeof(IDeviceCommandStrategy);
        var strategies = strategyType.Assembly.GetTypes()
            .Where(t => t.IsClass && !t.IsAbstract && strategyType.IsAssignableFrom(t))
            .ToList();

        foreach (var strategy in strategies)
        {
            var attribute = strategy.GetCustomAttributes(typeof(DeviceCommandStrategyAttribute), false)
                .FirstOrDefault() as DeviceCommandStrategyAttribute;
                
            if (attribute != null)
            {
                _strategyTypes[attribute.CommandType] = strategy;
            }
        }
    }

    public IDeviceCommandStrategy? GetStrategy(DeviceCommandTypes commandType)
    {
        if (_strategyTypes.TryGetValue(commandType, out var strategyType))
        {
            return _serviceProvider.GetService(strategyType) as IDeviceCommandStrategy;
        }
        
        return null;
    }
}
