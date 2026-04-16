using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Repositories;

namespace ZKTecoADMS.Core.Services;


public class DeviceService(
    IRepository<Device> deviceRepository,
    ILogger<DeviceService> logger,
    ZKTecoDbContext context)
    : IDeviceService
{

    public async Task<Device?> GetDeviceBySerialNumberAsync(string serialNumber)
    {
        // IgnoreQueryFilters() để tìm cả thiết bị chưa được gán StoreId (auto-registered)
        // Không dùng repository vì cần bypass tenant filter
        return await context.Devices
            .IgnoreQueryFilters()
            .AsNoTracking()
            .FirstOrDefaultAsync(d => d.SerialNumber == serialNumber && d.Deleted == null);
    }

    public async Task UpdateDeviceHeartbeatAsync(string serialNumber)
    {
        var now = DateTime.UtcNow;
        // Use ExecuteUpdateAsync to bypass change tracking issues
        var rowsAffected = await context.Devices
            .IgnoreQueryFilters()
            .Where(d => d.SerialNumber == serialNumber && d.Deleted == null)
            .ExecuteUpdateAsync(setters => setters
                .SetProperty(d => d.LastOnline, now)
                .SetProperty(d => d.DeviceStatus, "Online")
                .SetProperty(d => d.UpdatedAt, now));
        
        if (rowsAffected == 0)
        {
            logger.LogWarning("[Heartbeat] Device with SN: {SN} not found for heartbeat update", serialNumber);
        }
    }

    public async Task<IEnumerable<DeviceCommand>> GetPendingCommandsAsync(Guid deviceId)
    {
        return await context.DeviceCommands
            .Where(c => c.DeviceId == deviceId && c.Status == CommandStatus.Created)
            .OrderByDescending(c => c.Priority)
            .ThenBy(c => c.CreatedAt)
            .ToListAsync();
    }

    public async Task<IEnumerable<DeviceCommand>> GetCommandsAsync(Guid deviceId)
    {
        return await context.DeviceCommands
            .Where(c => c.DeviceId == deviceId)
            .OrderByDescending(c => c.Priority)
            .ThenBy(c => c.CreatedAt)
            .ToListAsync();
    }

    public async Task<IEnumerable<DeviceCommand>> GetAllDeviceCommandsAsync(Guid deviceId)
    {
        return await context.DeviceCommands.Where(i => i.DeviceId == deviceId).ToListAsync();
    }

    public async Task<DeviceCommand> CreateCommandAsync(DeviceCommand command)
    {
        await context.DeviceCommands.AddAsync(command);
        await context.SaveChangesAsync();
        return command;
    }

    public async Task MarkCommandAsSentAsync(Guid commandId)
    {
        var command = await context.DeviceCommands.FindAsync(commandId);
        if (command != null)
        {
            command.Status = CommandStatus.Sent;
            command.SentAt = DateTime.UtcNow;
            await context.SaveChangesAsync();
        }
    }

    public async Task UpdateCommandStatusAsync(long commandId, CommandStatus status, string? responseData, string? errorMessage)
    {
        var command = await context.DeviceCommands.SingleOrDefaultAsync(i => i.CommandId == commandId);
        if (command != null)
        {
            command.Status = status;
            command.ResponseData = responseData;
            command.CompletedAt = DateTime.UtcNow;
            command.ErrorMessage = errorMessage;
            await context.SaveChangesAsync();
        }
    }

    public async Task DeleteDeviceAsync(Guid deviceId)
    {
        var device = await deviceRepository.GetByIdAsync(deviceId);
        await deviceRepository.DeleteAsync(device);
    }

    public async Task<AppResponse<bool>> IsUserValid(DeviceUser employee)
    {
        var existing = await context.DeviceUsers.Include(i => i.Device).FirstOrDefaultAsync(i => i.DeviceId == employee.DeviceId && i.Pin == employee.Pin);
        
        return existing == null ? AppResponse<bool>.Success() : AppResponse<bool>.Error($"Employee PIN ({employee.Pin}) is existed in device {existing.Device.DeviceName}).");
    }

    public async Task<IEnumerable<Device>> GetAllDevicesByEmployeeAsync(Guid employeeId)
    {
        return await context.Devices.Where(d => d.ManagerId == employeeId).ToListAsync();
    }

    public Task<IEnumerable<Device>> GetAllDevicesAsync()
    {
        throw new NotImplementedException();
    }

    public async Task<bool> IsExistDeviceAsync(string serialNumber)
    {
        return await GetDeviceBySerialNumberAsync(serialNumber) != null;
    }

    public async Task<Device> CreateDeviceAsync(Device device)
    {
        // Tạo DeviceInfo liên kết với Device
        var deviceInfo = new DeviceInfo
        {
            Id = Guid.NewGuid(),
            DeviceId = device.Id,
            FirmwareVersion = "Unknown",
            EnrolledUserCount = 0,
            FingerprintCount = 0,
            AttendanceCount = 0,
        };
        device.DeviceInfoId = deviceInfo.Id;

        // Add cả 2 entity vào context trước khi SaveChanges để tránh lỗi circular FK
        await context.Devices.AddAsync(device);
        await context.DeviceInfos.AddAsync(deviceInfo);
        await context.SaveChangesAsync();

        logger.LogInformation(
            "[Device Service] Created device with SN: {SerialNumber}, ID: {DeviceId}",
            device.SerialNumber, device.Id);

        return device;
    }

    public async Task<Device> CreatePendingDeviceAsync(string serialNumber, string? ipAddress = null)
    {
        // Lấy admin user làm manager mặc định
        var adminUser = await context.Users.FirstOrDefaultAsync(u => u.Email == "admin@gmail.com");
        if (adminUser == null)
        {
            adminUser = await context.Users.FirstOrDefaultAsync();
        }

        // Tạo Device trước
        var device = new Device
        {
            Id = Guid.NewGuid(),
            SerialNumber = serialNumber,
            DeviceName = $"Thiết bị mới ({serialNumber})",
            Description = "Thiết bị chờ duyệt - được tự động thêm khi kết nối",
            IpAddress = ipAddress,
            Location = "Chưa xác định",
            LastOnline = DateTime.UtcNow,
            DeviceStatus = "Pending", // Trạng thái chờ duyệt
            IsActive = false, // Chưa active cho đến khi được duyệt
            ManagerId = adminUser?.Id ?? Guid.Empty,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };

        // Tạo DeviceInfo liên kết với Device
        var deviceInfo = new DeviceInfo
        {
            Id = Guid.NewGuid(),
            DeviceId = device.Id,
            FirmwareVersion = "Unknown",
            EnrolledUserCount = 0,
            FingerprintCount = 0,
            AttendanceCount = 0,
        };

        device.DeviceInfoId = deviceInfo.Id;

        await context.Devices.AddAsync(device);
        await context.DeviceInfos.AddAsync(deviceInfo);
        try
        {
            await context.SaveChangesAsync();

            logger.LogInformation(
                "[Device Service] Created pending device with SN: {SerialNumber}, ID: {DeviceId}",
                serialNumber, device.Id);

            return device;
        }
        catch (DbUpdateException ex) when (ex.InnerException?.Message.Contains("duplicate") == true
                                           || ex.InnerException?.Message.Contains("UNIQUE") == true
                                           || ex.InnerException?.Message.Contains("unique") == true)
        {
            // Race condition: another request already created this device.
            // Detach the conflicting entities and return the already-existing record.
            context.ChangeTracker.Clear();
            logger.LogWarning(
                "[Device Service] Race condition: device with SN {SerialNumber} was already created. Fetching existing record.",
                serialNumber);

            var existing = await context.Devices.FirstOrDefaultAsync(d => d.SerialNumber == serialNumber);
            if (existing != null)
                return existing;

            // This should never happen, but re-throw to avoid silent failure.
            throw;
        }
    }

    public async Task<IEnumerable<Device>> GetPendingDevicesAsync()
    {
        return await context.Devices
            .Where(d => d.DeviceStatus == "Pending" || !d.IsActive)
            .OrderByDescending(d => d.CreatedAt)
            .ToListAsync();
    }

    public async Task<Device?> ApproveDeviceAsync(Guid deviceId, string deviceName, string? description = null, string? location = null)
    {
        var device = await deviceRepository.GetByIdAsync(deviceId);
        if (device == null)
        {
            logger.LogWarning("[Device Service] Device with ID: {DeviceId} not found for approval", deviceId);
            return null;
        }

        device.DeviceName = deviceName;
        device.Description = description ?? device.Description;
        device.Location = location ?? device.Location;
        device.DeviceStatus = "Approved";
        device.IsActive = true;
        device.UpdatedAt = DateTime.UtcNow;

        await deviceRepository.UpdateAsync(device);
        logger.LogInformation(
            "[Device Service] Approved device with SN: {SerialNumber}, ID: {DeviceId}, Name: {DeviceName}",
            device.SerialNumber, device.Id, deviceName);

        return device;
    }

    public async Task AutoActivateDeviceAsync(string serialNumber)
    {
        var now = DateTime.UtcNow;
        var updated = await context.Devices
            .Where(d => d.SerialNumber == serialNumber && !d.IsActive && d.IsClaimed && d.StoreId.HasValue)
            .ExecuteUpdateAsync(s => s
                .SetProperty(d => d.IsActive, true)
                .SetProperty(d => d.DeviceStatus, "Online")
                .SetProperty(d => d.UpdatedAt, now));

        if (updated > 0)
        {
            logger.LogInformation(
                "[Device Service] Auto-activated claimed device with SN: {SerialNumber}",
                serialNumber);
        }
    }

    public async Task<bool> RejectDeviceAsync(Guid deviceId)
    {
        var device = await deviceRepository.GetByIdAsync(deviceId);
        if (device == null)
        {
            logger.LogWarning("[Device Service] Device with ID: {DeviceId} not found for rejection", deviceId);
            return false;
        }

        await deviceRepository.DeleteAsync(device);
        logger.LogInformation(
            "[Device Service] Rejected and deleted device with SN: {SerialNumber}, ID: {DeviceId}",
            device.SerialNumber, device.Id);

        return true;
    }

    public async Task<IEnumerable<Device>> GetConnectedDevicesAsync()
    {
        var threshold = DateTime.UtcNow.AddSeconds(-90);
        return await context.Devices
            .Where(d => d.LastOnline != null && d.LastOnline > threshold)
            .OrderByDescending(d => d.LastOnline)
            .ToListAsync();
    }

    public async Task<IEnumerable<Device>> GetAvailableDevicesAsync()
    {
        // Thiết bị available: đã kết nối (có trong DB) nhưng chưa được claim
        return await context.Devices
            .Where(d => !d.IsClaimed && d.OwnerId == null)
            .OrderByDescending(d => d.LastOnline)
            .ToListAsync();
    }

    public async Task<AppResponse<Device>> ClaimDeviceAsync(Guid userId, string serialNumber, string deviceName, string? description = null, string? location = null)
    {
        // Tìm thiết bị theo Serial Number
        var device = await GetDeviceBySerialNumberAsync(serialNumber);
        
        if (device == null)
        {
            logger.LogWarning("[Device Service] Device with SN: {SerialNumber} not found for claim", serialNumber);
            return AppResponse<Device>.Error("Thiết bị với Serial Number này chưa kết nối với server. Vui lòng kiểm tra lại số Serial hoặc cấu hình kết nối trên máy chấm công.");
        }

        if (device.IsClaimed)
        {
            logger.LogWarning("[Device Service] Device with SN: {SerialNumber} already claimed by user {OwnerId}", serialNumber, device.OwnerId);
            return AppResponse<Device>.Error("Thiết bị này đã được đăng ký bởi tài khoản khác.");
        }

        // Claim thiết bị cho user
        device.OwnerId = userId;
        device.ManagerId = userId;
        device.IsClaimed = true;
        device.ClaimedAt = DateTime.UtcNow;
        device.DeviceName = deviceName;
        device.Description = description;
        device.Location = location;
        device.DeviceStatus = "Online";
        device.IsActive = true;
        device.UpdatedAt = DateTime.UtcNow;

        await deviceRepository.UpdateAsync(device);
        
        logger.LogInformation(
            "[Device Service] Device claimed successfully. SN: {SerialNumber}, ID: {DeviceId}, Owner: {OwnerId}, Name: {DeviceName}",
            serialNumber, device.Id, userId, deviceName);

        return AppResponse<Device>.Success(device);
    }

    public async Task<IEnumerable<Device>> GetDevicesByOwnerAsync(Guid ownerId)
    {
        return await context.Devices
            .Where(d => d.OwnerId == ownerId || d.ManagerId == ownerId)
            .OrderByDescending(d => d.LastOnline)
            .ToListAsync();
    }

    public async Task<AppResponse<bool>> UnclaimDeviceAsync(Guid deviceId, Guid userId)
    {
        var device = await deviceRepository.GetByIdAsync(deviceId);
        if (device == null)
        {
            logger.LogWarning("[Device Service] Device with ID: {DeviceId} not found for unclaim", deviceId);
            return AppResponse<bool>.Error("Thiết bị không tồn tại hoặc đã bị xóa.");
        }

        // Chỉ owner mới có thể unclaim
        if (device.OwnerId != userId)
        {
            logger.LogWarning("[Device Service] User {UserId} is not the owner of device {DeviceId}", userId, deviceId);
            return AppResponse<bool>.Error("Không thể hủy đăng ký thiết bị. Bạn không phải chủ sở hữu thiết bị này.");
        }

        device.OwnerId = null;
        device.IsClaimed = false;
        device.ClaimedAt = null;
        device.DeviceStatus = "Available";
        device.IsActive = false;
        device.UpdatedAt = DateTime.Now;

        await deviceRepository.UpdateAsync(device);
        
        logger.LogInformation(
            "[Device Service] Device unclaimed. SN: {SerialNumber}, ID: {DeviceId}",
            device.SerialNumber, device.Id);

        return AppResponse<bool>.Success(true);
    }
}