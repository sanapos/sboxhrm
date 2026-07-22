using System.Collections.Concurrent;
using System.Text;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Queries.IClock.GetRequest;

public class GetRequestHandler(
    IDeviceService deviceService,
    IDeviceCmdService deviceCmdService,
    IRepository<Attendance> attendanceRepository,
    IRepository<DeviceInfo> deviceInfoRepository,
    ILogger<GetRequestHandler> logger
    ) : ICommandHandler<GetRequestQuery, string>
{
    private static readonly ConcurrentDictionary<string, DateTime> LastManualSyncConfigPushUtc = new();

    public async Task<string> Handle(GetRequestQuery request, CancellationToken cancellationToken)
    {
        var sn = request.SN;

        var device = await deviceService.GetDeviceBySerialNumberAsync(sn);
        if (device == null)
        {
            logger.LogWarning("[GetRequest] Device not found for SN: {SN}", sn);
            return ClockResponses.Ok;
        }

        if (!device.StoreId.HasValue)
        {
            logger.LogInformation("[GetRequest] Device {SN} not linked to any store. No commands.", sn);
            return ClockResponses.Ok;
        }

        logger.LogWarning("[GetRequest] Device found: SN={SN}, DeviceId={DeviceId}", sn, device.Id);

        if (!string.IsNullOrEmpty(request.Info))
        {
            await UpdateDeviceInfoAsync(device.Id, request.Info);
        }

        await AutoCompleteStaleSyncAttendancesAsync(device.Id, sn);
        await AutoCompleteStampSyncMarkersAsync(device.Id, sn);

        var commands = await deviceCmdService.GetCreatedCommandsAsync(device.Id);
        var deviceCommands = commands.ToList();

        logger.LogWarning("[GetRequest] Device {SN} (ID: {DeviceId}) - Found {Count} pending commands", sn, device.Id, deviceCommands.Count);

        if (deviceCommands.Count > 0)
        {
            var response = new StringBuilder();
            foreach (var command in deviceCommands.OrderByDescending(c => c.Priority))
            {
                // PreferStampSync: keep Sync* pending for OPERLOG/ATTLOG Stamp=0 — never send to device.
                if (AdmsEngineProfiles.ShouldSkipDeviceDelivery(command.CommandType, command.Command))
                {
                    logger.LogInformation(
                        "[GetRequest] Skipping stamp-sync marker for {SN}: Id={Id} Type={Type}",
                        sn, command.Id, command.CommandType);
                    continue;
                }

                var cmd = ClockCommandBuilder.FormatWireCommand(command.CommandId, command.Command, command.CommandType);
                // Match agap.top wire: CRLF between command lines (AppendLine is LF-only on Linux).
                response.Append(cmd).Append("\r\n");

                logger.LogInformation("[GetRequest] Sending command to device {SN}: {Cmd}", sn, cmd);

                await deviceCmdService.UpdateCommandStatusAsync(command.Id, CommandStatus.Sent);
            }

            if (response.Length > 0)
                return response.ToString();
        }

        // Máy getrequest-only: nhúng GET OPTION với Stamp=0 khi Sync user/ATT pending.
        var pushConfig = await TryBuildManualSyncPushConfigAsync(device.Id, sn, cancellationToken);
        if (pushConfig != null)
        {
            logger.LogInformation(
                "[GetRequest] Device {SN}: pushing GET OPTION for manual stamp sync",
                sn);
            return pushConfig;
        }

        return ClockResponses.Ok;
    }

    /// <summary>
    /// Máy chỉ poll getrequest (không GET cdata) — ép ATTLOGStamp/OPERLOGStamp=0 khi đồng bộ thủ công.
    /// </summary>
    private async Task<string?> TryBuildManualSyncPushConfigAsync(
        Guid deviceId,
        string sn,
        CancellationToken cancellationToken)
    {
        var pending = (await deviceCmdService.GetPendingCommandsAsync(deviceId)).ToList();

        // Stamp=0 storms interrupt remote enroll UI (face/FP) on Android/ZAM devices.
        if (pending.Any(c =>
                (c.CommandType is DeviceCommandTypes.EnrollFace
                    or DeviceCommandTypes.EnrollFingerprint)
                && (c.Status == CommandStatus.Created || c.Status == CommandStatus.Sent)))
        {
            return null;
        }

        var syncAtt = pending.Any(c => c.CommandType == DeviceCommandTypes.SyncAttendances);
        var syncUsers = pending.Any(c => c.CommandType == DeviceCommandTypes.SyncDeviceUsers);
        if (!syncAtt && !syncUsers)
            return null;

        if (LastManualSyncConfigPushUtc.TryGetValue(sn, out var lastPush)
            && DateTime.UtcNow - lastPush < TimeSpan.FromSeconds(20))
        {
            return null;
        }

        LastManualSyncConfigPushUtc[sn] = DateTime.UtcNow;

        var attStamp = syncAtt
            ? "0"
            : await AttendanceLogStampResolver.ResolveAsync(
                attendanceRepository, deviceId, fullSyncRequested: false, cancellationToken);
        var operStamp = syncUsers ? "0" : "9999";

        logger.LogWarning(
            "[GetRequest] Stamp config for {SN}: SyncUsers={Users} SyncAtt={Att} OPERLOGStamp={Op} ATTLOGStamp={AttStamp}",
            sn, syncUsers, syncAtt, operStamp, attStamp);

        return PushDeviceConfigBuilder.BuildGetOptionResponse(sn, attStamp, operStamp);
    }

    /// <summary>
    /// Stamp sync markers stay Created (not delivered). Complete after window so stamp=0
    /// has time to pull OPERLOG/ATTLOG; longer than before because getrequest-only devices are slow.
    /// Also clear stuck Sent Sync* (legacy DATA QUERY) — Status=Sent forever keeps OPERLOGStamp=0
    /// and prevents face enroll UI from staying on screen.
    /// </summary>
    private async Task AutoCompleteStampSyncMarkersAsync(Guid deviceId, string sn)
    {
        var pending = await deviceCmdService.GetPendingCommandsAsync(deviceId);
        var cutoff = DateTime.UtcNow.AddMinutes(-10);
        var stuckCutoff = DateTime.UtcNow.AddMinutes(-2);
        foreach (var cmd in pending.Where(c =>
                     c.CommandType is DeviceCommandTypes.SyncDeviceUsers
                         or DeviceCommandTypes.SyncAttendances
                         or DeviceCommandTypes.SyncFingerprints
                         or DeviceCommandTypes.SyncFaces))
        {
            var created = cmd.CreatedAt;
            var anchor = cmd.SentAt ?? created;
            if (anchor.Kind == DateTimeKind.Unspecified)
                anchor = DateTime.SpecifyKind(anchor, DateTimeKind.Utc);
            var utc = anchor.ToUniversalTime();

            var isMarker = AdmsEngineProfiles.ShouldSkipDeviceDelivery(cmd.CommandType, cmd.Command);
            var isStuckSentQuery = cmd.Status == CommandStatus.Sent && !isMarker;

            if (isMarker && utc > cutoff)
                continue;
            if (isStuckSentQuery && utc > stuckCutoff)
                continue;
            if (!isMarker && !isStuckSentQuery)
                continue;

            await deviceCmdService.UpdateCommandStatusAsync(cmd.Id, CommandStatus.Success);
            logger.LogInformation(
                "[GetRequest] Auto-completed sync {Type} {CommandId} for {SN} (marker={Marker}, stuckSent={Stuck})",
                cmd.CommandType, cmd.Id, sn, isMarker, isStuckSentQuery);
        }
    }

    private async Task AutoCompleteStaleSyncAttendancesAsync(Guid deviceId, string sn)
    {
        var serverCount = await attendanceRepository.CountAsync(a => a.DeviceId == deviceId);
        var deviceInfo = await deviceInfoRepository.GetSingleAsync(di => di.DeviceId == deviceId);
        var localCount = deviceInfo?.AttendanceCount ?? 0;

        var pending = await deviceCmdService.GetPendingCommandsAsync(deviceId);
        foreach (var cmd in pending.Where(c =>
                     c.CommandType == DeviceCommandTypes.SyncAttendances
                     && c.Status == CommandStatus.Sent
                     && c.SentAt.HasValue
                     && !AdmsEngineProfiles.ShouldSkipDeviceDelivery(c.CommandType, c.Command)))
        {
            if (!AttendanceBulkSyncTracker.ShouldAutoCompleteStaleSync(
                    deviceId, cmd.SentAt!.Value, localCount, serverCount))
            {
                continue;
            }

            await deviceCmdService.UpdateCommandStatusAsync(cmd.Id, CommandStatus.Success);
            logger.LogInformation(
                "[GetRequest] Auto-completed SyncAttendances {CommandId} for {SN} (server={Server}, machine={Machine})",
                cmd.Id, sn, serverCount, localCount);
        }
    }

    private async Task UpdateDeviceInfoAsync(Guid deviceId, string info)
    {
        var deviceInfo = await deviceInfoRepository.GetSingleAsync(di => di.DeviceId == deviceId) ?? new DeviceInfo
        {
            DeviceId = deviceId
        };

        var infoParts = info.Split(',', StringSplitOptions.None);

        if (infoParts.Length > 0 && !string.IsNullOrWhiteSpace(infoParts[0]))
        {
            deviceInfo.FirmwareVersion = infoParts[0].Trim();
        }

        if (infoParts.Length > 1 && int.TryParse(infoParts[1], out var enrolledUsers))
        {
            deviceInfo.EnrolledUserCount = enrolledUsers;
        }

        if (infoParts.Length > 2 && int.TryParse(infoParts[2], out var fingerprintCount))
        {
            deviceInfo.FingerprintCount = fingerprintCount;
        }

        if (infoParts.Length > 3 && int.TryParse(infoParts[3], out var attendanceCount))
        {
            deviceInfo.AttendanceCount = attendanceCount;
        }

        if (infoParts.Length > 4 && !string.IsNullOrWhiteSpace(infoParts[4]))
        {
            deviceInfo.DeviceIp = infoParts[4].Trim();
        }

        if (infoParts.Length > 5 && !string.IsNullOrWhiteSpace(infoParts[5]))
        {
            deviceInfo.FingerprintVersion = infoParts[5].Trim();
        }

        if (infoParts.Length > 6 && !string.IsNullOrWhiteSpace(infoParts[6]))
        {
            deviceInfo.FaceVersion = infoParts[6].Trim();
        }

        if (infoParts.Length > 7 && !string.IsNullOrWhiteSpace(infoParts[7]))
        {
            deviceInfo.FaceTemplateCount = infoParts[7].Trim();
        }

        if (infoParts.Length > 8 && !string.IsNullOrWhiteSpace(infoParts[8]))
        {
            deviceInfo.DevSupportData = infoParts[8].Trim();
        }

        await deviceInfoRepository.AddOrUpdateAsync(deviceInfo);
    }
}
