using System.Text;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Queries.IClock.CDataGet;

public class CDataGetHandler(
    IDeviceService deviceService,
    IRepository<Attendance> attendanceRepository,
    IRepository<DeviceInfo> deviceInfoRepository,
    IDeviceCmdService deviceCmdService,
    ILogger<CDataGetHandler> logger
    ) : IQueryHandler<CDataGetQuery, string>
{
    public async Task<string> Handle(CDataGetQuery request, CancellationToken cancellationToken)
    {
        var sn = request.SN;
        
        var device = await deviceService.GetDeviceBySerialNumberAsync(sn);

        if (device == null)
        {
            return ClockResponses.Fail;
        }

        if(request.type != null && request.type == "time")
        {
            return DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss+07:00");
        }

        // Thiết bị chưa liên kết cửa hàng → trả config cơ bản để máy xác nhận đã kết nối server
        if (!device.StoreId.HasValue)
        {
            logger.LogInformation("[CDataGet] Device {SN} connected but not linked to any store. Returning basic config.", sn);
            return $"GET OPTION FROM: {sn}\r\n" +
                   "ATTLOGStamp=9999\r\n" +
                   "OPERLOGStamp=9999\r\n" +
                   "ErrorDelay=30\r\n" +
                   "Delay=5\r\n" +
                   "TransTimes=00:00;14:05\r\n" +
                   "TransInterval=30\r\n" +
                   "TransFlag=1111111100\r\n" +
                   "Realtime=1\r\n" +
                   "TimeZone=+07:00\r\n" +
                   "Timeout=20\r\n" +
                   "SyncTime=1\r\n" +
                   "ServerVer=2.0.4\r\n" +
                   "Encrypt=0";
        }

        // Heartbeat đã được cập nhật bởi DeviceActiveCheckBehaviour, không cần gọi lại

        // Nếu là PUSH device (có pushver), đảm bảo DeviceInfo tồn tại
        // DeviceInfo đầy đủ sẽ được cập nhật khi device POST table=options
        if (!string.IsNullOrEmpty(request.PushVer))
        {
            var existingInfo = await deviceInfoRepository.GetSingleAsync(di => di.DeviceId == device.Id);
            if (existingInfo == null)
            {
                var newInfo = new DeviceInfo
                {
                    DeviceId = device.Id,
                    FirmwareVersion = $"PUSH v{request.PushVer}"
                };
                await deviceInfoRepository.AddOrUpdateAsync(newInfo);
                logger.LogInformation("[CDataGet] Created initial DeviceInfo for PUSH device {SN}, pushver={PushVer}", sn, request.PushVer);
            }
        }

        // Kiểm tra xem có pending commands không (Created hoặc Sent)
        var pendingCommands = await deviceCmdService.GetPendingCommandsAsync(device.Id);
        var pendingList = pendingCommands.ToList();
        
        logger.LogInformation("[CDataGet] Device {SN} - Found {Count} pending commands (Created/Sent)", sn, pendingList.Count);
        foreach (var cmd in pendingList)
        {
            logger.LogInformation("[CDataGet] Pending command: Type={Type}, Status={Status}", cmd.CommandType, cmd.Status);
        }
        
        // Kiểm tra xem có pending SyncDeviceUsers command không
        var hasSyncUsersCommand = pendingList.Any(c => c.CommandType == DeviceCommandTypes.SyncDeviceUsers);
        
        // Kiểm tra xem có pending SyncAttendances command không
        var hasSyncAttendancesCommand = pendingList.Any(c => c.CommandType == DeviceCommandTypes.SyncAttendances);
        
        // Kiểm tra xem có pending SyncFingerprints command không
        var hasSyncFingerprintsCommand = pendingList.Any(c => c.CommandType == DeviceCommandTypes.SyncFingerprints);
        
        // QUAN TRỌNG: ATTLOGStamp
        // - Nếu có lệnh SyncAttendances, set ATTLOGStamp=0 để máy gửi lại TOÀN BỘ attendance
        // - Nếu không, lấy thời gian attendance cuối cùng để chỉ nhận dữ liệu mới
        string ATTLOGStamp;
        if (hasSyncAttendancesCommand)
        {
            ATTLOGStamp = "0";
            logger.LogInformation("[CDataGet] Device {SN} - SyncAttendances command pending, setting ATTLOGStamp=0 to request all attendance data", sn);
        }
        else
        {
            var lastAttendance = await attendanceRepository.GetLastOrDefaultAsync(
                keySelector: a => a.AttendanceTime,
                filter: a => a.DeviceId == device.Id,
                cancellationToken: cancellationToken);
            ATTLOGStamp = lastAttendance?.AttendanceTime.ToString(DameTimeFormats.DeviceDateTimeFormat) ?? "0";
        }
        
        // QUAN TRỌNG: OPERLOGStamp
        // - Nếu có lệnh SyncDeviceUsers, set OPERLOGStamp=0 để máy gửi lại toàn bộ user
        var operLogStamp = hasSyncUsersCommand ? "0" : "9999";
        
        // QUAN TRỌNG: BIODATAStamp
        // - Nếu có lệnh SyncFingerprints, set BIODATAStamp=0 để máy gửi lại toàn bộ biometric
        // - Nếu không, set BIODATAStamp=9999 để không sync biometric
        var bioDataStamp = hasSyncFingerprintsCommand ? "0" : "9999";
        
        if (hasSyncFingerprintsCommand)
        {
            logger.LogInformation("[CDataGet] Device {SN} - SyncFingerprints command pending, setting BIODATAStamp=0 to request all biometric data", sn);
        }
        
        logger.LogInformation("[CDataGet] Device {SN} - hasSyncUsersCommand={HasSyncUsers}, hasSyncAttendancesCommand={HasSyncAtt}, hasSyncFingerprintsCommand={HasSyncFP}, ATTLOGStamp={AttStamp}, OPERLOGStamp={OpStamp}, BIODATAStamp={BioStamp}", 
            sn, hasSyncUsersCommand, hasSyncAttendancesCommand, hasSyncFingerprintsCommand, ATTLOGStamp, operLogStamp, bioDataStamp);

        // TransInterval=60 = gửi heartbeat mỗi 60 giây (1 phút)
        // Delay=5 = delay 5 giây giữa các request
        // QUAN TRỌNG: Giảm TransInterval để device gọi lại nhanh hơn khi có lệnh mới
        var response = $"GET OPTION FROM: {sn}\r\n" +
                       $"ATTLOGStamp={ATTLOGStamp}\r\n" + 
                       $"OPERLOGStamp={operLogStamp}\r\n" + 
                       $"BIODATAStamp={bioDataStamp}\r\n" +
                       $"FINGERTMPStamp={bioDataStamp}\r\n" +
                       "ErrorDelay=30\r\n" +
                       "Delay=3\r\n" +
                       "TransTimes=00:00;14:05\r\n" +
                       "TransInterval=10\r\n" +
                       "TransFlag=1111111100\r\n" +
                       "Realtime=1\r\n" +
                       "TimeZone=+07:00\r\n" +
                       "Timeout=20\r\n" +
                       "SyncTime=1\r\n" +
                       "ServerVer=2.0.4\r\n" +
                       "Encrypt=0";

        // Nhúng inline commands cho face/PUSH protocol devices (pushver != null)
        // Thiết bị PUSH có thể không gọi /iclock/getrequest → cần gửi lệnh qua cdata response
        // Complete SyncDeviceUsers/SyncAttendances immediately — stamp-based approach handles data sync
        // SyncFingerprints: giữ lại cho GetRequestHandler gửi command, nhưng timeout sau 2 phút
        foreach (var cmd in pendingList.Where(c => c.CommandType == DeviceCommandTypes.SyncDeviceUsers
            || c.CommandType == DeviceCommandTypes.SyncAttendances))
        {
            await deviceCmdService.UpdateCommandStatusAsync(cmd.Id, CommandStatus.Success);
            logger.LogInformation("[CDataGet] Completed sync command for device {SN}: Type={Type}", sn, cmd.CommandType);
        }
        
        // Auto-complete stale SyncFingerprints commands (Sent > 2 minutes ago)
        // V8 firmware devices don't POST biometric data via ADMS, so the command stays Sent forever
        foreach (var cmd in pendingList.Where(c => c.CommandType == DeviceCommandTypes.SyncFingerprints
            && c.Status == CommandStatus.Sent && c.SentAt.HasValue
            && c.SentAt.Value < DateTime.Now.AddMinutes(-2)))
        {
            await deviceCmdService.UpdateCommandStatusAsync(cmd.Id, CommandStatus.Success);
            logger.LogInformation("[CDataGet] Auto-completed stale SyncFingerprints command for device {SN} (sent at {SentAt})", sn, cmd.SentAt);
        }

        var inlineCommands = pendingList
            .Where(c => c.Status == CommandStatus.Created
                && c.CommandType != DeviceCommandTypes.SyncDeviceUsers
                && c.CommandType != DeviceCommandTypes.SyncAttendances
                && c.CommandType != DeviceCommandTypes.SyncFingerprints)
            .OrderByDescending(c => c.Priority)
            .ToList();

        if (inlineCommands.Count > 0)
        {
            var sb = new StringBuilder(response);
            foreach (var cmd in inlineCommands)
            {
                sb.Append($"\r\nC:{cmd.CommandId}:{cmd.Command}");
                
                // Enrollment commands: mark as Sent — they need time for the device to process
                // PostBiometricStrategy will mark them as Success when biometric data arrives
                var isEnrollment = cmd.CommandType == DeviceCommandTypes.EnrollFingerprint
                    || cmd.CommandType == DeviceCommandTypes.EnrollFace;
                var newStatus = isEnrollment ? CommandStatus.Sent : CommandStatus.Success;
                await deviceCmdService.UpdateCommandStatusAsync(cmd.Id, newStatus);
                logger.LogInformation("[CDataGet] Embedded inline command for {SN}: Type={Type}, Status={Status}, Cmd={Cmd}", sn, cmd.CommandType, newStatus, cmd.Command);
            }
            response = sb.ToString();
        }

        return response;
    }
}