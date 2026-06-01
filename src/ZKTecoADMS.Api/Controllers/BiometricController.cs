using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Controller quáº£n lÃ½ sinh tráº¯c há»c (vÃ¢n tay, khuÃ´n máº·t) giá»¯a cÃ¡c thiáº¿t bá»‹.
/// Há»— trá»£ xem, thá»‘ng kÃª vÃ  sao chÃ©p dá»¯ liá»‡u sinh tráº¯c giá»¯a cÃ¡c mÃ¡y cháº¥m cÃ´ng.
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
    /// Láº¥y danh sÃ¡ch dá»¯ liá»‡u sinh tráº¯c há»c cá»§a má»™t thiáº¿t bá»‹
    /// </summary>
    [HttpGet("device/{deviceId}")]
    [RequireModulePermission("Device", ModulePermissionAction.View)]
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
    /// Láº¥y thá»‘ng kÃª tá»•ng há»£p sinh tráº¯c há»c cá»§a má»™t thiáº¿t bá»‹
    /// </summary>
    [HttpGet("device/{deviceId}/summary")]
    [RequireModulePermission("Device", ModulePermissionAction.View)]
    public async Task<ActionResult> GetBiometricSummary(Guid deviceId)
    {
        var device = await dbContext.Devices.FindAsync(deviceId);
        if (device == null)
            return NotFound(AppResponse<object>.Fail("KhÃ´ng tÃ¬m tháº¥y thiáº¿t bá»‹"));

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

        // Äáº¿m sá»‘ vÃ¢n tay/khuÃ´n máº·t cÃ³ vÃ  chÆ°a cÃ³ template data
        var fingerprintsWithTemplate = await dbContext.FingerprintTemplates
            .CountAsync(f => f.Employee.DeviceId == deviceId && f.Template != null && f.Template != "");
        var fingerprintsWithoutTemplate = totalFingerprints - fingerprintsWithTemplate;

        var facesWithTemplate = await dbContext.FaceTemplates
            .CountAsync(f => f.Employee.DeviceId == deviceId && f.Template != null && f.Template != "");
        var facesWithoutTemplate = totalFaces - facesWithTemplate;

        // Kiá»ƒm tra cÃ³ lá»‡nh sync Ä‘ang chá» khÃ´ng
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
    /// Gá»­i lá»‡nh CHECK BIODATA tá»›i thiáº¿t bá»‹ Ä‘á»ƒ Ä‘á»“ng bá»™ dá»¯ liá»‡u sinh tráº¯c vá» server.
    /// </summary>
    [HttpPost("device/{deviceId}/sync")]
    [RequireModulePermission("Device", ModulePermissionAction.Create)]
    public async Task<ActionResult> SyncBiometrics(Guid deviceId)
    {
        var device = await dbContext.Devices.FindAsync(deviceId);
        if (device == null)
            return NotFound(AppResponse<object>.Fail("KhÃ´ng tÃ¬m tháº¥y thiáº¿t bá»‹"));

        // Kiá»ƒm tra xem Ä‘Ã£ cÃ³ lá»‡nh sync Ä‘ang chá» chÆ°a
        var pendingSync = await dbContext.DeviceCommands
            .AnyAsync(c => c.DeviceId == deviceId 
                && (c.CommandType == DeviceCommandTypes.SyncFingerprints || c.CommandType == DeviceCommandTypes.SyncFaces)
                && (c.Status == CommandStatus.Created || c.Status == CommandStatus.Sent));

        if (pendingSync)
            return BadRequest(AppResponse<object>.Fail("Äang cÃ³ lá»‡nh Ä‘á»“ng bá»™ sinh tráº¯c chá» xá»­ lÃ½. Vui lÃ²ng Ä‘á»£i hoÃ n thÃ nh."));

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
            Message = "ÄÃ£ gá»­i lá»‡nh Ä‘á»“ng bá»™ sinh tráº¯c há»c. Vui lÃ²ng chá» thiáº¿t bá»‹ pháº£n há»“i.",
            CommandId = syncCmd.Id
        }));
    }

    // ==================== CANCEL SYNC ====================

    /// <summary>
    /// Há»§y lá»‡nh Ä‘á»“ng bá»™ sinh tráº¯c Ä‘ang chá» (khi bá»‹ káº¹t quÃ¡ lÃ¢u).
    /// </summary>
    [HttpPost("device/{deviceId}/cancel-sync")]
    [RequireModulePermission("Device", ModulePermissionAction.Create)]
    public async Task<ActionResult> CancelSync(Guid deviceId)
    {
        var pendingSyncCommands = await dbContext.DeviceCommands
            .AsTracking()
            .Where(c => c.DeviceId == deviceId
                && (c.CommandType == DeviceCommandTypes.SyncFingerprints || c.CommandType == DeviceCommandTypes.SyncFaces)
                && (c.Status == CommandStatus.Created || c.Status == CommandStatus.Sent))
            .ToListAsync();

        if (pendingSyncCommands.Count == 0)
            return Ok(AppResponse<object>.Success(new { Message = "KhÃ´ng cÃ³ lá»‡nh Ä‘á»“ng bá»™ nÃ o Ä‘ang chá».", CancelledCount = 0 }));

        foreach (var cmd in pendingSyncCommands)
        {
            cmd.Status = CommandStatus.Failed;
            cmd.ErrorMessage = "ÄÃ£ bá»‹ há»§y bá»Ÿi ngÆ°á»i dÃ¹ng";
            cmd.CompletedAt = DateTime.UtcNow;
        }

        await dbContext.SaveChangesAsync();

        logger.LogWarning("[CancelSync] Cancelled {Count} pending sync commands for device {DeviceId}", 
            pendingSyncCommands.Count, deviceId);

        return Ok(AppResponse<object>.Success(new
        {
            Message = $"ÄÃ£ há»§y {pendingSyncCommands.Count} lá»‡nh Ä‘á»“ng bá»™.",
            CancelledCount = pendingSyncCommands.Count
        }));
    }

    // ==================== CANCEL ALL PENDING COMMANDS ====================

    /// <summary>
    /// Há»§y Táº¤T Cáº¢ lá»‡nh Ä‘ang chá» cá»§a thiáº¿t bá»‹ (khi bá»‹ káº¹t).
    /// </summary>
    [HttpPost("device/{deviceId}/cancel-all-commands")]
    [RequireModulePermission("Device", ModulePermissionAction.Create)]
    public async Task<ActionResult> CancelAllCommands(Guid deviceId)
    {
        var pendingCommands = await dbContext.DeviceCommands
            .AsTracking()
            .Where(c => c.DeviceId == deviceId
                && (c.Status == CommandStatus.Created || c.Status == CommandStatus.Sent))
            .ToListAsync();

        if (pendingCommands.Count == 0)
            return Ok(AppResponse<object>.Success(new { Message = "KhÃ´ng cÃ³ lá»‡nh nÃ o Ä‘ang chá».", CancelledCount = 0 }));

        foreach (var cmd in pendingCommands)
        {
            cmd.Status = CommandStatus.Failed;
            cmd.ErrorMessage = "ÄÃ£ bá»‹ há»§y bá»Ÿi ngÆ°á»i dÃ¹ng";
            cmd.CompletedAt = DateTime.UtcNow;
        }

        await dbContext.SaveChangesAsync();

        logger.LogWarning("[CancelAllCommands] Cancelled {Count} pending commands for device {DeviceId}", 
            pendingCommands.Count, deviceId);

        return Ok(AppResponse<object>.Success(new
        {
            Message = $"ÄÃ£ há»§y {pendingCommands.Count} lá»‡nh Ä‘ang chá».",
            CancelledCount = pendingCommands.Count
        }));
    }

}

