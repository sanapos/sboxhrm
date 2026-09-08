using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using System.Text.RegularExpressions;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Commands.IClock.CDataPost.Strategy;

/// <summary>
/// Handles biometric data uploads from device to server (fingerprint + face).
/// Fingerprint: FID 0-9. Face: FID >= 50.
/// Format: FINGERTMP PIN=xxx	FID=x	Size=xxx	Valid=x	TMP=base64data
/// </summary>
public class PostBiometricStrategy(IServiceProvider serviceProvider, string table = "") : IPostStrategy
{
    private readonly IRepository<FingerprintTemplate> _fingerprintRepository = serviceProvider.GetRequiredService<IRepository<FingerprintTemplate>>();
    private readonly IRepository<FaceTemplate> _faceTemplateRepository = serviceProvider.GetRequiredService<IRepository<FaceTemplate>>();
    private readonly IRepository<DeviceUser> _deviceUserRepository = serviceProvider.GetRequiredService<IRepository<DeviceUser>>();
    private readonly IDeviceCmdService _deviceCmdService = serviceProvider.GetRequiredService<IDeviceCmdService>();
    private readonly ILogger<PostBiometricStrategy> _logger = serviceProvider.GetRequiredService<ILogger<PostBiometricStrategy>>();
    private readonly string _table = table ?? "";

    public async Task<string> ProcessDataAsync(Device device, string body)
    {
        if (string.IsNullOrWhiteSpace(body)
            && _table is "BIOPHOTO" or "USERPIC" or "ATTPHOTO")
        {
            await CompleteSyncFaceCommandsAsync(device.Id);
            return ClockResponses.Ok;
        }

        if (_table == "ATTPHOTO")
            return ClockResponses.Ok;

        _logger.LogWarning("========== FINGERPRINT DATA RECEIVED ==========");
        _logger.LogWarning("[PostBiometric] Device ID: {DeviceId} Table={Table}", device.Id, _table);
        _logger.LogWarning("[PostBiometric] Device SN: {DeviceSN}", device.SerialNumber);
        _logger.LogWarning("[PostBiometric] Body Length: {Length} bytes", body?.Length ?? 0);
        if ((body?.Length ?? 0) <= 400)
            _logger.LogWarning("[PostBiometric] Raw Body: {Body}", body);
        _logger.LogWarning("==============================================");

        var lines = (body ?? "").Split('\n', StringSplitOptions.RemoveEmptyEntries);
        _logger.LogWarning("[PostBiometric] Found {LineCount} lines in body", lines.Length);
        
        var savedCount = 0;

        for (int i = 0; i < lines.Length; i++)
        {
            var line = lines[i];
            if (line.Length <= 240)
                _logger.LogWarning("[PostBiometric] Processing line {LineNum}: {Line}", i + 1, line);
            
            try
            {
                var isBioPhoto = _table == "BIOPHOTO"
                    || line.StartsWith("BIOPHOTO", StringComparison.OrdinalIgnoreCase);
                var isUserPic = _table == "USERPIC"
                    || line.StartsWith("USERPIC", StringComparison.OrdinalIgnoreCase);
                var isBioData = line.StartsWith("BIODATA", StringComparison.OrdinalIgnoreCase)
                    || (line.Contains("Type=", StringComparison.OrdinalIgnoreCase)
                        && line.Contains("Tmp=", StringComparison.OrdinalIgnoreCase));
                var isFingerTmp = line.StartsWith("FINGERTMP", StringComparison.OrdinalIgnoreCase)
                    || line.Contains("FID=", StringComparison.OrdinalIgnoreCase);

                bool saved;
                if (isBioPhoto || isUserPic)
                {
                    saved = await ProcessBioPhotoLineAsync(device, line);
                }
                else if (isBioData && !line.Contains("FID=", StringComparison.OrdinalIgnoreCase))
                {
                    _logger.LogWarning("[PostBiometric] Line matches BIODATA pattern, processing...");
                    saved = await ProcessBioDataLineAsync(device, line);
                }
                else if (isFingerTmp)
                {
                    _logger.LogWarning("[PostBiometric] Line matches FINGERTMP pattern, processing...");
                    saved = await ProcessFingerprintLineAsync(device, line);
                }
                else
                {
                    _logger.LogWarning("[PostBiometric] Line does NOT match biometric pattern, skipping");
                    saved = false;
                }

                if (saved)
                {
                    savedCount++;
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "[PostBiometric] Error processing line {LineNum}", i + 1);
            }
        }

        _logger.LogWarning("[PostBiometric] Total fingerprints saved: {Count}", savedCount);

        if (savedCount > 0)
        {
            _logger.LogInformation("[PostBiometric] Saved {Count} biometric templates (fingerprint + face)", savedCount);
            await CompleteEnrollFingerprintCommandsAsync(device.Id);
            await CompleteEnrollFaceCommandsAsync(device.Id);
            await CompleteSyncFaceCommandsAsync(device.Id);
        }

        return ClockResponses.Ok;
    }

    private async Task<bool> ProcessFingerprintLineAsync(Device device, string line)
    {
        // Format: FINGERTMP PIN=xxx	FID=x	Size=xxx	Valid=x	TMP=base64data
        // hoặc: PIN=xxx	FID=x	Size=xxx	Valid=x	TMP=base64data
        
        _logger.LogWarning("[PostBiometric] Parsing fingerprint line...");
        var cleanedLine = line.Replace("\r", string.Empty).Trim();
        if (cleanedLine.StartsWith("FINGERTMP", StringComparison.OrdinalIgnoreCase))
            cleanedLine = cleanedLine["FINGERTMP".Length..].Trim();
        else if (cleanedLine.StartsWith("FP", StringComparison.OrdinalIgnoreCase)
                 && cleanedLine.Length > 2
                 && (cleanedLine[2] is ' ' or '\t'))
            cleanedLine = cleanedLine[2..].Trim();
        string[] parts;
        if (cleanedLine.Contains('\t'))
        {
            parts = cleanedLine.Split('\t', StringSplitOptions.RemoveEmptyEntries);
        }
        else
        {
            parts = Regex.Split(cleanedLine, "\\s+").Where(p => !string.IsNullOrWhiteSpace(p)).ToArray();
        }
        _logger.LogWarning("[PostBiometric] Split into {PartCount} parts: {Parts}", parts.Length, string.Join(" | ", parts.Take(5)));
        
        string? pin = null;
        int? fingerIndex = null;
        int? size = null;
        int? valid = null;
        string? template = null;

        foreach (var part in parts)
        {
            var kv = part.Split('=', 2);
            if (kv.Length != 2) continue;

            var key = kv[0].Trim().ToUpperInvariant();
            var value = kv[1].Trim();

            switch (key)
            {
                case "PIN":
                    pin = value;
                    _logger.LogWarning("[PostBiometric] Found PIN: {PIN}", pin);
                    break;
                case "FID":
                    if (int.TryParse(value, out var fid))
                    {
                        fingerIndex = fid;
                        _logger.LogWarning("[PostBiometric] Found FID: {FID}", fingerIndex);
                    }
                    break;
                case "SIZE":
                    if (int.TryParse(value, out var s))
                    {
                        size = s;
                        _logger.LogWarning("[PostBiometric] Found SIZE: {Size}", size);
                    }
                    break;
                case "VALID":
                    if (int.TryParse(value, out var v))
                    {
                        valid = v;
                        _logger.LogWarning("[PostBiometric] Found VALID: {Valid}", valid);
                    }
                    break;
                case "TMP":
                    template = value;
                    _logger.LogWarning("[PostBiometric] Found TMP template, length: {Length}", template?.Length ?? 0);
                    break;
            }
        }

        _logger.LogWarning("[PostBiometric] Parsed values - PIN={PIN}, FID={FID}, Size={Size}, Valid={Valid}, TMP Length={TMPLen}",
            pin, fingerIndex, size, valid, template?.Length ?? 0);

        if (string.IsNullOrEmpty(pin) || fingerIndex == null)
        {
            _logger.LogWarning("[PostBiometric] Missing PIN or FID in line: {Line}", line);
            return false;
        }

        // Tìm DeviceUser theo PIN và DeviceId (001 == 1)
        var deviceUser = await DeviceUserPins.FindOnDeviceAsync(
            _deviceUserRepository, device.Id, pin);

        if (deviceUser == null)
        {
            _logger.LogWarning("[PostBiometric] DeviceUser not found for PIN={Pin}, DeviceId={DeviceId}", pin, device.Id);
            return false;
        }

        // FID >= 50 = Face template, FID 0-9 = Fingerprint template
        if (fingerIndex.Value >= 50)
        {
            return await SaveFaceTemplateAsync(deviceUser, fingerIndex.Value, template, size, 50);
        }
        else
        {
            if (!DeviceUserPins.IsCopyableTemplate(template))
            {
                _logger.LogWarning(
                    "[PostBiometric] Ignore non-copyable TMP for PIN={Pin} FID={Fid} len={Len}",
                    pin, fingerIndex, template?.Length ?? 0);
                return false;
            }

            var savedFp = await SaveFingerprintTemplateAsync(deviceUser, fingerIndex.Value, template, size, valid);
            if (savedFp)
            {
                await CompleteSyncFingerprintCommandsAsync(device.Id, pin);
                await FanOutFingerprintToStoreClocksAsync(
                    device, deviceUser, fingerIndex.Value, template!, size, valid);
            }
            return savedFp;
        }
    }

    /// <summary>
    /// VL face / generic biodata: Pin=… Type=9 Index=0 Tmp=…
    /// Type 1 = fingerprint; Type 8/9 = face.
    /// </summary>
    private async Task<bool> ProcessBioDataLineAsync(Device device, string line)
    {
        var cleanedLine = line.Replace("\r", string.Empty).Trim();
        if (cleanedLine.StartsWith("BIODATA", StringComparison.OrdinalIgnoreCase))
            cleanedLine = cleanedLine["BIODATA".Length..].Trim();

        string[] parts = cleanedLine.Contains('\t')
            ? cleanedLine.Split('\t', StringSplitOptions.RemoveEmptyEntries)
            : Regex.Split(cleanedLine, "\\s+").Where(p => !string.IsNullOrWhiteSpace(p)).ToArray();

        string? pin = null;
        int index = 0;
        int type = 9;
        int? size = null;
        int? valid = null;
        int majorVer = 58;
        string? template = null;

        foreach (var part in parts)
        {
            var kv = part.Split('=', 2);
            if (kv.Length != 2) continue;
            var key = kv[0].Trim();
            var value = kv[1].Trim();
            switch (key.ToUpperInvariant())
            {
                case "PIN":
                    pin = value;
                    break;
                case "INDEX":
                    if (int.TryParse(value, out var idx))
                        index = idx;
                    break;
                case "TYPE":
                    int.TryParse(value, out type);
                    break;
                case "SIZE":
                    if (int.TryParse(value, out var s)) size = s;
                    break;
                case "VALID":
                    if (int.TryParse(value, out var v)) valid = v;
                    break;
                case "MAJORVER":
                    int.TryParse(value, out majorVer);
                    break;
                case "TMP":
                    template = value;
                    break;
            }
        }

        if (string.IsNullOrEmpty(pin) || string.IsNullOrEmpty(template))
        {
            _logger.LogWarning("[PostBiometric] BIODATA missing Pin or Tmp");
            return false;
        }

        var deviceUser = await DeviceUserPins.FindOnDeviceAsync(
            _deviceUserRepository, device.Id, pin);
        if (deviceUser == null)
        {
            _logger.LogWarning("[PostBiometric] DeviceUser not found for PIN={Pin}", pin);
            return false;
        }

        // Type 8 = NIR face, Type 9 = visible-light face
        if (type is 8 or 9)
        {
            var jpeg = BioPhotoCodec.TryGetJpeg(template, null);
            return await SaveFaceTemplateAsync(deviceUser, index, template, size, majorVer, jpeg);
        }

        return await SaveFingerprintTemplateAsync(deviceUser, index, template, size, valid);
    }

    private async Task<bool> ProcessBioPhotoLineAsync(Device device, string line)
    {
        var cleanedLine = line.Replace("\r", string.Empty).Trim();
        string[] parts = cleanedLine.Contains('\t')
            ? cleanedLine.Split('\t', StringSplitOptions.RemoveEmptyEntries)
            : Regex.Split(cleanedLine, "\\s+").Where(p => !string.IsNullOrWhiteSpace(p)).ToArray();

        string? pin = null;
        string? content = null;
        int type = 9;

        foreach (var part in parts)
        {
            var kv = part.Split('=', 2);
            if (kv.Length != 2) continue;
            var key = kv[0].Trim();
            var value = kv[1].Trim();
            switch (key.ToUpperInvariant())
            {
                case "PIN":
                    pin = value;
                    break;
                case "TYPE":
                    int.TryParse(value, out type);
                    break;
                case "CONTENT":
                    content = value;
                    break;
            }
        }

        if (string.IsNullOrEmpty(pin) || string.IsNullOrEmpty(content))
        {
            _logger.LogWarning("[PostBiometric] BIOPHOTO/USERPIC missing PIN or Content");
            return false;
        }

        var deviceUser = await DeviceUserPins.FindOnDeviceAsync(
            _deviceUserRepository, device.Id, pin);
        if (deviceUser == null)
        {
            _logger.LogWarning("[PostBiometric] DeviceUser not found for PIN={Pin}", pin);
            return false;
        }

        var jpeg = BioPhotoCodec.TryGetJpeg(content, null);
        if (jpeg == null)
        {
            try { jpeg = Convert.FromBase64String(content); }
            catch (FormatException) { jpeg = null; }
        }

        if (jpeg == null || jpeg.Length < 80)
        {
            _logger.LogWarning("[PostBiometric] BIOPHOTO/USERPIC PIN={Pin} not a usable JPEG", pin);
            return false;
        }

        var b64 = Convert.ToBase64String(jpeg);
        var version = type is 8 or 9 ? 58 : 50;
        return await SaveFaceTemplateAsync(deviceUser, faceIndex: 0, b64, jpeg.Length, version, jpeg);
    }

    private async Task<bool> SaveFaceTemplateAsync(
        DeviceUser deviceUser,
        int faceIndex,
        string? template,
        int? size,
        int version = 50,
        byte[]? photoData = null)
    {
        var existingFace = await _faceTemplateRepository.GetSingleAsync(
            f => f.EmployeeId == deviceUser.Id && f.FaceIndex == faceIndex);

        if (existingFace != null)
        {
            existingFace.Template = template ?? string.Empty;
            existingFace.TemplateSize = size;
            existingFace.Version = version;
            if (photoData is { Length: > 0 })
                existingFace.PhotoData = photoData;
            existingFace.UpdatedAt = DateTime.UtcNow;
            await _faceTemplateRepository.UpdateAsync(existingFace);
            _logger.LogWarning("[PostBiometric] Updated face template: User={UserName}, FaceIndex={Index}", 
                deviceUser.Name, faceIndex);
        }
        else
        {
            var face = new FaceTemplate
            {
                Id = Guid.NewGuid(),
                EmployeeId = deviceUser.Id,
                FaceIndex = faceIndex,
                Template = template ?? string.Empty,
                TemplateSize = size,
                Version = version,
                PhotoData = photoData,
                CreatedAt = DateTime.UtcNow
            };
            await _faceTemplateRepository.AddAsync(face);
            _logger.LogWarning("[PostBiometric] Created new face template: User={UserName}, FaceIndex={Index}", 
                deviceUser.Name, faceIndex);
        }
        return true;
    }

    private async Task<bool> SaveFingerprintTemplateAsync(DeviceUser deviceUser, int fingerIndex, string? template, int? size, int? valid)
    {
        var existingFingerprint = await _fingerprintRepository.GetSingleAsync(
            f => f.EmployeeId == deviceUser.Id && f.FingerIndex == fingerIndex);

        if (existingFingerprint != null)
        {
            existingFingerprint.Template = template ?? string.Empty;
            existingFingerprint.TemplateSize = size;
            existingFingerprint.Quality = valid;
            existingFingerprint.UpdatedAt = DateTime.UtcNow;
            
            await _fingerprintRepository.UpdateAsync(existingFingerprint);
            _logger.LogInformation("[PostBiometric] Updated fingerprint: User={UserName}, FingerIndex={Index}", 
                deviceUser.Name, fingerIndex);
            return true;
        }
        else
        {
            var fingerprint = new FingerprintTemplate
            {
                Id = Guid.NewGuid(),
                EmployeeId = deviceUser.Id,
                FingerIndex = fingerIndex,
                Template = template ?? string.Empty,
                TemplateSize = size,
                Quality = valid,
                Version = 10,
                CreatedAt = DateTime.UtcNow
            };

            await _fingerprintRepository.AddAsync(fingerprint);
            _logger.LogInformation("[PostBiometric] Created new fingerprint: User={UserName}, FingerIndex={Index}", 
                deviceUser.Name, fingerIndex);
            return true;
        }
    }

    private async Task CompleteEnrollFingerprintCommandsAsync(Guid deviceId)
    {
        try
        {
            var pendingCommands = await _deviceCmdService.GetPendingCommandsAsync(deviceId);
            var enrollCommands = pendingCommands.Where(c => c.CommandType == DeviceCommandTypes.EnrollFingerprint);
            
            foreach (var cmd in enrollCommands)
            {
                await _deviceCmdService.UpdateCommandStatusAsync(cmd.Id, CommandStatus.Success);
                _logger.LogInformation("[PostBiometric] Completed EnrollFingerprint command {CommandId}", cmd.Id);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[PostBiometric] Error completing EnrollFingerprint commands for device {DeviceId}", deviceId);
        }
    }

    private async Task CompleteEnrollFaceCommandsAsync(Guid deviceId)
    {
        try
        {
            var pendingCommands = await _deviceCmdService.GetPendingCommandsAsync(deviceId);
            var enrollFaceCommands = pendingCommands.Where(c => c.CommandType == DeviceCommandTypes.EnrollFace);

            foreach (var cmd in enrollFaceCommands)
            {
                await _deviceCmdService.UpdateCommandStatusAsync(cmd.Id, CommandStatus.Success);
                _logger.LogInformation("[PostBiometric] Completed EnrollFace command {CommandId}", cmd.Id);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[PostBiometric] Error completing EnrollFace commands for device {DeviceId}", deviceId);
        }
    }

    private async Task CompleteSyncFingerprintCommandsAsync(Guid deviceId, string pin)
    {
        try
        {
            var pendingCommands = await _deviceCmdService.GetPendingCommandsAsync(deviceId);
            var syncCommands = pendingCommands.Where(c => c.CommandType == DeviceCommandTypes.SyncFingerprints);

            foreach (var cmd in syncCommands)
            {
                var cmdPin = ParseCommandPin(cmd.Command);
                if (cmdPin == null || !DeviceUserPins.EqualsPin(cmdPin, pin))
                    continue;

                await _deviceCmdService.UpdateCommandStatusAsync(cmd.Id, CommandStatus.Success);
                _logger.LogInformation(
                    "[PostBiometric] Completed SyncFingerprints {CommandId} for PIN={Pin}",
                    cmd.Id, pin);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[PostBiometric] Error completing SyncFingerprints commands for device {DeviceId}", deviceId);
        }
    }

    private async Task FanOutFingerprintToStoreClocksAsync(
        Device sourceDevice,
        DeviceUser sourceUser,
        int fingerIndex,
        string template,
        int? size,
        int? valid)
    {
        if (!sourceDevice.StoreId.HasValue || !DeviceUserPins.IsCopyableTemplate(template))
            return;

        try
        {
            var deviceRepo = serviceProvider.GetRequiredService<IRepository<Device>>();
            var cmdRepo = serviceProvider.GetRequiredService<IRepository<DeviceCommand>>();
            var others = await deviceRepo.GetAllAsync(d =>
                d.StoreId == sourceDevice.StoreId && d.Id != sourceDevice.Id);

            foreach (var other in others)
            {
                var targetUser = await DeviceUserPins.FindOnDeviceAsync(
                    _deviceUserRepository, other.Id, sourceUser.Pin);
                if (targetUser == null)
                    continue;

                var existing = await _fingerprintRepository.GetSingleAsync(
                    f => f.EmployeeId == targetUser.Id && f.FingerIndex == fingerIndex);
                if (existing != null && DeviceUserPins.IsCopyableTemplate(existing.Template))
                    continue;

                await SaveFingerprintTemplateAsync(targetUser, fingerIndex, template, size, valid);

                var pending = await cmdRepo.GetAllAsync(c =>
                    c.DeviceId == other.Id
                    && c.CommandType == DeviceCommandTypes.PushFingerprint
                    && (c.Status == CommandStatus.Created || c.Status == CommandStatus.Sent));
                var alreadyQueued = pending.Any(c =>
                    c.Command.Contains($"FID={fingerIndex}", StringComparison.Ordinal)
                    && DeviceUserPins.EqualsPin(ParseCommandPin(c.Command), targetUser.Pin));
                if (alreadyQueued)
                    continue;

                await cmdRepo.AddAsync(new DeviceCommand
                {
                    DeviceId = other.Id,
                    CommandId = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() % 90_000 + 10_000,
                    Command = ClockCommandBuilder.BuildUpdateFingerprintCommand(
                        targetUser.Pin, fingerIndex, template, size, valid ?? 1),
                    Priority = 10,
                    Status = CommandStatus.Created,
                    CommandType = DeviceCommandTypes.PushFingerprint,
                    ObjectReferenceId = targetUser.Id,
                    CreatedAt = DateTime.UtcNow
                });
                _logger.LogWarning(
                    "[PostBiometric] Auto-push FP PIN={Pin} FID={Fid} {Src} → {Dst}",
                    targetUser.Pin, fingerIndex, sourceDevice.DeviceName, other.DeviceName);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[PostBiometric] Fan-out fingerprint failed for PIN={Pin}", sourceUser.Pin);
        }
    }

    private static string? ParseCommandPin(string? command)
    {
        if (string.IsNullOrWhiteSpace(command)) return null;
        var match = Regex.Match(command, @"PIN=([^\t\s]+)", RegexOptions.IgnoreCase);
        return match.Success ? match.Groups[1].Value : null;
    }

    private async Task CompleteSyncFaceCommandsAsync(Guid deviceId)
    {
        try
        {
            var pendingCommands = await _deviceCmdService.GetPendingCommandsAsync(deviceId);
            var syncCommands = pendingCommands.Where(c => c.CommandType == DeviceCommandTypes.SyncFaces);

            foreach (var cmd in syncCommands)
            {
                await _deviceCmdService.UpdateCommandStatusAsync(cmd.Id, CommandStatus.Success);
                _logger.LogInformation("[PostBiometric] Completed SyncFaces command {CommandId}", cmd.Id);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[PostBiometric] Error completing SyncFaces commands for device {DeviceId}", deviceId);
        }
    }
}