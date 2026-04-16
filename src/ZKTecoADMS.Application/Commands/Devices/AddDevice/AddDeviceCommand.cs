using ZKTecoADMS.Application.DTOs.Devices;

namespace ZKTecoADMS.Application.Commands.Devices.AddDevice;

public record AddDeviceCommand : ICommand<AppResponse<DeviceDto>>
{
    public string SerialNumber { get; set; }
    public string DeviceName { get; set; }
    public string? Location { get; set; }
    public string? Description { get; set; }
    public Guid ManagerId { get; set; }
    public Guid? StoreId { get; set; }
}