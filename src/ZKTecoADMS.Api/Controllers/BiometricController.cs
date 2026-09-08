using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Biometrics;
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
    /// Lấy thống kê tổng hợp sinh trắc học của một thiết bị
    /// </summary>
    [HttpGet("device/{deviceId}/summary")]
    [RequireModulePermission("Device", ModulePermissionAction.View)]
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
            IsOnline = DeviceConnectivity.IsOnline(device.LastOnline),
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
    [RequireModulePermission("Device", ModulePermissionAction.Create)]
    public async Task<ActionResult> SyncBiometrics(Guid deviceId)
    {
        var device = await dbContext.Devices
            .Include(d => d.DeviceInfo)
            .FirstOrDefaultAsync(d => d.Id == deviceId);
        if (device == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy thiết bị"));

        // Kiểm tra xem đã có lệnh sync đang chờ chưa
        var pendingSync = await dbContext.DeviceCommands
            .AnyAsync(c => c.DeviceId == deviceId 
                && (c.CommandType == DeviceCommandTypes.SyncFingerprints || c.CommandType == DeviceCommandTypes.SyncFaces)
                && (c.Status == CommandStatus.Created || c.Status == CommandStatus.Sent));

        if (pendingSync)
            return BadRequest(AppResponse<object>.Fail("Đang có lệnh đồng bộ sinh trắc chờ xử lý. Vui lòng đợi hoàn thành."));

        var now = DateTime.UtcNow;
        var stampOnly = AdmsEngineProfiles.IsAndroidVisibleLight(device.DeviceInfo, device.SerialNumber);
        QueueBiometricPullCommands(deviceId, [], now, fingerprints: true, faces: true, stampOnly: stampOnly);
        await dbContext.SaveChangesAsync();

        logger.LogInformation("[SyncBiometrics] Queued biometric pull for device {DeviceId} stampOnly={Stamp}", deviceId, stampOnly);

        return Ok(AppResponse<object>.Success(new
        {
            Message = "Đã gửi lệnh đồng bộ sinh trắc học (vân tay + khuôn mặt). Vui lòng chờ thiết bị phản hồi.",
        }));
    }

    // ==================== CANCEL SYNC ====================

    /// <summary>
    /// Hủy lệnh đồng bộ sinh trắc đang chờ (khi bị kẹt quá lâu).
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
    [RequireModulePermission("Device", ModulePermissionAction.Create)]
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

    // ==================== COPY BIOMETRICS A → B ====================

    // ZK firmware often parses command ID as a small integer. Ticks (~18 digits) is ignored.
    private static long _commandIdSeq = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() % 1_000_000;
    private static long NextCommandId()
    {
        var n = Interlocked.Increment(ref _commandIdSeq);
        if (n > 2_000_000_000)
            Interlocked.Exchange(ref _commandIdSeq, 1);
        return n;
    }

    /// <summary>
    /// Sao chép vân tay / khuôn mặt từ máy nguồn sang máy đích.
    /// sourceUserIds rỗng = mọi nhân viên trên máy nguồn đã có template trên server.
    /// </summary>
    [HttpPost("copy")]
    [RequireModulePermission("DeviceUser", ModulePermissionAction.Create)]
    public async Task<ActionResult> CopyBiometrics([FromBody] CopyBiometricsRequest request)
    {
        try
        {
            return await CopyBiometricsCore(request);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "[CopyBiometrics] {Source} → {Target}",
                request.SourceDeviceId, request.TargetDeviceId);
            return Ok(AppResponse<object>.Fail($"Copy sinh trắc thất bại: {ex.Message}"));
        }
    }

    private async Task<ActionResult> CopyBiometricsCore(CopyBiometricsRequest request)
    {
        if (request.SourceDeviceId == Guid.Empty || request.TargetDeviceId == Guid.Empty)
            return BadRequest(AppResponse<object>.Fail("Thiếu máy nguồn hoặc máy đích."));

        if (request.SourceDeviceId == request.TargetDeviceId)
            return BadRequest(AppResponse<object>.Fail("Máy nguồn và máy đích phải khác nhau."));

        if (!request.IncludeFingerprints && !request.IncludeFaces)
            return BadRequest(AppResponse<object>.Fail("Chọn ít nhất vân tay hoặc khuôn mặt."));

        var sourceDevice = await dbContext.Devices.AsNoTracking()
            .Include(d => d.DeviceInfo)
            .FirstOrDefaultAsync(d => d.Id == request.SourceDeviceId);
        var targetDevice = await dbContext.Devices.AsNoTracking()
            .Include(d => d.DeviceInfo)
            .FirstOrDefaultAsync(d => d.Id == request.TargetDeviceId);

        if (sourceDevice == null || targetDevice == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy thiết bị nguồn hoặc đích."));

        if (sourceDevice.StoreId != targetDevice.StoreId)
            return BadRequest(AppResponse<object>.Fail("Hai máy phải thuộc cùng cửa hàng."));

        if (CurrentStoreId.HasValue && sourceDevice.StoreId != CurrentStoreId && !IsAdmin)
            return BadRequest(AppResponse<object>.Fail("Thiết bị không thuộc cửa hàng của bạn."));

        var sourceQuery = dbContext.DeviceUsers
            .Where(du => du.DeviceId == request.SourceDeviceId)
            .Include(du => du.FingerprintTemplates)
            .Include(du => du.FaceTemplates)
            .AsQueryable();

        if (request.SourceUserIds is { Count: > 0 })
            sourceQuery = sourceQuery.Where(du => request.SourceUserIds.Contains(du.Id));

        var sourceUsers = await sourceQuery.OrderBy(du => du.Pin).ToListAsync();
        if (sourceUsers.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Không có nhân viên nào trên máy nguồn (hoặc bộ lọc trống)."));

        var targetUsers = await dbContext.DeviceUsers
            .Where(du => du.DeviceId == request.TargetDeviceId)
            .Include(du => du.FingerprintTemplates)
            .Include(du => du.FaceTemplates)
            .ToListAsync();
        var targetByPin = targetUsers
            .GroupBy(u => DeviceUserPins.Key(u.Pin), StringComparer.OrdinalIgnoreCase)
            .ToDictionary(g => g.Key, g => g.First(), StringComparer.OrdinalIgnoreCase);

        var now = DateTime.UtcNow;
        var usersCopied = 0;
        var usersSkipped = 0;
        var usersCreated = 0;
        var fingerprintsQueued = 0;
        var facesQueued = 0;
        var commandsQueued = 0;

        static bool HasTemplate(string? t) => DeviceUserPins.IsCopyableTemplate(t);

        var sourceIsVl = AdmsEngineProfiles.IsAndroidVisibleLight(
            sourceDevice.DeviceInfo, sourceDevice.SerialNumber);
        var targetIsVl = AdmsEngineProfiles.IsAndroidVisibleLight(
            targetDevice.DeviceInfo, targetDevice.SerialNumber);

        foreach (var source in sourceUsers)
        {
            var fps = request.IncludeFingerprints
                ? source.FingerprintTemplates.Where(f => HasTemplate(f.Template)).ToList()
                : [];
            var faces = request.IncludeFaces
                ? source.FaceTemplates.Where(f => BioPhotoCodec.HasFacePayload(f.Template, f.PhotoData)).ToList()
                : [];

            // Copy một nhân viên: vẫn gửi USERINFO (tên) dù chưa có file vân tay trên server.
            // Copy tất cả: bỏ user không có template (tránh Flash I/O hàng loạt).
            var selectedSubset = request.SourceUserIds is { Count: > 0 };
            if (fps.Count == 0 && faces.Count == 0 && !selectedSubset)
            {
                usersSkipped++;
                continue;
            }

            var createdThisUser = false;
            if (!targetByPin.TryGetValue(DeviceUserPins.Key(source.Pin), out var targetUser)
                && source.EmployeeId is Guid empId)
            {
                targetUser = targetUsers.FirstOrDefault(u => u.EmployeeId == empId);
            }

            if (targetUser == null)
            {
                targetUser = new DeviceUser
                {
                    Id = Guid.NewGuid(),
                    Pin = source.Pin,
                    Name = source.Name,
                    CardNumber = source.CardNumber,
                    Password = source.Password,
                    Privilege = source.Privilege,
                    GroupId = source.GroupId,
                    VerifyMode = source.VerifyMode,
                    DeviceId = request.TargetDeviceId,
                    EmployeeId = source.EmployeeId,
                    IsActive = true,
                    CreatedAt = now
                };
                dbContext.DeviceUsers.Add(targetUser);
                targetByPin[DeviceUserPins.Key(targetUser.Pin)] = targetUser;
                usersCreated++;
                createdThisUser = true;
            }

            targetUser.FingerprintTemplates ??= new List<FingerprintTemplate>();
            targetUser.FaceTemplates ??= new List<FaceTemplate>();

            targetUser.Name = source.Name;
            targetUser.CardNumber = source.CardNumber;
            targetUser.Password = source.Password;
            targetUser.Privilege = source.Privilege;
            targetUser.GroupId = source.GroupId;
            targetUser.VerifyMode = source.VerifyMode;
            if (source.EmployeeId.HasValue)
                targetUser.EmployeeId = source.EmployeeId;
            targetUser.UpdatedAt = now;

            // USERINFO trước FINGERTMP — luôn gửi: tên mới, và PIN có thể chưa có trên máy đích.
            dbContext.DeviceCommands.Add(new DeviceCommand
            {
                DeviceId = request.TargetDeviceId,
                CommandId = NextCommandId(),
                Command = ClockCommandBuilder.BuildAddOrUpdateEmployeeCommand(targetUser),
                Priority = 20,
                Status = CommandStatus.Created,
                CommandType = createdThisUser
                    ? DeviceCommandTypes.AddDeviceUser
                    : DeviceCommandTypes.UpdateDeviceUser,
                ObjectReferenceId = targetUser.Id,
                CreatedAt = now
            });
            commandsQueued++;

            if (fps.Count == 0 && faces.Count == 0)
            {
                usersCopied++;
                continue;
            }

            foreach (var fp in fps)
            {
                var existing = targetUser.FingerprintTemplates
                    .FirstOrDefault(t => t.FingerIndex == fp.FingerIndex);
                if (existing != null)
                {
                    existing.Template = fp.Template;
                    existing.TemplateSize = fp.TemplateSize;
                    existing.Quality = fp.Quality;
                    existing.Version = fp.Version;
                    existing.UpdatedAt = now;
                }
                else
                {
                    var copy = new FingerprintTemplate
                    {
                        Id = Guid.NewGuid(),
                        EmployeeId = targetUser.Id,
                        FingerIndex = fp.FingerIndex,
                        Template = fp.Template,
                        TemplateSize = fp.TemplateSize,
                        Quality = fp.Quality,
                        Version = fp.Version,
                        CreatedAt = now
                    };
                    dbContext.FingerprintTemplates.Add(copy);
                    targetUser.FingerprintTemplates.Add(copy);
                }

                dbContext.DeviceCommands.Add(new DeviceCommand
                {
                    DeviceId = request.TargetDeviceId,
                    CommandId = NextCommandId(),
                    Command = ClockCommandBuilder.BuildUpdateFingerprintCommand(
                        targetUser.Pin, fp.FingerIndex, fp.Template, fp.TemplateSize, fp.Quality ?? 1),
                    Priority = 10,
                    Status = CommandStatus.Created,
                    CommandType = DeviceCommandTypes.PushFingerprint,
                    ObjectReferenceId = targetUser.Id,
                    CreatedAt = now
                });
                fingerprintsQueued++;
                commandsQueued++;
            }

            foreach (var face in faces)
            {
                var jpeg = BioPhotoCodec.TryGetJpeg(face.Template, face.PhotoData);
                var existing = targetUser.FaceTemplates
                    .FirstOrDefault(t => t.FaceIndex == face.FaceIndex);
                FaceTemplate stored;
                if (existing != null)
                {
                    if (HasTemplate(face.Template))
                    {
                        existing.Template = face.Template;
                        existing.TemplateSize = face.TemplateSize;
                        existing.Version = face.Version;
                    }
                    existing.PhotoData = jpeg ?? face.PhotoData ?? existing.PhotoData;
                    existing.UpdatedAt = now;
                    stored = existing;
                }
                else
                {
                    stored = new FaceTemplate
                    {
                        Id = Guid.NewGuid(),
                        EmployeeId = targetUser.Id,
                        FaceIndex = face.FaceIndex,
                        Template = HasTemplate(face.Template)
                            ? face.Template
                            : jpeg != null ? Convert.ToBase64String(jpeg) : face.Template,
                        TemplateSize = face.TemplateSize ?? jpeg?.Length,
                        Version = face.Version,
                        PhotoData = jpeg ?? face.PhotoData,
                        CreatedAt = now
                    };
                    dbContext.FaceTemplates.Add(stored);
                    targetUser.FaceTemplates.Add(stored);
                }

                string? faceCmd = null;
                if (face.FaceIndex >= 50)
                {
                    if (HasTemplate(stored.Template))
                    {
                        faceCmd = ClockCommandBuilder.BuildUpdateFaceTemplateCommand(
                            targetUser.Pin, face.FaceIndex, stored.Template, stored.TemplateSize);
                    }
                }
                else if (targetIsVl)
                {
                    // ZAM70: BioTime pushes JPEG via BIOPHOTO Url, not BIODATA Type=9 (device -30).
                    if (jpeg is { Length: > 0 })
                    {
                        stored.PhotoData = jpeg;
                        faceCmd = ClockCommandBuilder.BuildUpdateBioPhotoCommand(
                            targetUser.Pin,
                            $"iclock/doc/biophoto/{stored.Id}.jpg");
                    }
                    else
                    {
                        logger.LogWarning(
                            "[CopyBiometrics] Skip BIODATA Type=9 to VL {SN} PIN={Pin} — no JPEG",
                            targetDevice.SerialNumber, targetUser.Pin);
                    }
                }
                else if (HasTemplate(stored.Template))
                {
                    faceCmd = ClockCommandBuilder.BuildUpdateVisibleFaceCommand(
                        targetUser.Pin,
                        stored.Template,
                        face.FaceIndex,
                        face.Version >= 51 ? face.Version : 58);
                }

                if (faceCmd != null)
                {
                    dbContext.DeviceCommands.Add(new DeviceCommand
                    {
                        DeviceId = request.TargetDeviceId,
                        CommandId = NextCommandId(),
                        Command = faceCmd,
                        Priority = 10,
                        Status = CommandStatus.Created,
                        CommandType = DeviceCommandTypes.PushFace,
                        ObjectReferenceId = targetUser.Id,
                        CreatedAt = now
                    });
                    facesQueued++;
                    commandsQueued++;
                }

                var picBytes = jpeg ?? stored.PhotoData;
                if (picBytes is { Length: > 0 })
                {
                    dbContext.DeviceCommands.Add(new DeviceCommand
                    {
                        DeviceId = request.TargetDeviceId,
                        CommandId = NextCommandId(),
                        Command = ClockCommandBuilder.BuildUpdateUserPicCommand(targetUser.Pin, picBytes),
                        Priority = 10,
                        Status = CommandStatus.Created,
                        CommandType = DeviceCommandTypes.PushUserPic,
                        ObjectReferenceId = targetUser.Id,
                        CreatedAt = now
                    });
                    commandsQueued++;
                }
            }

            usersCopied++;
        }

        var missingFpFile = request.IncludeFingerprints && fingerprintsQueued == 0;
        if (usersCopied == 0 || missingFpFile)
        {
            var pendingSync = await dbContext.DeviceCommands.AnyAsync(c =>
                c.DeviceId == request.SourceDeviceId
                && (c.CommandType == DeviceCommandTypes.SyncFingerprints
                    || c.CommandType == DeviceCommandTypes.SyncFaces)
                && c.Status == CommandStatus.Created);

            if (!pendingSync && request.IncludeFingerprints)
            {
                QueueBiometricPullCommands(
                    request.SourceDeviceId,
                    sourceUsers.Select(s => s.Pin),
                    now,
                    fingerprints: request.IncludeFingerprints,
                    faces: request.IncludeFaces,
                    stampOnly: sourceIsVl,
                    includeBiodata: sourceIsVl);
            }
        }

        if (usersCopied == 0)
        {
            await dbContext.SaveChangesAsync();
            return Ok(AppResponse<object>.Success(new
            {
                Title = "Đang lấy vân tay",
                Message =
                    $"Đã gửi lệnh lấy vân tay từ máy {sourceDevice.DeviceName}. Giữ máy nguồn online khoảng 1 phút — không cần bấm Copy lại, hệ thống tự đẩy sang máy {targetDevice.DeviceName} khi có file.",
                Phase = "waiting_fp",
                AutoRetry = true,
                RetryAfterSeconds = 8,
                NeedsTemplateSync = true,
                PartialCopy = true,
                SourceDevice = sourceDevice.DeviceName,
                TargetDevice = targetDevice.DeviceName,
                UsersCopied = 0,
                UsersSkipped = usersSkipped,
                CommandsQueued = 0
            }));
        }

        await dbContext.SaveChangesAsync();

        var waitingFp = request.IncludeFingerprints && fingerprintsQueued == 0;
        var title = waitingFp ? "Đang lấy vân tay" : "Đã copy xong";
        var message = waitingFp
            ? $"Đã gửi tên sang máy {targetDevice.DeviceName}. Đang lấy vân tay từ máy {sourceDevice.DeviceName}. Giữ cả hai máy online — không cần bấm Copy lại."
            : fingerprintsQueued > 0
                ? $"Đã copy tên và vân tay sang máy {targetDevice.DeviceName}. Máy đích online sẽ nhận trong vài giây."
                : $"Đã copy sang máy {targetDevice.DeviceName}. Máy đích online sẽ nhận trong vài giây.";

        logger.LogInformation(
            "[CopyBiometrics] {Source} → {Target}: users={Users} created={Created} skipped={Skipped} fp={Fp} face={Face} cmds={Cmds} waitingFp={Waiting}",
            sourceDevice.SerialNumber, targetDevice.SerialNumber,
            usersCopied, usersCreated, usersSkipped, fingerprintsQueued, facesQueued, commandsQueued, waitingFp);

        return Ok(AppResponse<object>.Success(new
        {
            Title = title,
            Message = message,
            Phase = waitingFp ? "waiting_fp" : "done",
            AutoRetry = waitingFp,
            RetryAfterSeconds = waitingFp ? 8 : 0,
            NeedsTemplateSync = waitingFp,
            PartialCopy = waitingFp,
            SourceDevice = sourceDevice.DeviceName,
            TargetDevice = targetDevice.DeviceName,
            UsersCopied = usersCopied,
            UsersCreated = usersCreated,
            UsersSkipped = usersSkipped,
            FingerprintsQueued = fingerprintsQueued,
            FacesQueued = facesQueued,
            CommandsQueued = commandsQueued
        }));
    }

    private void QueueBiometricPullCommands(
        Guid deviceId,
        IEnumerable<string> pins,
        DateTime now,
        bool fingerprints,
        bool faces,
        bool stampOnly,
        bool includeBiodata = false)
    {
        if (stampOnly)
        {
            if (fingerprints)
            {
                dbContext.DeviceCommands.Add(new DeviceCommand
                {
                    DeviceId = deviceId,
                    CommandId = NextCommandId(),
                    Command = AdmsEngineProfiles.StampSyncCommand,
                    Priority = 5,
                    Status = CommandStatus.Created,
                    CommandType = DeviceCommandTypes.SyncFingerprints,
                    CreatedAt = now
                });
            }

            if (faces)
            {
                dbContext.DeviceCommands.Add(new DeviceCommand
                {
                    DeviceId = deviceId,
                    CommandId = NextCommandId(),
                    Command = AdmsEngineProfiles.StampSyncCommand,
                    Priority = 5,
                    Status = CommandStatus.Created,
                    CommandType = DeviceCommandTypes.SyncFaces,
                    CreatedAt = now
                });
            }

            return;
        }

        if (fingerprints)
        {
            dbContext.DeviceCommands.Add(new DeviceCommand
            {
                DeviceId = deviceId,
                CommandId = NextCommandId(),
                Command = AdmsEngineProfiles.StampSyncCommand,
                Priority = 5,
                Status = CommandStatus.Created,
                CommandType = DeviceCommandTypes.SyncFingerprints,
                CreatedAt = now
            });
            dbContext.DeviceCommands.Add(new DeviceCommand
            {
                DeviceId = deviceId,
                CommandId = NextCommandId(),
                Command = ClockCommandBuilder.BuildGetFingerprintsCommand(),
                Priority = 5,
                Status = CommandStatus.Created,
                CommandType = DeviceCommandTypes.SyncFingerprints,
                CreatedAt = now
            });
            foreach (var pin in pins.Where(p => !string.IsNullOrWhiteSpace(p)).Distinct(StringComparer.Ordinal))
            {
                dbContext.DeviceCommands.Add(new DeviceCommand
                {
                    DeviceId = deviceId,
                    CommandId = NextCommandId(),
                    Command = ClockCommandBuilder.BuildGetFingerprintsForUserCommand(pin),
                    Priority = 6,
                    Status = CommandStatus.Created,
                    CommandType = DeviceCommandTypes.SyncFingerprints,
                    CreatedAt = now
                });
                if (includeBiodata)
                {
                    dbContext.DeviceCommands.Add(new DeviceCommand
                    {
                        DeviceId = deviceId,
                        CommandId = NextCommandId(),
                        Command = ClockCommandBuilder.BuildGetBiodataForUserCommand(pin),
                        Priority = 6,
                        Status = CommandStatus.Created,
                        CommandType = DeviceCommandTypes.SyncFingerprints,
                        CreatedAt = now
                    });
                }
            }
            if (includeBiodata)
            {
                dbContext.DeviceCommands.Add(new DeviceCommand
                {
                    DeviceId = deviceId,
                    CommandId = NextCommandId(),
                    Command = ClockCommandBuilder.BuildGetBiodataCommand(),
                    Priority = 5,
                    Status = CommandStatus.Created,
                    CommandType = DeviceCommandTypes.SyncFingerprints,
                    CreatedAt = now
                });
            }
        }

        if (faces)
        {
            dbContext.DeviceCommands.Add(new DeviceCommand
            {
                DeviceId = deviceId,
                CommandId = NextCommandId(),
                Command = ClockCommandBuilder.BuildGetBiodataCommand(),
                Priority = 5,
                Status = CommandStatus.Created,
                CommandType = DeviceCommandTypes.SyncFaces,
                CreatedAt = now
            });
            dbContext.DeviceCommands.Add(new DeviceCommand
            {
                DeviceId = deviceId,
                CommandId = NextCommandId(),
                Command = ClockCommandBuilder.BuildGetFacesCommand(),
                Priority = 5,
                Status = CommandStatus.Created,
                CommandType = DeviceCommandTypes.SyncFaces,
                CreatedAt = now
            });
        }
    }

}

