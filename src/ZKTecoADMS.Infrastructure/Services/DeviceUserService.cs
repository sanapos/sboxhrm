using System.Data;
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
        // Filter out employees with duplicate PINs
        var employeePins = await context.DeviceUsers
            .Where(u => u.DeviceId == deviceId)
            .Select(u => u.Pin)
            .ToListAsync();
            
        var device = await deviceRepository.GetSingleAsync(d => d.Id == deviceId);
        
        if(device == null)
        {
            throw new ArgumentException("Device not found", nameof(deviceId));
        }

        var validUsers = newUsers
            .Where(u => !employeePins.Contains(u.Pin))
            .ToList();

        if (validUsers.Count != 0)
        {
            await context.DeviceUsers.AddRangeAsync(validUsers);
            await context.SaveChangesAsync();
        }
        // await CreateEmployeeAccounts(validUsers, device);

        // logger.LogInformation("Created {Count} employees", validUsers.Count);
        return validUsers;
    }


}