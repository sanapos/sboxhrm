using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using System.Text.RegularExpressions;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.IClock.CDataPost.Strategy;

/// <summary>
/// Handles biometric data uploads from device to server (fingerprint + face).
/// Fingerprint: FID 0-9. Face: FID >= 50.
/// Format: FINGERTMP PIN=xxx	FID=x	Size=xxx	Valid=x	TMP=base64data
/// </summary>
public class PostBiometricStrategy(IServiceProvider serviceProvider) : IPostStrategy
{
    private readonly IRepository<FingerprintTemplate> _fingerprintRepository = serviceProvider.GetRequiredService<IRepository<FingerprintTemplate>>();
    private readonly IRepository<FaceTemplate> _faceTemplateRepository = serviceProvider.GetRequiredService<IRepository<FaceTemplate>>();
    private readonly IRepository<DeviceUser> _deviceUserRepository = serviceProvider.GetRequiredService<IRepository<DeviceUser>>();
    private readonly IDeviceCmdService _deviceCmdService = serviceProvider.GetRequiredService<IDeviceCmdService>();
    private readonly ILogger<PostBiometricStrategy> _logger = serviceProvider.GetRequiredService<ILogger<PostBiometricStrategy>>();

    public async Task<string> ProcessDataAsync(Device device, string body)
    {
        _logger.LogWarning("========== FINGERPRINT DATA RECEIVED ==========");
        _logger.LogWarning("[PostBiometric] Device ID: {DeviceId}", device.Id);
        _logger.LogWarning("[PostBiometric] Device SN: {DeviceSN}", device.SerialNumber);
        _logger.LogWarning("[PostBiometric] Body Length: {Length} bytes", body?.Length ?? 0);
        _logger.LogWarning("[PostBiometric] Raw Body: {Body}", body);
        _logger.LogWarning("==============================================");

        var lines = body.Split('\n', StringSplitOptions.RemoveEmptyEntries);
        _logger.LogWarning("[PostBiometric] Found {LineCount} lines in body", lines.Length);
        
        var savedCount = 0;

        for (int i = 0; i < lines.Length; i++)
        {
            var line = lines[i];
            _logger.LogWarning("[PostBiometric] Processing line {LineNum}: {Line}", i + 1, line);
            
            try
            {
                if (line.StartsWith("FINGERTMP", StringComparison.OrdinalIgnoreCase) ||
                    line.Contains("FID=", StringComparison.OrdinalIgnoreCase))
                {
                    _logger.LogWarning("[PostBiometric] Line matches FINGERTMP pattern, processing...");
                    var saved = await ProcessFingerprintLineAsync(device, line);
                    if (saved)
                    {
                        savedCount++;
                    }
                }
                else
                {
                    _logger.LogWarning("[PostBiometric] Line does NOT match FINGERTMP pattern, skipping");
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "[PostBiometric] Error processing line: {Line}", line);
            }
        }

        _logger.LogWarning("[PostBiometric] Total fingerprints saved: {Count}", savedCount);

        if (savedCount > 0)
        {
            _logger.LogInformation("[PostBiometric] Saved {Count} biometric templates (fingerprint + face)", savedCount);
            await CompleteEnrollFingerprintCommandsAsync(device.Id);
            await CompleteEnrollFaceCommandsAsync(device.Id);
            await CompleteSyncFingerprintCommandsAsync(device.Id);
        }

        return ClockResponses.Ok;
    }

    private async Task<bool> ProcessFingerprintLineAsync(Device device, string line)
    {
        // Format: FINGERTMP PIN=xxx	FID=x	Size=xxx	Valid=x	TMP=base64data
        // hoặc: PIN=xxx	FID=x	Size=xxx	Valid=x	TMP=base64data
        
        _logger.LogWarning("[PostBiometric] Parsing fingerprint line...");
        var cleanedLine = line.Replace("\r", string.Empty).Trim();
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

        // Tìm DeviceUser theo PIN và DeviceId
        var deviceUser = await _deviceUserRepository.GetSingleAsync(
            u => u.Pin == pin && u.DeviceId == device.Id);

        if (deviceUser == null)
        {
            _logger.LogWarning("[PostBiometric] DeviceUser not found for PIN={Pin}, DeviceId={DeviceId}", pin, device.Id);
            return false;
        }

        // FID >= 50 = Face template, FID 0-9 = Fingerprint template
        if (fingerIndex.Value >= 50)
        {
            return await SaveFaceTemplateAsync(deviceUser, fingerIndex.Value, template, size);
        }
        else
        {
            return await SaveFingerprintTemplateAsync(deviceUser, fingerIndex.Value, template, size, valid);
        }
    }

    private async Task<bool> SaveFaceTemplateAsync(DeviceUser deviceUser, int faceIndex, string? template, int? size)
    {
        var existingFace = await _faceTemplateRepository.GetSingleAsync(
            f => f.EmployeeId == deviceUser.Id && f.FaceIndex == faceIndex);

        if (existingFace != null)
        {
            existingFace.Template = template ?? string.Empty;
            existingFace.TemplateSize = size;
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
                Version = 50,
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
            // Tạo mới fingerprint
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

    private async Task CompleteSyncFingerprintCommandsAsync(Guid deviceId)
    {
        try
        {
            var pendingCommands = await _deviceCmdService.GetPendingCommandsAsync(deviceId);
            var syncCommands = pendingCommands.Where(c => c.CommandType == DeviceCommandTypes.SyncFingerprints);

            foreach (var cmd in syncCommands)
            {
                await _deviceCmdService.UpdateCommandStatusAsync(cmd.Id, CommandStatus.Success);
                _logger.LogInformation("[PostBiometric] Completed SyncFingerprints command {CommandId}", cmd.Id);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[PostBiometric] Error completing SyncFingerprints commands for device {DeviceId}", deviceId);
        }
    }
}