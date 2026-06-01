using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Core.Services;

public class DeviceUserService(
    ZKTecoDbContext context,
    IRepository<Device> deviceRepository) : IDeviceUserService
{
    public async Task<DeviceUser?> GetEmployeeByIdAsync(Guid id)
    {
        return await context.DeviceUsers.FindAsync(id);
    }

    public async Task<DeviceUser?> GetDeviceUserByPinAsync(Guid deviceId, string pin)
    {
        return await context.DeviceUsers.FirstOrDefaultAsync(u => u.Pin == pin && u.DeviceId == deviceId);
    }

    public async Task<IEnumerable<DeviceUser>> CreateDeviceUsersAsync(Guid deviceId, IEnumerable<DeviceUser> newUsers)
    {
        var device = await deviceRepository.GetSingleAsync(d => d.Id == deviceId);
        if (device == null)
        {
            throw new ArgumentException("Device not found", nameof(deviceId));
        }

        var incoming = newUsers.ToList();
        if (incoming.Count == 0)
        {
            return [];
        }

        var pins = incoming.Select(u => u.Pin).Distinct().ToList();
        var existingByPin = await context.DeviceUsers
            .Where(u => u.DeviceId == deviceId && pins.Contains(u.Pin))
            .ToDictionaryAsync(u => u.Pin);

        var toInsert = new List<DeviceUser>();
        var updated = new List<DeviceUser>();

        foreach (var u in incoming)
        {
            if (existingByPin.TryGetValue(u.Pin, out var existing))
            {
                existing.Name = u.Name;
                existing.CardNumber = u.CardNumber;
                existing.Password = u.Password;
                existing.GroupId = u.GroupId;
                existing.Privilege = u.Privilege;
                existing.VerifyMode = u.VerifyMode;
                if (u.EmployeeId.HasValue)
                {
                    existing.EmployeeId = u.EmployeeId;
                }
                updated.Add(existing);
            }
            else
            {
                u.DeviceId = deviceId;
                toInsert.Add(u);
            }
        }

        if (updated.Count > 0)
        {
            context.DeviceUsers.UpdateRange(updated);
        }

        if (toInsert.Count > 0)
        {
            await context.DeviceUsers.AddRangeAsync(toInsert);
        }

        if (updated.Count > 0 || toInsert.Count > 0)
        {
            await context.SaveChangesAsync();
        }

        return toInsert.Concat(updated);
    }
}
