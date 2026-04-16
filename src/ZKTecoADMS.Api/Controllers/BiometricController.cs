using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Controller quản lý sinh trắc học (vân tay, khuôn mặt) giữa các thiết bị.
/// Hỗ trợ xem, thống kê và sao chép dữ liệu sinh trắc giữa các máy chấm công.
/// </summary>
[ApiController]
[Authorize]
[Route("api/biometrics")]
public class BiometricController(
    ZKTecoDbContext dbContext,
    ILogger<BiometricController> logger
) : AuthenticatedControllerBase
{
    // ==================== GET BIOMETRICS BY DEVICE ====================

    /// <summary>
    /// Lấy danh sách dữ liệu sinh trắc học của một thiết bị
    /// </summary>
    [HttpGet("device/{deviceId}")]
    public async Task<ActionResult> GetBiometricsByDevice(Guid deviceId)
    {
        var deviceUsers = await dbContext.DeviceUsers
            .Where(du => du.DeviceId == deviceId)
            .Include(du => du.FingerprintTemplates)
            .Include(du => du.FaceTemplates)
            .OrderBy(du => du.Pin)
            .ToListAsync();

        var result = deviceUsers.Select(du => new
        {
            du.Id,
            du.Pin,
            du.Name,
            DisplayName = du.Name,
            du.DeviceId,
            FingerprintCount = du.FingerprintTemplates.Count,
            FaceCount = du.FaceTemplates.Count,
            Fingerprints = du.FingerprintTemplates.Select(f => new
            {
                f.Id,
                f.FingerIndex,
                f.TemplateSize,
                f.Quality,
                f.Version
            }),
            Faces = du.FaceTemplates.Select(f => new
            {
                f.Id,
                f.FaceIndex,
                f.TemplateSize,
                f.Version
            })
        });

        return Ok(AppResponse<object>.Success(result));
    }

    // ==================== GET SUMMARY ====================

    /// <summary>
    /// Lấy thống kê tổng hợp sinh trắc học của một thiết bị
    /// </summary>
    [HttpGet("device/{deviceId}/summary")]
    public async Task<ActionResult> GetBiometricSummary(Guid deviceId)
    {
        var device = await dbContext.Devices.FindAsync(deviceId);
        if (device == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy thiết bị"));

        var totalUsers = await dbContext.DeviceUsers
            .CountAsync(du => du.DeviceId == deviceId);

        var usersWithFingerprints = await dbContext.DeviceUsers
            .CountAsync(du => du.DeviceId == deviceId && du.FingerprintTemplates.Any());

        var usersWithFaces = await dbContext.DeviceUsers
            .CountAsync(du => du.DeviceId == deviceId && du.FaceTemplates.Any());

        var totalFingerprints = await dbContext.FingerprintTemplates
            .CountAsync(f => f.Employee.DeviceId == deviceId);

        var totalFaces = await dbContext.FaceTemplates
            .CountAsync(f => f.Employee.DeviceId == deviceId);

        // Đếm số vân tay/khuôn mặt có và chưa có template data
        var fingerprintsWithTemplate = await dbContext.FingerprintTemplates
            .CountAsync(f => f.Employee.DeviceId == deviceId && f.Template != null && f.Template != "");
        var fingerprintsWithoutTemplate = totalFingerprints - fingerprintsWithTemplate;

        var facesWithTemplate = await dbContext.FaceTemplates
            .CountAsync(f => f.Employee.DeviceId == deviceId && f.Template != null && f.Template != "");
        var facesWithoutTemplate = totalFaces - facesWithTemplate;

        // Kiểm tra có lệnh sync đang chờ không
        var hasPendingSync = await dbContext.DeviceCommands
            .AnyAsync(c => c.DeviceId == deviceId
                && (c.CommandType == DeviceCommandTypes.SyncFingerprints || c.CommandType == DeviceCommandTypes.SyncFaces)
                && (c.Status == CommandStatus.Created || c.Status == CommandStatus.Sent));

        return Ok(AppResponse<object>.Success(new
        {
            DeviceId = deviceId,
            DeviceName = device.DeviceName ?? device.SerialNumber,
            IsOnline = device.LastOnline != null && device.LastOnline > DateTime.UtcNow.AddSeconds(-90),
            TotalUsers = totalUsers,
            UsersWithFingerprints = usersWithFingerprints,
            UsersWithFaces = usersWithFaces,
            TotalFingerprints = totalFingerprints,
            TotalFaces = totalFaces,
            FingerprintsWithTemplate = fingerprintsWithTemplate,
            FingerprintsWithoutTemplate = fingerprintsWithoutTemplate,
            FacesWithTemplate = facesWithTemplate,
            FacesWithoutTemplate = facesWithoutTemplate,
            HasPendingSync = hasPendingSync
        }));
    }

    // ==================== SYNC BIOMETRICS (CHECK BIODATA) ====================

    /// <summary>
    /// Gửi lệnh CHECK BIODATA tới thiết bị để đồng bộ dữ liệu sinh trắc về server.
    /// </summary>
    [HttpPost("device/{deviceId}/sync")]
    public async Task<ActionResult> SyncBiometrics(Guid deviceId)
    {
        var device = await dbContext.Devices.FindAsync(deviceId);
        if (device == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy thiết bị"));

        // Kiểm tra xem đã có lệnh sync đang chờ chưa
        var pendingSync = await dbContext.DeviceCommands
            .AnyAsync(c => c.DeviceId == deviceId 
                && (c.CommandType == DeviceCommandTypes.SyncFingerprints || c.CommandType == DeviceCommandTypes.SyncFaces)
                && (c.Status == CommandStatus.Created || c.Status == CommandStatus.Sent));

        if (pendingSync)
            return BadRequest(AppResponse<object>.Fail("Đang có lệnh đồng bộ sinh trắc chờ xử lý. Vui lòng đợi hoàn thành."));

        var syncCmd = new DeviceCommand
        {
            DeviceId = deviceId,
            Command = ClockCommandBuilder.BuildGetFingerprintsCommand(), // "CHECK BIODATA"
            CommandType = DeviceCommandTypes.SyncFingerprints,
            Status = CommandStatus.Created,
            Priority = 3
        };

        await dbContext.DeviceCommands.AddAsync(syncCmd);
        await dbContext.SaveChangesAsync();

        logger.LogInformation("[SyncBiometrics] Created CHECK BIODATA command for device {DeviceId}", deviceId);

        return Ok(AppResponse<object>.Success(new
        {
            Message = "Đã gửi lệnh đồng bộ sinh trắc học. Vui lòng chờ thiết bị phản hồi.",
            CommandId = syncCmd.Id
        }));
    }

    // ==================== CANCEL SYNC ====================

    /// <summary>
    /// Hủy lệnh đồng bộ sinh trắc đang chờ (khi bị kẹt quá lâu).
    /// </summary>
    [HttpPost("device/{deviceId}/cancel-sync")]
    public async Task<ActionResult> CancelSync(Guid deviceId)
    {
        var pendingSyncCommands = await dbContext.DeviceCommands
            .AsTracking()
            .Where(c => c.DeviceId == deviceId
                && (c.CommandType == DeviceCommandTypes.SyncFingerprints || c.CommandType == DeviceCommandTypes.SyncFaces)
                && (c.Status == CommandStatus.Created || c.Status == CommandStatus.Sent))
            .ToListAsync();

        if (pendingSyncCommands.Count == 0)
            return Ok(AppResponse<object>.Success(new { Message = "Không có lệnh đồng bộ nào đang chờ.", CancelledCount = 0 }));

        foreach (var cmd in pendingSyncCommands)
        {
            cmd.Status = CommandStatus.Failed;
            cmd.ErrorMessage = "Đã bị hủy bởi người dùng";
            cmd.CompletedAt = DateTime.UtcNow;
        }

        await dbContext.SaveChangesAsync();

        logger.LogWarning("[CancelSync] Cancelled {Count} pending sync commands for device {DeviceId}", 
            pendingSyncCommands.Count, deviceId);

        return Ok(AppResponse<object>.Success(new
        {
            Message = $"Đã hủy {pendingSyncCommands.Count} lệnh đồng bộ.",
            CancelledCount = pendingSyncCommands.Count
        }));
    }

    // ==================== CANCEL ALL PENDING COMMANDS ====================

    /// <summary>
    /// Hủy TẤT CẢ lệnh đang chờ của thiết bị (khi bị kẹt).
    /// </summary>
    [HttpPost("device/{deviceId}/cancel-all-commands")]
    public async Task<ActionResult> CancelAllCommands(Guid deviceId)
    {
        var pendingCommands = await dbContext.DeviceCommands
            .AsTracking()
            .Where(c => c.DeviceId == deviceId
                && (c.Status == CommandStatus.Created || c.Status == CommandStatus.Sent))
            .ToListAsync();

        if (pendingCommands.Count == 0)
            return Ok(AppResponse<object>.Success(new { Message = "Không có lệnh nào đang chờ.", CancelledCount = 0 }));

        foreach (var cmd in pendingCommands)
        {
            cmd.Status = CommandStatus.Failed;
            cmd.ErrorMessage = "Đã bị hủy bởi người dùng";
            cmd.CompletedAt = DateTime.UtcNow;
        }

        await dbContext.SaveChangesAsync();

        logger.LogWarning("[CancelAllCommands] Cancelled {Count} pending commands for device {DeviceId}", 
            pendingCommands.Count, deviceId);

        return Ok(AppResponse<object>.Success(new
        {
            Message = $"Đã hủy {pendingCommands.Count} lệnh đang chờ.",
            CancelledCount = pendingCommands.Count
        }));
    }

}
