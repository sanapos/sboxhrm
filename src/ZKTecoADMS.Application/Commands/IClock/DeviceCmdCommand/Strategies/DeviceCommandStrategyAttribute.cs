using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.IClock.DeviceCmdCommand.Strategies;

/// <summary>
/// Attribute to mark which device command type a strategy handles
/// </summary>
[AttributeUsage(AttributeTargets.Class, AllowMultiple = false)]
public class DeviceCommandStrategyAttribute : Attribute
{
    public DeviceCommandTypes CommandType { get; }

    public DeviceCommandStrategyAttribute(DeviceCommandTypes commandType)
    {
        CommandType = commandType;
    }
}
