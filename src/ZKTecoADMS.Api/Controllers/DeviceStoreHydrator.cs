using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.SystemAdmin;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

internal static class DeviceStoreHydrator
{
    public static async Task<List<SystemDeviceDto>> ToSystemDeviceDtosAsync(
        ZKTecoDbContext db,
        IReadOnlyList<Device> devices,
        CancellationToken cancellationToken = default)
    {
        if (devices.Count == 0)
            return [];

        var storeMap = devices
            .Where(d => d.Store != null)
            .Select(d => d.Store!)
            .GroupBy(s => s.Id)
            .ToDictionary(g => g.Key, g => g.First());

        var missingStoreIds = devices
            .Where(d => d.StoreId.HasValue && (d.Store == null || !storeMap.ContainsKey(d.StoreId.Value)))
            .Select(d => d.StoreId!.Value)
            .Distinct()
            .ToList();

        if (missingStoreIds.Count > 0)
        {
            var fetched = await db.Stores.AsNoTracking()
                .Include(s => s.Agent)
                .Where(s => missingStoreIds.Contains(s.Id))
                .ToListAsync(cancellationToken);

            foreach (var store in fetched)
                storeMap[store.Id] = store;
        }

        return devices
            .Select(d =>
            {
                Store? store = d.Store;
                if (store == null && d.StoreId.HasValue)
                    storeMap.TryGetValue(d.StoreId.Value, out store);
                return AgentStoreMapper.ToSystemDeviceDto(d, store);
            })
            .ToList();
    }
}
