using ZKTecoADMS.Application.DTOs.SystemAdmin;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

internal static class AgentStoreMapper
{
    public static StoreDetailDto ToStoreDetailDto(Store store) => new(
        store.Id,
        store.Name,
        store.Code,
        store.Description,
        store.Address,
        store.Province,
        store.Phone,
        store.IsActive,
        store.IsLocked,
        store.LockReason,
        store.LicenseType.ToString(),
        store.LicenseKey,
        store.ExpiryDate,
        store.MaxUsers,
        store.MaxDevices,
        store.RenewalCount,
        store.ServicePackageId,
        store.ServicePackage?.Name,
        store.TrialStartDate,
        store.TrialDays,
        store.OwnerId,
        store.Owner?.FullName,
        store.Owner?.Email,
        store.AgentId,
        store.Agent?.Name,
        store.Agent?.Email,
        store.Users.Count,
        store.Devices.Count,
        store.Users.Count(u => u.Role == nameof(Roles.Employee)),
        store.CreatedAt,
        store.UpdatedAt
    );

    public static SystemDeviceDto ToSystemDeviceDto(Device device, Store? store = null)
    {
        store ??= device.Store;
        return new SystemDeviceDto(
            device.Id,
            device.SerialNumber,
            device.DeviceName,
            device.IpAddress,
            device.DeviceStatus == "Online",
            device.StoreId,
            store?.Name,
            store?.Code,
            device.LastOnline,
            device.CreatedAt,
            store?.AgentId,
            store?.Agent?.Name,
            device.IsClaimed
        );
    }
}
